# This makefile manages a development instance of the IAM service, storing data in
# ./devdb, applying dev.yaml (and dev.env), and with a Compose project name of "iamdev"
#
# Using kinit you can authenticate to the KDC with:
#
# $ kinit --kdc-server=localhost:988 admin/admin@EXAMPLE.COM
#
# The password for the admin/admin principal can be found in devdb/kdc/admin-pw

build:
	./dev-compose build

up: build
	./dev-compose up

start: build
	./dev-compose up -V --wait

down:
	./dev-compose down --remove-orphans

clean: down
	rm -rf dev/data devdb ds/testdb dump.ldif

rebuild: clean
	./dev-compose build 
	./dev-compose up -V --wait

lite: build
	IAM_DEV_LIGHT=1 ./dev-compose up -V --wait --remove-orphans

relite: clean build
	IAM_DEV_LIGHT=1 ./dev-compose up -V --wait --remove-orphans

logs:
	./dev-compose logs -f

kms-logs:
	./dev-compose logs kms -f

ds-logs:
	./dev-compose logs ds -f

ds-dump:
	./dev-compose exec -it ds /app/entrypoint dump > dump.ldif

kdc-logs:
	./dev-compose logs kdc -f

dev-logs:
	./dev-compose logs dev -f

kadmin-logs:
	./dev-compose logs kadmin -f

root-ca-logs:
	./dev-compose logs root-ca -f

kms-shell:
	./dev-compose exec -it kms sh

ds-shell:
	./dev-compose exec -it ds bash

kdc-shell:
	./dev-compose exec -it kdc bash

kadmin-shell:
	./dev-compose exec -it kadmin bash

dev-shell:
	./dev-compose exec -it dev bash

root-ca-shell:
	./dev-compose exec -it root-ca bash

infra-ca-shell:
	./dev-compose exec -it infra-ca bash

root-ca-health:
	./dev-compose exec -e STEPDEBUG=1 -it root-ca step ca health

dev-login:
	./dev-compose exec -it dev /bin/login

