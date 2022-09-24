# This makefile manages a development instance of the IAM service, storing data in
# ./devdb, applying dev.yaml (and dev.env), and with a Compose project name of "iamdev"
#
# Using kinit you can authenticate to the KDC with:
#
# $ kinit --kdc-server=localhost:988 admin/admin@EXAMPLE.COM
#
# The password for the admin/admin principal can be found in devdb/kdc/admin-pw

COMPOSEFLAGS = --project-name=iamdev -f docker-compose.yaml -f dev/dev.yaml

build:
	docker compose ${COMPOSEFLAGS} build

up: build
	dev/bootstrap-docker.sh ${COMPOSEFLAGS}
	docker compose ${COMPOSEFLAGS} up

down:
	docker compose ${COMPOSEFLAGS} down --remove-orphans

clean: down
	rm -rf dev/data devdb ds/testdb dump.ldif

rebuild: clean
	docker compose ${COMPOSEFLAGS} build 
	dev/bootstrap-docker.sh ${COMPOSEFLAGS}
	docker compose ${COMPOSEFLAGS} up -V --wait

ds-logs:
	docker compose ${COMPOSEFLAGS} logs ds -f

ds-dump:
	docker compose ${COMPOSEFLAGS} exec -it ds /app/entrypoint dump > dump.ldif

logs:
	docker compose ${COMPOSEFLAGS} logs -f

kdc-logs:
	docker compose ${COMPOSEFLAGS} logs kdc -f

dev-logs:
	docker compose ${COMPOSEFLAGS} logs dev -f

kadmin-logs:
	docker compose ${COMPOSEFLAGS} logs kadmin -f

root-ca-logs:
	docker compose ${COMPOSEFLAGS} logs root-ca -f

ds-shell:
	docker compose ${COMPOSEFLAGS} exec -it ds bash

kdc-shell:
	docker compose ${COMPOSEFLAGS} exec -it kdc bash

kadmin-shell:
	docker compose ${COMPOSEFLAGS} exec -it kadmin bash

dev-shell:
	docker compose ${COMPOSEFLAGS} exec -it dev bash

root-ca-shell:
	docker compose ${COMPOSEFLAGS} exec -it root-ca bash

infra-ca-shell:
	docker compose ${COMPOSEFLAGS} exec -it infra-ca bash

root-ca-health:
	docker compose ${COMPOSEFLAGS} exec -e STEPDEBUG=1 -it root-ca step ca health

dev-login:
	docker compose ${COMPOSEFLAGS} exec -it dev /bin/login

