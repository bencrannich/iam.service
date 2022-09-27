FROM debian:stable-slim AS base

WORKDIR /root

ENV LC_ALL C
ENV TZ=UTC
ENV DEBIAN_FRONTEND noninteractive

RUN echo 'APT::Install-Recommends "0"; \n\
APT::Install-Suggests "0"; \n\
APT::Get::Assume-Yes "true"; \n\
' > /etc/apt/apt.conf.d/noninteractive
ONBUILD RUN apt-get update

## Smallstep

FROM smallstep/step-cli as step

## SoftHSM server (used only in development)

FROM base AS hsm

RUN apt-get install -qq gnutls-bin p11-kit softhsm 

RUN mkdir /app
COPY dev/hsm/server /app/server
COPY dev/hsm/healthcheck /app/healthcheck
RUN chmod +x /app/server /app/healthcheck
ENTRYPOINT [ "/app/server" ]
VOLUME [ "/run/p11-kit", "/var/lib/softhsm/tokens" ]
HEALTHCHECK --interval=5s --timeout=10s --start-period=2s --retries=3 CMD [ "/app/healthcheck" ]

## Keys/Secrets Manager container (used only in development)

FROM vault AS kms
RUN mkdir -p /app
COPY dev/kms/healthcheck /app/healthcheck
RUN chmod +x /app/healthcheck
HEALTHCHECK --interval=5s --timeout=2s --start-period=5s --retries=5 CMD [ "/app/healthcheck" ]

FROM kms AS kms-init

RUN mkdir -p /app
COPY dev/kms-init/bootstrap /app/bootstrap
RUN chmod +x /app/bootstrap
HEALTHCHECK NONE
ENTRYPOINT [ "/app/bootstrap" ]

## Offline Certificate Authority (CA) container (used only in development)

FROM base AS offline-ca

RUN apt-get install -qq openssl gnutls-bin p11-kit libengine-pkcs11-openssl
RUN mkdir -p /app/db /app/libexec /app/certs /app/requests /app/keys /app/private
RUN mkdir -p /etc/pkcs11/modules && echo "module: /usr/lib/$(uname -m)-linux-gnu/pkcs11/p11-kit-client.so" > /etc/pkcs11/modules/p11-kit-client.module
COPY dev/offline-ca/entrypoint /app/entrypoint
COPY libexec/provision /app/libexec/provision
COPY --from=kms /bin/vault /usr/local/bin/
RUN chmod +x /app/entrypoint /app/libexec/provision 
VOLUME [ "/app/db", "/app/certs", "/app/requests", "/app/keys", "/app/private" ]
ENTRYPOINT [ "/app/entrypoint" ]
HEALTHCHECK NONE

## Online Certificate Authority (CA) container

FROM smallstep/step-ca AS online-ca
USER root
RUN mkdir -p /app /app/libexec
#COPY dev/online-ca/adopt /usr/local/bin/
COPY libexec/provision /app/libexec/provision
COPY online-ca/ca-wrapper /app/libexec/ca-wrapper
COPY online-ca/entrypoint /app/entrypoint
COPY --from=kms /bin/vault /usr/local/bin/
RUN chmod +x /app/entrypoint /app/libexec/provision /app/libexec/ca-wrapper
USER step
ENTRYPOINT [ "/app/entrypoint" ]
CMD /usr/local/bin/step-ca --password-file $PWDPATH $CONFIGPATH

## "Core" container, used as a basis for the main service containers

FROM base AS core
RUN apt-get install -qq certbot heimdal-clients ldap-utils openssl gnutls-bin pwgen p11-kit libengine-pkcs11-openssl
RUN mkdir -p /app /app/libexec
COPY --from=step /usr/local/bin/step /usr/local/bin/
COPY --from=kms /bin/vault /usr/local/bin/
COPY libexec/provision /app/libexec
RUN chmod +x /app/libexec/provision
ENTRYPOINT [ "/app/libexec/provision" ]
CMD [ "/bin/bash" ]

## LDAP Directory Service (DS) container

FROM core AS ds

RUN apt-get install slapd 

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

RUN apt-get install -qq heimdal-servers heimdal-kdc

RUN mkdir -p /app /app/config /app/lib /app/db /app/etc
VOLUME [ "/app/db" ]

COPY kdc/services /etc/services
COPY kdc/common.sh /app/lib
RUN mv /var/lib/heimdal-kdc /var/lib/heimdal-kdc.dist && ln -sf /app/db/kdc /var/lib/heimdal-kdc

## Development client container

FROM core AS client
RUN apt-get install -qq procps nano nslcd libnss-ldapd finger less libpam-krb5 strace
RUN mkdir -p /etc/ldap
COPY dev/client/ldap.conf /etc/ldap/
COPY dev/client/krb5.conf /etc/
COPY dev/client/nslcd.conf /etc/
COPY dev/client/nsswitch.conf /etc/
RUN mkdir /me
# This matches the default initial UID and GID of the initial user in the
# directory, but will need to be changed if you change them in dev.env or
# local.env
RUN chown 5000:5000 /me
RUN mkdir -p /etc/pkcs11/modules && echo "module: /usr/lib/$(uname -m)-linux-gnu/pkcs11/p11-kit-client.so" > /etc/pkcs11/modules/p11-kit-client.module
COPY dev/client/entrypoint /app/entrypoint
COPY dev/client/healthcheck /app/healthcheck
RUN chmod +x /app/entrypoint /app/healthcheck
VOLUME [ "/me" ]
ENTRYPOINT [ "/app/entrypoint" ]
HEALTHCHECK --interval=1s --timeout=30s --start-period=5s --retries=3 CMD [ "/app/healthcheck" ]

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
