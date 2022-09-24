This directory contains files used when running a local test
instance of the IAM stack. `dev.yaml` (which references `dev.env`)
is specified in the `docker compose` commands by the `Makefile`
in the parent directory.

The files `krb5.conf`, `nslcd.conf`, and `nsswitch.conf` are
installed to `/etc` within the `dev` container. They assume
that the realm name (specified in `dev.env`) is `EXAMPLE.COM`.
