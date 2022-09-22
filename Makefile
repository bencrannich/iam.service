# This makefile manages a development instance of the IAM service, storing data in
# ./devdb, applying dev.yaml (and dev.env), and with a Compose project name of "iamdev"
#
# Using kinit you can authenticate to the KDC with:
#
# $ kinit --kdc-server=localhost:988 admin/admin@EXAMPLE.COM
#
# The password for the admin/admin principal can be found in devdb/kdc/admin-pw

COMPOSEFLAGS = --project-name=iamdev -f docker-compose.yaml -f dev.yaml

build:
	docker compose ${COMPOSEFLAGS} build

up: build
	mkdir -p devdb
	docker compose ${COMPOSEFLAGS} up

down:
	docker compose ${COMPOSEFLAGS} down --remove-orphans

clean: down
	rm -rf devdb

rebuild:
	rm -rf devdb && mkdir -p devdb
	docker compose ${COMPOSEFLAGS} up --force-recreate --build --remove-orphans -V --wait

ds-logs:
	docker compose ${COMPOSEFLAGS} logs ds -f

ds-dump:
	docker compose ${COMPOSEFLAGS} exec -it ds /app/entrypoint dump > dump.ldif

kdc-logs:
	docker compose ${COMPOSEFLAGS} logs kdc -f

kadmin-logs:
	docker compose ${COMPOSEFLAGS} logs kadmin -f

ds-shell:
	docker compose ${COMPOSEFLAGS} exec -it ds bash

kdc-shell:
	docker compose ${COMPOSEFLAGS} exec -it kdc bash

kadmin-shell:
	docker compose ${COMPOSEFLAGS} exec -it kadmin bash

dev-shell:
	docker compose ${COMPOSEFLAGS} exec -it dev bash
