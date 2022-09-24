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

## Design principles

### The Directory is the source of truth

The focal point of this stack is the directory service, `ds`. As is typical, the
purpose of the directory service is to be the so-called "single source of
truth" across a realm, containing information not only about user and
service accounts, roles, and groups, but also physical and virtual sites,
devices, certificates and certificate authorities, mail distribution lists,
and so on.

Necessarily, a somewhat opinionated approach has been taken with regards to
how information in the directory is structured. Hopefully, over time, more
flexibility can be afforded as administration tools are developed.

OpenLDAP's `slapd` provides the directory service engine. It is open source,
stable, robust, well-understood (there are books about it), and speaks the
industry-standard LDAP protocol with a range of access-control and
authentication options including use of mutual TLS.

### Kerberos provides authentication

The directory service does not perform authentication itself. Instead, this
is delegated to either a Kerberos realm, or a (X.509/PKIX) certificate
authority.

The Kerberos authentication services (`kdc` and `kadmin`) use the Heimdal
Kerberos implementation, configured to use the directory service as its
database. Thus, Kerberos services can operate anywhere a replica of the
directory service is available.

Kerberos is implemented in all major operating systems (both mobile and
desktop) and is an integral component of both Microsoft Active Directory
and Apple Open Directory. NFSv4 uses Kerberos to provide a strong
security layer to network-available shared storage.

### No secret material persisted on disk

User accounts and role instances (and where possible service accounts)
will not be protected by passwords, and the goal is to eliminate all
secret material from being persisted on disk anywhere in the stack
(where secret material must be persisted, that ideally will be via a
hardware token). Accounts will be authenticated by proving access to a
private key, which translates to inserting a token (e.g., YubiKey,
Smartcard) and entering the unlock PIN.

### Certificates as standard

Digital certificates are a copy of a portion of information from the
directory, digitally signed for a fixed period (or until revoked) to
allow the receiver to verify their validity. Typically, the information
conveyed in a certificate is, in effect, "the entity which controls the
private key for this certificate corresponds to this named entry in the
directory"—in other words, for identification.

However, this extends to any kind of entity in the directory, not only
to people or service accounts.

Implementing public/private-key-based authentication requires operating a
properly-configured certificate authority and configuring the Kerberos KDC
to trust that authority.

The certificate authorities in this stack are instances of StepCA, which
is a modern, highly-configurable certificate authority implementation
designed for use in both cloud and on-premises configurations.

### Role-based access control

Access control is role-based, and we adhere to the Kerberos pattern of
creating per-user-role _instances_ with their own authentication
requirements, such as `joe/admin`. These are created as subsidiary
objects of the relevant user account, and have their own Kerberos
principal name but do not have their own numeric user and group ID (i.e.,
they are not separate accounts as Posix applications understand them).

As with user accounts, role instances also are authenticated using
a security token and PIN: a certificate is issued to the user which is
stored on their token (or for some roles, on a different token), and may
even be protected by a different PIN to their usual identity.

### Lightweight and portable

This stack should be easily deployable to low-cost commodity hardware
and to lower-spec compute instances offered by major cloud providers.

### Standards-based and interoperable

This stack is intended to be used by clients running a range of
operating systems (particularly Linux, macOS, iOS, and Android),
and afford integration with other services (such as NFS and a DHCP
server), and do so with minimal 


## Data model

A `Realm` represents the top-level container for everything within a single management realm. It's an auxiliary class, and so is typically added to an `Organization` or `OrganizationalUnit` instance (although a realm could in principle be anything). A `Realm` may have a `description`, `dNSDomainName`, and `krb5RealmName`; the latter two will always be present under normal circumstances.

A `Container` is a generic container of other objects. It must have a Common Name (`CN`), and may have a `description`.

An `Account` represents any entity that has its own security identity (in Kerberos terms, a security principal), and there are a number of subclasses for different kinds of account: `Role` (a defined role which confers access to resources), `ServiceAccount` (an account used by a network service in order to access other resources), `UserAccount` (an account issued to a person), `RoleInstance` (an instance of a role conferred upon a particular user account), `Group` (a group of accounts). Not all properties apply usefully to all kinds of account, but an account must have a `uid` and may have a`CN`, `description`, `uidNumber`, `gidNumber`, `homeDirectory`, `loginShell`, `gecos`, and `krb5PrincipalName`.

## Certificate authorities and purposes

Certificates within a realm are routinely issued to:

* People (ordinary user accounts)
* Service groups (e.g., Identity and access management) and Services (e.g., Directory Service) within an environment
* Individual service nodes (service accounts, e.g., NFS on server25)
* Roles
* Role instances (e.g., `joe/admin`)
* Network hosts (physical and virtual machines) and containers
* Point-to-Point VPN endpoints

In effect, certification happens wherever a relationship between two entities in the directory needs to be cryptographically-verifiable as part of a protocol exchange (often, mutual identification as part of establishing a TLS connection).

## Replication

TBC.

## Performance, resources, and scaling

TBC.

## Integration

TBC.

## Local testing & development

See the top-level `Makefile` for a list of useful targets -- they should be
fairly self-explanatory. To get started quickly, run:

```
$ make rebuild
```

This will (re)build the container images and bring up a test instance, with a
Compose project name of `iamdev` and storing data in `./dev/data`.

The initial user account (and its associated role instances) are created based
upon values set in `dev/dev.env`. By default, this creates a user named `me`
with a password set to `password`, who can administer Kerberos via a
`me/admin` principal with a password set to `admin`. Longer-term both should use
X.509 certificates and PKINIT in place of passwords.

See `ds/templates/40-accounts.ldif.in` for this account's template.

The `dev` container which is brought up is configured to perform NSS LDAP lookups
and for PAM to authenticate with Kerberos. Use the `dev-logs` target to view the
debug output from the LDAP client daemon, `nslcd`, use `dev-shell` for a standard
root shell within the container, and `dev-login` to test PAM authentication.

```
$ make dev-login
docker compose --project-name=iamdev -f docker-compose.yaml -f dev/dev.yaml exec -it dev /bin/login
fe5a241b6e83 login: me
Password: 
Linux fe5a241b6e83 5.10.124-linuxkit #1 SMP PREEMPT Thu Jun 30 08:18:26 UTC 2022 aarch64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
me@fe5a241b6e83:~$ klist
Credentials cache: FILE:/tmp/krb5cc_5000_nVDTRb
        Principal: me@EXAMPLE.COM

  Issued                Expires               Principal
Sep 23 15:43:00 2022  Sep 24 15:43:00 2022  krbtgt/EXAMPLE.COM@EXAMPLE.COM
me@fe5a241b6e83:~$ id
uid=5000(me) gid=5000(Test User) groups=5000(Test User),20000(All users)
me@fe5a241b6e83:~$ finger me
Login: me                               Name: Test User
Directory: /me                          Shell: /bin/bash
On since Fri Sep 23 15:43 (UTC) on pts/0   2 seconds idle
     (messages off)
No mail.
No Plan.
me@fe5a241b6e83:~$ who
me       pts/0        Sep 23 15:43
me@fe5a241b6e83:~$ pwd
/me
me@fe5a241b6e83:~$ kadmin
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
 Last password change: 2022-09-23 15:42:54 UTC
      Max ticket life: unlimited
   Max renewable life: unlimited
                 Kvno: 1
                Mkvno: unknown
Last successful login: never
    Last failed login: never
   Failed login count: 0
        Last modified: 2022-09-23 15:42:54 UTC
             Modifier: unknown
           Attributes: 
             Keytypes: aes256-cts-hmac-sha1-96(pw-salt)[1], des3-cbc-sha1(pw-salt)[1], arcfour-hmac-md5(pw-salt)[1]
          PK-INIT ACL: 
              Aliases: 

kadmin> exit
me@fe5a241b6e83:~$ exit
logout
$ 
```

...
... the initial password for "me" is "password" and the password for
... "me/admin" is "admin" -- see dev/dev.env
...
... the dev container is configured to perform NSS LDAP lookups and to perform
... PAM authentication via Kerberos, and so any users (or groups, hosts, etc.)
... added to the directory should be visible to the system, and those with
... passwords set via `kadmin` should

$ make dev-shell
docker compose --project-name=iamdev -f docker-compose.yaml -f dev/dev.yaml exec -it dev bash
root@0123456789ab:~# finger me
Login: me                               Name: Test User
Directory: /me                          Shell: /bin/bash
Never logged in.
No mail.
No Plan.
root@0123456789ab:~# id me
uid=5000(me) gid=5000(Test User) groups=5000(Test User),20000(All users)
root@0123456789ab:~# su - me
me@0123456789ab:~$ kinit
me@EXAMPLE.COM's Password: 
me@0123456789ab:~$ klist
Credentials cache: FILE:/tmp/krb5cc_5000
        Principal: me@EXAMPLE.COM

  Issued                Expires               Principal
Sep 23 12:50:17 2022  Mar 25 03:50:15 2023  krbtgt/EXAMPLE.COM@EXAMPLE.COM
me@0123456789ab:~$ kadmin
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
 Last password change: 2022-09-23 12:49:45 UTC
      Max ticket life: unlimited
   Max renewable life: unlimited
                 Kvno: 1
                Mkvno: unknown
Last successful login: never
    Last failed login: never
   Failed login count: 0
        Last modified: 2022-09-23 12:49:45 UTC
             Modifier: unknown
           Attributes: 
             Keytypes: aes256-cts-hmac-sha1-96(pw-salt)[1], des3-cbc-sha1(pw-salt)[1], arcfour-hmac-md5(pw-salt)[1]
          PK-INIT ACL: 
              Aliases: 

kadmin> exit
me@0123456789ab:~$ id
uid=5000(me) gid=5000(Test User) groups=5000(Test User),20000(All users)
me@0123456789ab:~$ pwd
/me
me@0123456789ab:~$ exit
logout
root@0123456789ab:~# exit
exit

Note that as the dev container has access to the LDAP socket, it can use `kadmin -l` as well as `ldapsearch` etc.

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


## To-do

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
14. ~~does Heimdal HDB support LDAP connections over TCP/mTLS?~~ according to the code, yes, although it isn't obvious how to supply a client certificate
15. online CA configurations (infra services, users… + ~~throwaway root in dev~~)
16. ~~kadmin: why is `hdb-ldap-create-base` ignored~~ **SOLUTION**: create users via LDAP first, and perform key management and attribute changes via `kadmin`
17. ~~ALL: database directories only need to be shared by certain containers~~
18. ALL: tidy up environment variables
19. ~~kdc: initialise with --bare (just add krbtgt); add other entries via LDAP and then `kadmin -l modify`, etc.~~
20. ~~kdc: expand search scope~~
21. ~~dev: working pam-krb5 and nss-ldap (authenticating the "admin" user)~~
22. ~~kdc: separate passwords for admin and admin/admin (duh)~~
23. ~~swap admin and admin/admin for templated $name and $name/admin~~
24. ds: ACLs ACLs ACLs
25. ds: replica bootstrap
26. kdc: mkey in KMS (verify that mkey is even used)
27. kdc: listen on non-default port so that it can run unprivileged

## Heimdal hdb-ldap options

From [hdp-ldap.c](https://github.com/heimdal/heimdal/blob/8b0c7ec09a167e37fb6f7626cf0a633174e30184/lib/hdb/hdb-ldap.c#L1907):-

* `kdc`.`hdb-ldap-url` (string)
* `kdc`.`hdb-ldap-structural-object` (string)
* `kdc`.`hdb-samba-forwardable` (boolean)
* `kdc`.`hdb-ldap-secret-file` (string)
* `kdc`.`hdb-ldap-bind-dn` (string)
* `kdc`.`hdb-ldap-bind-password` (string)
* `kdc`.`hdb-ldap-start-tls` (boolean)
* `kdc`.`hdb-ldap-create-base` (string)
