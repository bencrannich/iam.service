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

RUN mkdir -p /app /app/config /app/lib /app/db /app/etc
VOLUME [ "/app/db" ]

COPY kdc/services /etc/services
COPY kdc/common.sh /app/lib
RUN mv /var/lib/heimdal-kdc /var/lib/heimdal-kdc.dist && ln -sf /app/db/kdc /var/lib/heimdal-kdc

## Development container

FROM kerberos AS dev
RUN apt-get install -qq procps nano
COPY kdc/krb5.dev.conf.in /app/etc/krb5.conf.in
COPY kdc/entrypoint.dev /app/entrypoint
ENTRYPOINT [ "/app/entrypoint" ]

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
