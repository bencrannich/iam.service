#! /bin/sh

set -e

## This script is used to bootstrap a development stack and is invoked by the
## top-level Makefile. Its primary purpose is to bring up the certificate
## authorities before other services are ready.

log()
{
	printf "%s: %s\n" "bootstrap-docker" "$*" >&2
}

#. ./dev/dev.env

DATADIR="$(cd dev && pwd)/data"
DS_REALM_ORGNAME="Example Enterprises"
DS_REALM_DN="O=Example Enterprises"
DS_REALM_DNS="example.com"
DS_REALM_KRB="EXAMPLE.COM"
IAM_USER_NAME=me

export DS_REALM_ORGNAME DS_REALM_DN DS_REALM_DNS DS_REALM_KRB

log "storing instance data in ${DATADIR}"
mkdir -p ${DATADIR} ${DATADIR}/tls ${DATADIR}/secrets

# In production deployment, we use two independent hardware-managed root CA keys,
# A1 and B1, which are used to cross-sign a common intermediate, X1, which is then
# used to issue certificates for production subsidiary CAs within the realm.
#
# For development, we generate A1, B1, and X1, and spin up a StepCA instance
# to issue certificates from X1 as a stand-in for the realm offline intermediate.

log "generating the ${DS_REALM_ORGNAME} Root A1 certificate authority"
cat >${DATADIR}/openssl-root-a1.cnf <<EOF
[default]
default_md=sha512
string_mask=utf8only

[req]
prompt=no
utf8=yes
distinguished_name=root_a1_dn
x509_extensions=root_a1_extensions

[root_a1_dn]
CN=${DS_REALM_ORGNAME} Root A1
O=${DS_REALM_ORGNAME}

[root_a1_extensions]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
#extendedKeyUsage=OCSPSigning
#authorityKeyIdentifier=keyid:always,issuer:always
subjectKeyIdentifier=hash
#subjectAltName=DNS:root-ca
#authorityInfoAccess=OSCP;...
#authorityInfoAccess=caIssuers;...
#crlDistributionPoints=URI:
#certificatePolicies=...
EOF

# Generate the certificate serial number for A1
serial_a1=$(openssl rand -hex 16)
# Generate a 2048-bit RSA key
openssl genrsa -out ${DATADIR}/secrets/root-a1.key.pem 2048
# Wrap the key in a self-signed certificate using the above configuration
openssl req -batch -config ${DATADIR}/openssl-root-a1.cnf -set_serial 0x${serial_a1} -key ${DATADIR}/secrets/root-a1.key.pem -new -x509 -out ${DATADIR}/tls/root-a1.pem
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
#subjectAltName=DNS:root-ca
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

set -x

# Sign A1 with B1
openssl x509 -sha512 -req -extfile ${DATADIR}/openssl-root-b1.cnf -extensions root_b1_extensions -set_serial 0x${serial_a1} -CA ${DATADIR}/tls/root-b1.pem -CAkey ${DATADIR}/secrets/root-b1.key.pem -in ${DATADIR}/tls/root-a1.req.pem -out ${DATADIR}/tls/root-a1.b1.pem
# Sign B1 with A1
openssl x509 -sha512 -req -extfile ${DATADIR}/openssl-root-a1.cnf -extensions root_a1_extensions -set_serial 0x${serial_b1} -CA ${DATADIR}/tls/root-a1.pem -CAkey ${DATADIR}/secrets/root-a1.key.pem -in ${DATADIR}/tls/root-b1.req.pem -out ${DATADIR}/tls/root-b1.a1.pem

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
#subjectAltName=DNS:root-ca
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
openssl x509 -sha512 -req -extfile ${DATADIR}/openssl-inter-x1.cnf -extensions inter_x1_extensions -set_serial 0x${serial_x1} -CA ${DATADIR}/tls/root-a1.pem -CAkey ${DATADIR}/secrets/root-a1.key.pem -in ${DATADIR}/tls/inter-x1.req.pem -out ${DATADIR}/tls/inter-x1.a1.pem
# Sign X1 with B1
openssl x509 -sha512 -req -extfile ${DATADIR}/openssl-inter-x1.cnf -extensions inter_x1_extensions -set_serial 0x${serial_x1} -CA ${DATADIR}/tls/root-b1.pem -CAkey ${DATADIR}/secrets/root-b1.key.pem -in ${DATADIR}/tls/inter-x1.req.pem -out ${DATADIR}/tls/inter-x1.b1.pem

# Merge X1
cat ${DATADIR}/tls/inter-x1.a1.pem ${DATADIR}/tls/inter-x1.b1.pem > ${DATADIR}/tls/inter-x1.pem

# Store human-readable versions of each individual certificate, along with the combined set
cp ${DATADIR}/tls/roots.txt ${DATADIR}/tls/inter.txt
cp ${DATADIR}/tls/roots.pem ${DATADIR}/tls/inter.pem
for cert in inter-x1.a1 inter-x1.b1 ; do
	openssl x509 -in ${DATADIR}/tls/${cert}.pem -text -out ${DATADIR}/tls/${cert}.txt
	openssl x509 -in ${DATADIR}/tls/${cert}.pem -text >> ${DATADIR}/tls/roots.txt
	cat ${DATADIR}/tls/${cert}.pem >> ${DATADIR}/tls/roots.pem
done

openssl x509 -in ${DATADIR}/tls/inter-x1.pem -noout -text > ${DATADIR}/tls/inter-x1.txt

log "initialising development certificate authority for ${DS_REALM_DN}..."

## Initialise the "root" CA

# Generate a StepCA configuration, and then replace the certificates and keys with our
# own
mkdir -p ${DATADIR}/root-ca
docker compose "$@" run \
	-e DOCKER_STEPCA_INIT_NAME="${DS_REALM_ORGNAME}" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="root-ca" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i root-ca \
	true
# StepCA can't handle multiple certificates in the root or intermediate
# certificate files, so we just use the A1 branch, but that doesn't
# impact the cross-validity of the certificates that it issues.
cp ${DATADIR}/tls/root-a1.pem ${DATADIR}/root-ca/certs/root_ca.crt
rm -f ${DATADIR}/root-ca/secrets/root_ca_key
cp ${DATADIR}/tls/inter-x1.a1.pem ${DATADIR}/root-ca/certs/intermediate_ca.crt
# Use openssl ec to safely strip out the EC PARAMETERS section
openssl ec -in ${DATADIR}/secrets/inter-x1.key.pem -out ${DATADIR}/root-ca/secrets/intermediate_ca_key
# StepCA uses the fingerprint, which is the SHA256 of the DER-encoded root
# certificate, as a sense check when bootstrapping
ROOT_FINGERPRINT=$(openssl x509 -in ${DATADIR}/root-ca/certs/root_ca.crt -outform der | openssl sha256)
# An alternative is using step certificate fingerprint via Docker
#ROOT_FINGERPRINT=$(docker compose "$@" run -it root-ca step certificate fingerprint certs/root_ca.crt)
echo "${ROOT_FINGERPRINT}" > ${DATADIR}/tls/root-ca.fingerprint
cat >${DATADIR}/root-ca/config/defaults.json <<EOF
{
  "ca-url": "https://root-ca:9000",
  "fingerprint": "${ROOT_FINGERPRINT}",
  "root": "/home/step/certs/root_ca.crt",
  "redirect-url": ""
}
EOF
cp ${DATADIR}/root-ca/secrets/password ${DATADIR}/secrets/root-ca.password
docker compose "$@" create root-ca
docker compose "$@" start root-ca

## Initialise the infrastructure services CA

# This CA will issue server certificates to the directory service and
# Kerberos KDC. The former enables LDAPS connections, whilst the
# latter allows PKINIT 

mkdir -p ${DATADIR}/infra-ca
docker compose "$@" run \
	-e DOCKER_STEPCA_INIT_NAME="${DS_REALM_ORGNAME} Infrastructure Services" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="infra-ca" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i infra-ca \
	true
INFRA_FINGERPRINT=$(openssl x509 -in ${DATADIR}/infra-ca/certs/root_ca.crt -outform der | openssl sha256)
echo "${INFRA_FINGERPRINT}" > ${DATADIR}/tls/infra-ca.fingerprint
cp ${DATADIR}/infra-ca/secrets/password ${DATADIR}/secrets/infra-ca.password
docker compose "$@" create infra-ca
docker compose "$@" start infra-ca

## Initialise the user CA

# This CA will issue certificates to user account-holders of the directory

mkdir -p ${DATADIR}/user-ca
docker compose "$@" run \
	-e DOCKER_STEPCA_INIT_NAME="${DS_REALM_ORGNAME} User" \
	-e DOCKER_STEPCA_INIT_DNS_NAMES="user-ca" \
	-e DOCKER_STEPCA_INIT_PROVISIONER_NAME=bootstrap \
	-i user-ca \
	true
USER_FINGERPRINT=$(openssl x509 -in ${DATADIR}/infra-ca/certs/root_ca.crt -outform der | openssl sha256)
USER_FINGERPRINT=$(docker compose "$@" run -it infra-ca step certificate fingerprint certs/root_ca.crt)
echo "${USER_FINGERPRINT}" > ${DATADIR}/tls/user-ca.fingerprint
cp ${DATADIR}/user-ca/secrets/password ${DATADIR}/secrets/user-ca.password

docker compose "$@" create user-ca
docker compose "$@" start user-ca
