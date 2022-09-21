# Identity and Access Management (IAM) service stack

This stack contains:

* `ds`: an LDAP directory service (OpenLDAP)
* `kdc`: an authentication service (Heimdal Kerberos V KDC)
* `kadmin`: a Kerberos administration server (Heimdal Kerberos V kadmind)
* TODO: certificate authorities (Step)
* TODO: RADIUS accounting service

It is **NOT** remotely production-ready

## Testing locally

See the top-level `Makefile` for a list of useful targets -- they should be
fairly self-explanatory.


```
$ make rebuild
... this will (re)build the container images and bring up a test instance,
... storing data in ./devdb
... the initial password for admin/admin is "password" (see dev.env)
$ make dev-shell
docker compose --project-name=iamdev -f docker-compose.yaml -f dev.yaml exec -it dev bash
root@0123456789ab:~# kinit admin/admin
admin/admin@EXAMPLE.COM's Password:
root@0123456789ab:~# klist
Credentials cache: FILE:/tmp/krb5cc_0
        Principal: admin/admin@EXAMPLE.COM

  Issued                Expires               Principal
Sep 21 21:29:16 2022  Sep 22 21:29:16 2022  krbtgt/EXAMPLE.COM@EXAMPLE.COM
root@0123456789ab:~# kadmin
admin/admin@EXAMPLE.COM's Password: 
            Principal: admin/admin@EXAMPLE.COM
    Principal expires: never
     Password expires: never
 Last password change: 2022-09-21 21:28:32 UTC
      Max ticket life: 1 day
   Max renewable life: 1 week
                 Kvno: 1
                Mkvno: unknown
Last successful login: never
    Last failed login: never
   Failed login count: 0
        Last modified: 2022-09-21 21:28:32 UTC
             Modifier: unknown
           Attributes: 
             Keytypes: aes256-cts-hmac-sha1-96(pw-salt)[1], des3-cbc-sha1(pw-salt)[1], arcfour-hmac-md5(pw-salt)[1]
          PK-INIT ACL: 
              Aliases: 

kadmin> exit
root@0123456789ab:~# exit
exit
$ make ds-dump
 :
 :
dn: krb5PrincipalName=admin/admin@EXAMPLE.COM,o=Example Enterprises
objectClass: top
objectClass: account
objectClass: krb5Principal
objectClass: krb5KDCEntry
krb5PrincipalName: admin/admin@EXAMPLE.COM
uid: admin/admin
krb5KeyVersionNumber: 1
krb5ExtendedAttributes:: MBqgAwEBAKETpxEYDzIwMjIwOTIxMjEyODMyWg==
krb5MaxLife: 86400
krb5MaxRenew: 604800
krb5KDCFlags: 126
krb5Key:: ME+hKzApoAMCARKhIgQgwf04TI63pH5cw34JtA3ifGpmfLFgHVUEEAxNb2R7PgyiID
 AeoAMCAQOhFwQVRVhBTVBMRS5DT01hZG1pbmFkbWlu
krb5Key:: MEehIzAhoAMCARChGgQYN80xZ+XjMsFePux2UpsqAfFYTAcqHK0voiAwHqADAgEDoR
 cEFUVYQU1QTEUuQ09NYWRtaW5hZG1pbg==
krb5Key:: MD+hGzAZoAMCARehEgQQiEb36u6PsRetBr3YMLdYbKIgMB6gAwIBA6EXBBVFWEFNUE
 xFLkNPTWFkbWluYWRtaW4=
structuralObjectClass: account
entryUUID: 16667eb4-ce40-103c-8cc8-2b302354e5be
creatorsName: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
createTimestamp: 20220921212832Z
entryCSN: 20220921212832.668399Z#000000#000#000000
modifiersName: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
modifyTimestamp: 20220921212832Z

$ 
```

## Todo

1. ds: Run container as unprivileged user
2. ds: Run container with read-only root
3. ~~When running with compose, mount volume for socket~~
4. ds: schema updates???
5. ~~kdc: wait for ds availability~~
6. kdc: fail better on initialisation
7. ds: indices, DB_CONFIG
8. admin tools
9. healthchecks
10. unify scripts
11. better logging (add some logging functions...)
12. integrity/consistency checks
13. map `gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth` to something nicer
14. does Heimdal HDB support LDAP connections over TCP/mTLS?
15. online CA configurations (intermediate, infra services, users… + throwaway root in dev)
16. kadmin: why is `hdb-ldap-create-base` ignored

