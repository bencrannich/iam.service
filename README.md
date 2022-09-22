# Identity and Access Management (IAM) service stack

This stack contains:

* `ds`: an LDAP directory service (OpenLDAP)
* `kdc`: an authentication service (Heimdal Kerberos V KDC)
* `kadmin`: a Kerberos administration server (Heimdal Kerberos V kadmind)
* TODO: certificate authorities (Step)
* TODO: RADIUS accounting service

It is **NOT** remotely production-ready

There's no kpasswdd because user accounts (and indeed ideally service accounts)
should use PKINIT

## Testing locally

See the top-level `Makefile` for a list of useful targets -- they should be
fairly self-explanatory.


```
$ make rebuild
... this will (re)build the container images and bring up a test instance,
... storing data in ./dev/data
... the initial password for "me" is "password" and the password for
... "me/admin" is "admin" -- see dev/dev.env

$ make dev-shell
docker compose --project-name=iamdev -f docker-compose.yaml -f dev/dev.yaml exec -it dev bash
root@0123456789ab:~# kinit me
me@EXAMPLE.COM's Password: 
root@0123456789ab:~# klist
Credentials cache: FILE:/tmp/krb5cc_0
        Principal: me@EXAMPLE.COM

  Issued                Expires               Principal
Sep 22 21:27:32 2022  Mar 24 12:27:31 2023  krbtgt/EXAMPLE.COM@EXAMPLE.COM
root@0123456789ab:~# kadmin
kadmin> list *
me/admin@EXAMPLE.COM's Password: 
me
me/admin
krbtgt/EXAMPLE.COM
kadmin/admin
kadmin> get me
            Principal: me@EXAMPLE.COM
    Principal expires: never
     Password expires: never
 Last password change: 2022-09-22 21:25:13 UTC
      Max ticket life: unlimited
   Max renewable life: unlimited
                 Kvno: 1
                Mkvno: unknown
Last successful login: never
    Last failed login: never
   Failed login count: 0
        Last modified: 2022-09-22 21:25:13 UTC
             Modifier: unknown
           Attributes: 
             Keytypes: aes256-cts-hmac-sha1-96(pw-salt)[1], des3-cbc-sha1(pw-salt)[1], arcfour-hmac-md5(pw-salt)[1]
          PK-INIT ACL: 
              Aliases: 

kadmin> exit
```

Note that as the dev container has access to the LDAP socket so can use `kadmin -l` as well as `ldapsearch` etc.

```
root@0123456789ab:~# kadmin -l
kadmin> list *
me
me/admin
krbtgt/EXAMPLE.COM
kadmin/admin
kadmin> exit
root@0123456789ab:~# exit
exit
```

You can dump the contents of the directory with `make ds-dump`, which will generate `dump.ldif`


## Todo

1. ds: Run container as unprivileged user
2. ds: Run container with read-only root
3. ~~When running with compose, mount volume for socket~~
4. ds: schema updates + local schema overrides???
5. ~~kdc: wait for ds availability~~
6. kdc: fail better on initialisation
7. ds: ~~indices~~, database config (cross-check against DB_CONFIG)
8. admin tools
9. healthchecks
10. unify scripts
11. better logging (add some logging functions...)
12. integrity/consistency checks
13. map `gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth` to something nicer
14. does Heimdal HDB support LDAP connections over TCP/mTLS?
15. online CA configurations (intermediate, infra services, users… + throwaway root in dev)
16. ~~kadmin: why is `hdb-ldap-create-base` ignored~~ **SOLUTION**: create users via LDAP first, and perform key management and attribute changes via `kadmin`
17. ~~ALL: database directories only need to be shared by certain containers~~
18. ALL: tidy up environment variables
19. ~~kdc: initialise with --bare (just add krbtgt); add other entries via LDAP and then `kadmin -l modify`, etc.~~
20. ~~kdc: expand search scope~~
21. dev: working pam-ldap and nss-ldap (authenticating the "admin" user)
22. ~~~kdc: separate passwords for admin and admin/admin (duh)~~~
23. ~~~swap admin and admin/admin for templated $name and $name/admin~~~

