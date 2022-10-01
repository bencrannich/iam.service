# Identity and Access Management (IAM) service stack

This stack contains:

* `ds`: an LDAP directory service (OpenLDAP)
* `kdc`: an authentication service (Heimdal Kerberos V KDC)
* `kadmin`: a Kerberos administration server (Heimdal Kerberos V kadmind)
* ~~certificate authorities (Step)~~ (these are no longer included in the core stack for flexibility)
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
server), and do so with relatively light configuration and following standard patterns where possible.

## Data model

A `Realm` represents the top-level container for everything within a single management realm. It's an auxiliary class, and so is typically added to an `Organization` or `OrganizationalUnit` instance (although a realm could in principle be anything). A `Realm` may have a `description`, `dNSDomainName`, and `krb5RealmName`; the latter two will always be present under normal circumstances.

A `Container` is a generic container of other objects. It must have a Common Name (`CN`), and may have a `description`.

An `Account` represents any entity that has its own security identity (in Kerberos terms, a security principal), and there are a number of subclasses for different kinds of account: `Role` (a defined role which confers access to resources), `ServiceAccount` (an account used by a network service in order to access other resources), `UserAccount` (an account issued to a person), `RoleInstance` (an instance of a role conferred upon a particular user account), `Group` (a group of accounts). Not all properties apply usefully to all kinds of account, but an account must have a `uid` and may have a`CN`, `description`, `uidNumber`, `gidNumber`, `homeDirectory`, `loginShell`, `gecos`, and `krb5PrincipalName`.

…

## Certificate authorities and purposes

![Diagram showing a typical arrangement of certificate authorities](https://raw.githubusercontent.com/bencrannich/iam.service/default/docs/pki.png | width=600)

Certificates within a realm are routinely issued to:

* People (ordinary user accounts)
* Service groups (e.g., Identity and access management) and Services (e.g., Directory Service) within an environment
* Individual service nodes (service accounts, e.g., NFS on server25)
* Roles
* Role instances (e.g., `joe/admin`)
* Network hosts (physical and virtual machines) and containers
* Point-to-Point VPN endpoints

In effect, certification happens wherever a relationship between two entities in the directory needs to be cryptographically-verifiable as part of a protocol exchange (often, mutual identification as part of establishing a TLS connection).

The `iamdev` stack seeks to simulate an ideal public-key infrastructure (PKI)
setup, which is described below, although the stack could be integrated with
any functioning PKI.

### Offline certificate authorities (A1, B1, X1)

There are two "offline" root and one intermediate CAs, A1, B1, and X1,
respectively. The private keys for each are stored on separate hardware
security tokens, each having different PINs, and can be stored in
separate locations.

Wherever possible, systems are configured to trust both root A1 and B1
together.

Because the root CA keys are stored on hardware tokens (and marked
non-extractable), having a pair of keys provides a safety net: if either
of the two keys is lost, the other can be used to bring a replacement
into service (i.e., A2 or B2).

A1's and B1's keys are both used to sign the same certificate request
generated when X1 is initialised. In other words, X1 is identified by
two identical CA certificates containing its public key, one issued
by A1, and one issued by B1: whichever the client trusts, subordinates
of X1 will be considered valid.

(A1 and B1 actually also cross-sign each other, but it's unclear if
this is useful).

X1 is used to issue a small number of other certificates. One of these
in development only is the certificate for `kms`, the Vault instance—this
is because we need to bootstrap the KMS (configured properly for TLS)
before any of the online (Step) CAs are available.

### Provisioning CA

The Provisioning CA exists to issue a form of bearer token which can be
exchanged for a different kind of credential or bootstrap an authentication
process. For example, hosts configured to access the directory server
need to present a client certificate to do so, and the process of
authenticating a user may involve accessing the directory (depending upon
the client configuration), and so the certificate issued to it by the
Provisioning CA is used for this purpose.

In development, the Provisioning CA is a Step-CA instance with an ACME
provisioner configured that will issue certificates bearing the SAN of
any host that can pass the ACME `http-01` challenge within the stack (i.e.,
any of the running containers).

In production, certificates might be issued manually by a Provisioning
CA (e.g., not using ACME or similar at all), or be issued only to devices
which have completed an enrolment process and possess some kind of
shared secret, but the specifics are beyond the scope of this README.

In development, mirroring a typical production setup, certificates issued by
the Provisioning CA are restricted in their `keyUsage` and `extendedKeyUsage`,
to ensure that they cannot be used as server certificates, and they
contain an extension with a dummy value to mark them as a provisioning
certificate.

The specifics of these certificates are a compromise between Step-CA's
capabilities (in the context of an ACME provisioning flow, at least), and the
requirements of the servers which will be configured to accept them. In an
ideal world, the rules defining what is and isn't an acceptable client
certificate in a particular context would be expressed in a flexible but
very standard formulation, such that teaching a server about an extension
that it should pass without problem when marked as "Critical" would be
a trivial task (and not involving code changes).

The Provisioning CA is not restricted to devices: in particular, it can
be used as part of the provisioning process for a new hardware security
token: shortly after initialisation, a provisioning certificate is issued
to (and stored on) the token. That token provisioning certificate can then
be used to enrol the token for a particular user account through a
self-service process.

### Infrastructure CA

The infrastructure CA issues certificates to services which form part of
the realm infrastructure, such as the directory server, and the Kerberos
KDC (whose certificate must include specific extensions to support PKINIT).

### User CA

The User CA issues certificates for user accounts in the directory. User
certificates tend to have long lifetimes and be ideally only kept on
hardware security tokens such as YubiKeys or smartcards.

User certificates encode the Kerberos principal of the user and should
be compatible with Smartcard Login on macOS / Windows or equivalent PAM
modules, including supporting local on-demand account creation and
automatic Kerberos ticket initialisation.

In other words, when a user provides their token and enters the correct
PIN, any properly configured client host (e.g., a workstation) will create
a local account (if required), mount any network home directory specified
in their directory entry, and obtain a Kerberos ticket.

Open source platforms (Linux, FreeBSD, etc.) offer the further possibility
of using information from the certificate as a fallback for when the
directory service is unavailable, such as logging into a laptop for the
first time in an area with limited connectivity (obviously if the
certificate has been revoked, then that will impair any actual to
resources once that laptop is back online).

## Replication

TBC.

## Performance, resources, and scaling

TBC.

## Integration

TBC.

## Local testing & development

In addition to the core stack definition in `docker-compose.yaml`, there are
a number of additional YAML files which are used if you invoke the
`dev-compose` wrapper script. In addition to the OpenLDAP directory server
and Kerberos KDC, these files also define:

* An enterprise-style PKI with two "offline" root and a cross-signed intermediate CA
* A set of emulated hardware security modules (HSMs) which can be attached to containers (such as the offline CAs)
* An instance of Hashicorp Vault to act as a secrets/key manager (KMS)
* Setup and configuration for the online CAs so that they are integrated with the PKI and Vault

All of this should bootstrap automatically. On an M1 MacBook Pro, a full stack
takes between 30-60 seconds to reach a healthy state across the board from a
standing start (i.e., freshly initialising a realm and all secrets from
scratch), assuming the container images are already built. This can be made
faster if you're willing to make healthchecks more aggressive.

There is no requirement that all, or even any, of this is replicated in a
production deployment of the stack: the main requirement is that there
is a functioning PKI. If that's handled entirely externally, then that
should work just fine, although over time more functionality will
rely on being able to issue and validate various different kinds of
certificates beyond those implemented so far.

To get started, see the top-level `Makefile` for a set of useful targets --
they should be fairly self-explanatory. The quickest way to bootstrap
a development environment is to run:—

```
make rebuild
```

This will (re)build the container images and bring up a test instance, with a
Compose project name of `iamdev` and storing data in `./dev/data` and
`./dev/secrets`. Note that `./dev/data` is removed by `make clean` but
`./dev/secrets` is not removed unless you run `make fullclean`.

`make rebuild` is exactly the same as running:

```
./dev-compose build
./dev-compose up -V --wait client
````

By default (see the `dev-compose` script itself for more information), this is
the same as running:

```
docker compose --project-name iamdev -f docker-compose.yaml -f dev/hsm.yaml -f dev/root-ca.yaml -f dev/inter-ca.yaml -f dev/kms.yaml -f dev/prov-ca.yaml -f dev/infra-ca.yaml -f dev/user-ca.yaml -f dev/client.yaml -f dev/overrides.yaml -f dev/local.yaml build

docker compose --project-name iamdev -f docker-compose.yaml -f dev/hsm.yaml -f dev/root-ca.yaml -f dev/inter-ca.yaml -f dev/kms.yaml -f dev/prov-ca.yaml -f dev/infra-ca.yaml -f dev/user-ca.yaml -f dev/client.yaml -f dev/overrides.yaml -f dev/local.yaml up -V --wait client
```

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
28. ALL: certificate renewals !!
29. ds, kdc: certificate revocations!
30. ds, kdc, kadmin, client: minimal deployment with mini-ca & how to use externally-provided certs

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

## OpenLDAP debugging levels

| Level    | Keyword        | Description                                    |
| -------- | -------------- | ---------------------------------------------- |
|     -1   | any            | enable all debugging                           |
|       0  |                | no debugging                                   |
|       1  | (0x1 trace)    | trace function calls                           |
|       2  | (0x2 packets)  | debug packet handling                          |
|       4  | (0x4 args)     | heavy trace debugging                          |
|       8  | (0x8 conns)    | connection management                          |
|      16  | (0x10 BER)     | print out packets sent and received            |
|      32  | (0x20 filter)  | search filter processing                       |
|      64  | (0x40 config)  | configuration processing                       |
|     128  | (0x80 ACL)     | access control list processing                 |
|     256  | (0x100 stats)  | stats log connections/operations/results       |
|     512  | (0x200 stats2) | stats log entries sent                         |
|    1024  | (0x400 shell)  | print communication with shell backends        |
|    2048  | (0x800 parse)  | print entry parsing debugging                  |
|   16384  | (0x4000 sync)  | syncrepl consumer processing                   |
|   32768  | (0x8000 none)  | only highest-priority messages (always logged) |
