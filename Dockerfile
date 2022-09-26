FROM debian:stable-slim AS core

WORKDIR /root

ENV LC_ALL C
ENV TZ=UTC
ENV DEBIAN_FRONTEND noninteractive

RUN echo 'APT::Install-Recommends "0"; \n\
APT::Install-Suggests "0"; \n\
APT::Get::Assume-Yes "true"; \n\
' > /etc/apt/apt.conf.d/noninteractive
ONBUILD RUN apt-get update

FROM smallstep/step-cli as step

## SoftHSM server

FROM core AS hsm

RUN apt-get install -qq gnutls-bin p11-kit softhsm 

COPY dev/hsm/server /server
ENTRYPOINT [ "/server" ]
VOLUME [ "/run/p11-kit", "/var/lib/softhsm/tokens" ]
## Offline Certificate Authority (CA) container

FROM core AS offline-ca

RUN apt-get install -qq openssl gnutls-bin p11-kit libengine-pkcs11-openssl
RUN mkdir -p /app/db /app/certs /app/requests /app/keys /app/private
COPY dev/offline-ca/entrypoint /app/entrypoint
VOLUME [ "/app/db", "/app/certs", "/app/requests", "/app/keys", "/app/private" ]
ENTRYPOINT [ "/app/entrypoint" ]
RUN mkdir -p /etc/pkcs11/modules && echo "module: /usr/lib/$(uname -m)-linux-gnu/pkcs11/p11-kit-client.so" > /etc/pkcs11/modules/p11-kit-client.module

## Online Certificate Authority (CA) container

FROM smallstep/step-ca AS online-ca

# This script is used by inter-ca which only exists in the development
# environment

COPY dev/online-ca/adopt /usr/local/bin/

## Keys/Secrets Manager container

FROM vault AS kms

FROM kms AS kms-init

COPY dev/kms-init/bootstrap /

ENTRYPOINT [ "/bootstrap" ]

## LDAP Directory Service (DS) container

FROM core AS ds

COPY --from=step /usr/local/bin/step /usr/local/bin/

RUN apt-get install slapd ldap-utils heimdal-clients

EXPOSE 389
EXPOSE 636

VOLUME [ "/app/db", "/app/config", "/var/run/slapd" ]

RUN mkdir -p /app /app/share/templates /app/share/schema /app/db

COPY ds/entrypoint /app/entrypoint
ADD ds/templates/ /app/share/templates/
ADD ds/schema/ /app/share/schema/

ENTRYPOINT [ "/app/entrypoint" ]
CMD [ "run" ]

## Kerberos base container

FROM core AS kerberos

RUN apt-get install -qq heimdal-servers heimdal-clients heimdal-kdc openssl pwgen ldap-utils

COPY --from=step /usr/local/bin/step /usr/local/bin/

RUN mkdir -p /app /app/config /app/lib /app/db /app/etc
VOLUME [ "/app/db" ]

COPY kdc/services /etc/services
COPY kdc/common.sh /app/lib
RUN mv /var/lib/heimdal-kdc /var/lib/heimdal-kdc.dist && ln -sf /app/db/kdc /var/lib/heimdal-kdc

## Development container

FROM kerberos AS dev
COPY --from=vault /bin/vault /usr/local/bin
RUN apt-get install -qq procps nano nslcd libnss-ldapd finger less libpam-krb5 gnutls-bin p11-kit strace libengine-pkcs11-openssl
RUN mkdir -p /etc/ldap
COPY dev/ldap.conf /etc/ldap/
COPY dev/krb5.conf /etc/
COPY dev/nslcd.conf /etc/
COPY dev/nsswitch.conf /etc/
RUN mkdir /me
RUN mkdir -p /etc/pkcs11/modules && echo "module: /usr/lib/$(uname -m)-linux-gnu/pkcs11/p11-kit-client.so" > /etc/pkcs11/modules/p11-kit-client.module

VOLUME [ "/me" ]
ENTRYPOINT [ "/bin/sh", "-c" ]
CMD [ "/usr/sbin/nslcd --debug" ]

## Kerberos Key Distribution Center (KDC) container

FROM kerberos AS kdc
# http
EXPOSE 80/tcp
# kerberos-kdc
EXPOSE 88/tcp
EXPOSE 88/udp
# kpasswd
EXPOSE 464/udp
# hprop
#EXPOSE 754/tcp

COPY kdc/kdc.conf.in /app/etc/kdc.conf.in
COPY kdc/krb5.kdc.conf.in /app/etc/krb5.conf.in
COPY kdc/entrypoint.kdc /app/entrypoint
ENTRYPOINT [ "/app/entrypoint" ]
CMD [ "run" ]

## Kerberos Administration Service (kadmin) container

FROM kerberos AS kadmin
# kerberos-adm
EXPOSE 749/tcp
EXPOSE 749/udp
COPY kdc/kadmin.conf.in /app/etc/kadmin.conf.in
COPY kdc/krb5.kadmin.conf.in /app/etc/krb5.conf.in
COPY kdc/entrypoint.kadmin /app/entrypoint
ENTRYPOINT [ "/app/entrypoint" ]
CMD [ "run" ]
