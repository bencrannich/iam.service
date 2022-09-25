#! /bin/sh

set -e

## This script is used to bootstrap a development stack and is invoked by the
## top-level Makefile. Its primary purpose is to bring up the certificate
## authorities before other services are ready and write some *.env files
## into this directory which are referenced by dev.yaml. 

#. ./dev/dev.env

TOP="$(pwd)"
DATADIR="$(cd dev && pwd)/data"
DS_REALM_ORGNAME="Example Enterprises"
DS_REALM_DN="O=Example Enterprises"
DS_REALM_DNS="example.com"
DS_REALM_KRB="EXAMPLE.COM"
IAM_USER_NAME=me

export DS_REALM_ORGNAME DS_REALM_DN DS_REALM_DNS DS_REALM_KRB

log()
{
	printf "%s: %s\n" "bootstrap-docker" "$*" >&2
}

compose()
{
	${TOP}/dev-compose "$@"
}

bootstrap_kms()
{
	compose create kms
	compose start kms
	sleep 1
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault operator init > ${DATADIR}/secrets/vault.txt
	KMS_UNSEAL_KEY_1=$( grep -E '^Unseal Key 1:' ${DATADIR}/secrets/vault.txt | cut -c15- )
	KMS_UNSEAL_KEY_2=$( grep -E '^Unseal Key 2:' ${DATADIR}/secrets/vault.txt | cut -c15- )
	KMS_UNSEAL_KEY_3=$( grep -E '^Unseal Key 3:' ${DATADIR}/secrets/vault.txt | cut -c15- )
	KMS_ROOT_TOKEN=$( grep -E '^Initial Root Token: ' ${DATADIR}/secrets/vault.txt | cut -c21- )
	rm ${DATADIR}/secrets/vault.txt
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault operator unseal "${KMS_UNSEAL_KEY_1}" >/dev/null
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault operator unseal "${KMS_UNSEAL_KEY_2}" >/dev/null
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault operator unseal "${KMS_UNSEAL_KEY_3}" >/dev/null
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault login "${KMS_ROOT_TOKEN}" >/dev/null
	unset KMS_UNSEAL_KEY_1 KMS_UNSEAL_KEY_2 KMS_UNSEAL_KEY_3
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault secrets enable -path=secret -version=2 kv
	compose exec -e VAULT_ADDR='http://127.0.0.1:8200' kms vault secrets enable pki
}

bootstrap_root_ca()
{
	ca_name="$1"
	ca_title="$2"
	ca_serial="$3"
	mkdir -p ${DATADIR}/${ca_name}
	compose run \
		-e CA_NAME="${ca_name}" \
		-e CA_SERIAL="${ca_serial}" \
		-i ${ca_name}
}

bootstrap_online_ca()
{
	ca_name="$1"
	ca_title="$2"
	mkdir -p ${DATADIR}/${ca_name}
	cp ${DATADIR}/inter-ca/${ca_name}.password ${DATADIR}/${ca_name}
	compose run \
	-e DOCKER_STEPCA_INIT_NAME="${ca_title}" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="${ca_name}" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i ${ca_name} \
	/bin/sh -xc "mkdir -p .step && \
	cd / && \
	STEP= CONFIGPATH= STEPPATH= step ca bootstrap --ca-url https://inter-ca:9000 --fingerprint ${ROOT_FINGERPRINT} && \
	cd .. && \
	cp /home/step/.step/certs/root_ca.crt /home/step/certs/root_ca.crt && \
	rm -f /home/step/secrets/root_ca_key && \
	STEP= CONFIGPATH= STEPPATH= \
		step ca certificate '${ca_title}' /home/step/certs/intermediate_ca.crt /home/step/secrets/intermediate_ca_key \
			--password-file /home/step/secrets/password \
			--provisioner ${ca_name} \
			--provisioner-password-file /home/step/${ca_name}.password \
			--force"
	cat >${DATADIR}/${ca_name}/config/defaults.json <<EOF
{
  "ca-url": "https://${ca_name}:9000",
  "fingerprint": "${ROOT_FINGERPRINT}",
  "root": "/home/step/certs/root_ca.crt",
  "redirect-url": ""
}
EOF
}

log "storing instance data in ${DATADIR}"
mkdir -p ${DATADIR} ${DATADIR}/tls ${DATADIR}/secrets
chmod 700 ${DATADIR}/secrets

# In production deployment, we use two independent hardware-managed root CA keys,
# A1 and B1, which are used to cross-sign a common intermediate, X1, also stored
# on a hardware token, and which is then used to issue certificates for
# online subsidiary CAs within the realm.
#
# For development, we generate A1, B1, and X1, and spin up an additional StepCA
# instance to issue certificates from X1 as a stand-in for the real (offline)
# intermediate.
log "generating the ${DS_REALM_ORGNAME} Root A1 certificate authority"

# Generate the certificate serial number for A1
serial_a1=$(openssl rand -hex 16)
bootstrap_root_ca root-a1 "${DS_REALM_ORGNAME} Root A1" "${serial_a1}"
exit 100

# Generate a 2048-bit RSA key
openssl genrsa -out ${DATADIR}/secrets/root-a1.key.pem 2048
# Wrap the key in a self-signed certificate using the above configuration
openssl req -batch -config ${DATADIR}/../root-a1.cnf -set_serial 0x${serial_a1} -key ${DATADIR}/secrets/root-a1.key.pem -new -x509 -out ${DATADIR}/tls/root-a1.pem
# Generate a CSR from the certificate for cross-signing
openssl x509 -x509toreq -in ${DATADIR}/tls/root-a1.pem -signkey ${DATADIR}/secrets/root-a1.key.pem -out ${DATADIR}/tls/root-a1.req.pem

log "generating the ${DS_REALM_ORGNAME} Root B1 certificate authority"
cat >${DATADIR}/openssl-root-b1.cnf <<EOF
[default]
default_md=sha512
string_mask=utf8only

[req]
prompt=no
utf8=yes
distinguished_name=root_b1_dn
x509_extensions=root_b1_extensions

[root_b1_dn]
CN=${DS_REALM_ORGNAME} Root B1
O=${DS_REALM_ORGNAME}

[root_b1_extensions]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
#extendedKeyUsage=OCSPSigning
#authorityKeyIdentifier=keyid:always,issuer:always
subjectKeyIdentifier=hash
#subjectAltName=DNS:inter-ca
#authorityInfoAccess=OSCP;...
#authorityInfoAccess=caIssuers;...
#crlDistributionPoints=URI:
#certificatePolicies=...

[inter_x1_extensions]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign,digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer:always
#extendedKeyUsage=OCSPSigning
#subjectAltName=DNS:inter-ca
#authorityInfoAccess=OSCP;...
#authorityInfoAccess=caIssuers;...
#crlDistributionPoints=URI:
#certificatePolicies=...
EOF

# Generate the certificate serial number for B1
serial_b1=$(openssl rand -hex 16)
# Generate a Prime256v1 elliptic curve key
openssl ecparam -genkey -name prime256v1 -out ${DATADIR}/secrets/root-b1.key.pem
# Wrap the key in a self-signed certificate using the above configuration
openssl req -batch -config ${DATADIR}/openssl-root-b1.cnf  -set_serial 0x${serial_b1} -key ${DATADIR}/secrets/root-b1.key.pem -new -x509 -out ${DATADIR}/tls/root-b1.pem
# Generate a CSR from the certificate for cross-signing
openssl x509 -x509toreq -in ${DATADIR}/tls/root-b1.pem -signkey ${DATADIR}/secrets/root-b1.key.pem -out ${DATADIR}/tls/root-b1.req.pem

## Cross-sign the roots

log "Cross-signing root certificates"

# Sign A1 with B1
openssl x509 -sha512 -req -extfile ${DATADIR}/openssl-root-b1.cnf -extensions root_b1_extensions -set_serial 0x${serial_a1} -CA ${DATADIR}/tls/root-b1.pem -CAkey ${DATADIR}/secrets/root-b1.key.pem -in ${DATADIR}/tls/root-a1.req.pem -out ${DATADIR}/tls/root-a1.b1.pem
# Sign B1 with A1
openssl x509 -sha512 -req -extfile ${DATADIR}/../root-a1.cnf -extensions root_a1_extensions -set_serial 0x${serial_b1} -CA ${DATADIR}/tls/root-a1.pem -CAkey ${DATADIR}/secrets/root-a1.key.pem -in ${DATADIR}/tls/root-b1.req.pem -out ${DATADIR}/tls/root-b1.a1.pem

# Store human-readable versions of each individual certificate and the combined set
for cert in root-a1 root-a1.b1 root-b1 root-b1.a1 ; do
	openssl x509 -in ${DATADIR}/tls/${cert}.pem -text -out ${DATADIR}/tls/${cert}.txt
	openssl x509 -in ${DATADIR}/tls/${cert}.pem -text >> ${DATADIR}/tls/roots.txt
	cat ${DATADIR}/tls/${cert}.pem >> ${DATADIR}/tls/roots.pem
done

## Generate the X1 intermediate

log "generating the ${DS_REALM_ORGNAME} Intermediate X1 certificate authority"
cat >${DATADIR}/openssl-inter-x1.cnf <<EOF
[req]
prompt=no
utf8=yes
distinguished_name=inter_x1_dn

[inter_x1_dn]
CN=${DS_REALM_ORGNAME} Intermediate X1
O=${DS_REALM_ORGNAME}

[inter_x1_extensions]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign,digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer:always
#extendedKeyUsage=OCSPSigning
#subjectAltName=DNS:inter-ca
#authorityInfoAccess=OSCP;...
#authorityInfoAccess=caIssuers;...
#crlDistributionPoints=URI:
#certificatePolicies=...
EOF

# Generate the certificate serial number for X1
serial_x1=$(openssl rand -hex 16)

# Generate the X1 request
openssl ecparam -genkey -name prime256v1 -out ${DATADIR}/secrets/inter-x1.key.pem
openssl req -batch -config ${DATADIR}/openssl-inter-x1.cnf -key ${DATADIR}/secrets/inter-x1.key.pem -new -out ${DATADIR}/tls/inter-x1.req.pem
# Sign X1 with A1
openssl x509 -sha512 -req -extfile ${DATADIR}/../root-a1.cnf -extensions inter_x1_extensions -set_serial 0x${serial_x1} -CA ${DATADIR}/tls/root-a1.pem -CAkey ${DATADIR}/secrets/root-a1.key.pem -in ${DATADIR}/tls/inter-x1.req.pem -out ${DATADIR}/tls/inter-x1.a1.pem
# Sign X1 with B1
openssl x509 -sha512 -req -extfile ${DATADIR}/openssl-inter-x1.cnf -extensions inter_x1_extensions -set_serial 0x${serial_x1} -CA ${DATADIR}/tls/root-b1.pem -CAkey ${DATADIR}/secrets/root-b1.key.pem -in ${DATADIR}/tls/inter-x1.req.pem -out ${DATADIR}/tls/inter-x1.b1.pem

# Merge X1
cat ${DATADIR}/tls/inter-x1.a1.pem ${DATADIR}/tls/inter-x1.b1.pem > ${DATADIR}/tls/inter-x1.pem

# Store human-readable versions of each individual certificate, along with the combined set
cp ${DATADIR}/tls/roots.txt ${DATADIR}/tls/inter.txt
cp ${DATADIR}/tls/roots.pem ${DATADIR}/tls/inter.pem
for cert in inter-x1.a1 inter-x1.b1 ; do
	openssl x509 -in ${DATADIR}/tls/${cert}.pem -text -out ${DATADIR}/tls/${cert}.txt
	openssl x509 -in ${DATADIR}/tls/${cert}.pem -text >> ${DATADIR}/tls/inter.txt
	cat ${DATADIR}/tls/${cert}.pem >> ${DATADIR}/tls/inter.pem
done

openssl x509 -in ${DATADIR}/tls/inter-x1.pem -noout -text > ${DATADIR}/tls/inter-x1.txt

log "initialising KMS"
bootstrap_kms

log "initialising online intermediate certificate authority for ${DS_REALM_DN}..."

## Initialise the "root" CA

# Generate a StepCA configuration, and then replace the certificates and keys with our
# own
mkdir -p ${DATADIR}/inter-ca
compose run \
	-e DOCKER_STEPCA_INIT_NAME="${DS_REALM_ORGNAME}" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="inter-ca" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i inter-ca \
	true
# StepCA can't handle multiple certificates in the root or intermediate
# certificate files, so we just use the A1 branch, but that doesn't
# impact the cross-validity of the certificates that it issues.
cp ${DATADIR}/tls/root-a1.pem ${DATADIR}/inter-ca/certs/root_ca.crt
rm -f ${DATADIR}/inter-ca/secrets/root_ca_key
cp ${DATADIR}/tls/inter-x1.a1.pem ${DATADIR}/inter-ca/certs/intermediate_ca.crt
# Use openssl ec to safely strip out the EC PARAMETERS section
openssl ec -in ${DATADIR}/secrets/inter-x1.key.pem -out ${DATADIR}/inter-ca/secrets/intermediate_ca_key
# StepCA uses the fingerprint, which is the SHA256 of the DER-encoded root
# certificate, as a sense check when bootstrapping
ROOT_FINGERPRINT=$(openssl x509 -in ${DATADIR}/inter-ca/certs/root_ca.crt -outform der | openssl sha256)
# An alternative is using step certificate fingerprint via Docker
#ROOT_FINGERPRINT=$(compose run -it inter-ca step certificate fingerprint certs/root_ca.crt)
echo "${ROOT_FINGERPRINT}" > ${DATADIR}/tls/inter-ca.fingerprint
cat >${DATADIR}/inter-ca/config/defaults.json <<EOF
{
  "ca-url": "https://inter-ca:9000",
  "fingerprint": "${ROOT_FINGERPRINT}",
  "root": "/home/step/certs/root_ca.crt",
  "redirect-url": ""
}
EOF
cp ${DATADIR}/inter-ca/secrets/password ${DATADIR}/secrets/inter-ca.password



compose create inter-ca
compose start inter-ca

# Now the X1 CA is running, create provisioners for bootstrapping the
# subsidiary CAs
openssl rand -hex 16 -out ${DATADIR}/inter-ca/prov-ca.password
openssl rand -hex 16 -out ${DATADIR}/inter-ca/infra-ca.password
openssl rand -hex 16 -out ${DATADIR}/inter-ca/user-ca.password

# Create X.509 certificate templates for each of the provisioners
cat >${DATADIR}/inter-ca/templates/prov-ca.tpl <<EOF
{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Example Enterprises Provisioning CA"
	},
	"keyUsage": [ "certSign", "crlSign", "digitalSignature" ],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 1
	}
}
EOF
cat >${DATADIR}/inter-ca/templates/infra-ca.tpl <<EOF
{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Example Enterprises Infrastructure Services CA"
	},
	"keyUsage": [ "certSign", "crlSign", "digitalSignature" ],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 1
	}
}
EOF
cat >${DATADIR}/inter-ca/templates/user-ca.tpl <<EOF
{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Example Enterprises User CA"
	},
	"keyUsage": [ "certSign", "crlSign", "digitalSignature" ],
	"basicConstraints": {
		"isCA": true,
		"maxPathLen": 1
	}
}
EOF
# Create the provisioners themselves
compose exec -it inter-ca step ca provisioner add prov-ca --type JWK --create --password-file=prov-ca.password --x509-template ./templates/prov-ca.tpl
compose exec -it inter-ca step ca provisioner add infra-ca --type JWK --create --password-file=infra-ca.password --x509-template ./templates/infra-ca.tpl
compose exec -it inter-ca step ca provisioner add user-ca --type JWK --create --password-file=user-ca.password --x509-template ./templates/user-ca.tpl
# Reload the CA
compose kill -s HUP inter-ca


## Initialise the provisioning CA

# This CA issues certificates to hosts which allows them basic access to
# network services. Typically, provisioning certificates are then used
# as part of the process of authenticating as a stronger identity. For
# example, the provisioning certificate issued to the directory service
# container allows it to provision the service certificate used by
# OpenLDAP

bootstrap_online_ca prov-ca "${DS_REALM_ORGNAME} Provisioning"

## Initialise the infrastructure services CA

# This CA will issue server certificates to the directory service and
# Kerberos KDC. The former enables LDAPS connections, whilst the
# latter allows PKINIT

mkdir -p ${DATADIR}/infra-ca
cp ${DATADIR}/inter-ca/infra-ca.password ${DATADIR}/infra-ca
compose run \
	-e DOCKER_STEPCA_INIT_NAME="${DS_REALM_ORGNAME} Infrastructure Services" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="infra-ca" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i infra-ca \
	/bin/sh -xc "mkdir -p .step && \
	cd / && \
	STEP= CONFIGPATH= STEPPATH= step ca bootstrap --ca-url https://inter-ca:9000 --fingerprint ${ROOT_FINGERPRINT} && \
	cd .. && \
	cp /home/step/.step/certs/root_ca.crt /home/step/certs/root_ca.crt && \
	rm -f /home/step/secrets/root_ca_key && \
	STEP= CONFIGPATH= STEPPATH= \
		step ca certificate Infrastructure /home/step/certs/intermediate_ca.crt /home/step/secrets/intermediate_ca_key \
			--password-file /home/step/secrets/password \
			--provisioner infra-ca \
			--provisioner-password-file /home/step/infra-ca.password \
			--force"
cat >${DATADIR}/infra-ca/config/defaults.json <<EOF
{
  "ca-url": "https://infra-ca:9000",
  "fingerprint": "${ROOT_FINGERPRINT}",
  "root": "/home/step/certs/root_ca.crt",
  "redirect-url": ""
}
EOF
cat >${DATADIR}/infra-ca/templates/ds.tpl <<EOF
{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Directory Service"
	},
{{- if typeIs "*rsa.PublicKey" .Insecure.CR.PublicKey }}
    "keyUsage": ["keyEncipherment", "digitalSignature"],
{{- else }}
    "keyUsage": ["digitalSignature"],
{{- end }}
	"extendedKeyUsage": [ "serverAuth", "clientAuth" ],
	"dnsNames": [
		"ds", "ds.EXAMPLE.COM"
	]
}
EOF
cat >${DATADIR}/infra-ca/templates/kdc.tpl <<EOF
{
	"subject": {
		"organization": "Example Enterprises",
		"commonName": "Kerberos KDC"
	},
{{- if typeIs "*rsa.PublicKey" .Insecure.CR.PublicKey }}
    "keyUsage": ["keyEncipherment", "digitalSignature"],
{{- else }}
    "keyUsage": ["digitalSignature"],
{{- end }}
	"extendedKeyUsage": [ "serverAuth", "clientAuth" ],
	"dnsNames": [
		"kdc", "kdc.EXAMPLE.COM"
	]
}
EOF
cp ${DATADIR}/infra-ca/secrets/password ${DATADIR}/secrets/infra-ca.password
openssl rand -hex 16 -out ${DATADIR}/infra-ca/ds.password
openssl rand -hex 16 -out ${DATADIR}/infra-ca/kdc.password
compose create infra-ca
compose start infra-ca
compose exec -it infra-ca step crypto jwk create ds.pub.json ds.priv.json --password-file=ds.password
compose exec -it infra-ca step crypto jwk create kdc.pub.json kdc.priv.json --password-file=kdc.password
compose exec -it infra-ca step ca provisioner add ds --type JWK --public-key ds.pub.json --private-key ds.priv.json --password-file=ds.password --x509-template ./templates/ds.tpl
compose exec -it infra-ca step ca provisioner add kdc --type JWK --public-key kdc.pub.json --private-key kdc.priv.json --password-file=kdc.password --x509-template ./templates/kdc.tpl
compose kill -s HUP infra-ca

cat >dev/ds-step.env <<EOF
STEP_CA_URL=https://infra-ca:9000
STEP_CA_FINGERPRINT=${ROOT_FINGERPRINT}
STEP_CA_PROVISIONER=ds
STEP_CA_PROVISIONER_PASSWORD=$(cat ${DATADIR}/infra-ca/ds.password)
EOF

## Initialise the user CA

# This CA will issue certificates to user account-holders of the directory

mkdir -p ${DATADIR}/user-ca
cp ${DATADIR}/inter-ca/user-ca.password ${DATADIR}/user-ca
compose run \
	-e DOCKER_STEPCA_INIT_NAME="${DS_REALM_ORGNAME} User" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="user-ca" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i user-ca \
	/bin/sh -xc "mkdir -p .step && \
	cd / && \
	STEP= CONFIGPATH= STEPPATH= step ca bootstrap --ca-url https://inter-ca:9000 --fingerprint ${ROOT_FINGERPRINT} && \
	cd .. && \
	cp /home/step/.step/certs/root_ca.crt /home/step/certs/root_ca.crt && \
	rm -f /home/step/secrets/root_ca_key && \
	STEP= CONFIGPATH= STEPPATH= \
		step ca certificate Infrastructure /home/step/certs/intermediate_ca.crt /home/step/secrets/intermediate_ca_key \
			--password-file /home/step/secrets/password \
			--provisioner user-ca \
			--provisioner-password-file /home/step/user-ca.password \
			--force"
cat >${DATADIR}/user-ca/config/defaults.json <<EOF
{
  "ca-url": "https://user-ca:9000",
  "fingerprint": "${ROOT_FINGERPRINT}",
  "root": "/home/step/certs/root_ca.crt",
  "redirect-url": ""
}
EOF
cp ${DATADIR}/user-ca/secrets/password ${DATADIR}/secrets/user-ca.password
compose create user-ca
compose start user-ca
