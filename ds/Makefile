DOCKERRUNFLAGS=-it -e TERM='$(TERM)' -e DS_REALM_ORGNAME='Example Enterprises' -e DS_REALM_DNS="example.com"

container:
	( cd .. && docker build --pull=false --tag ds --file Dockerfile --target ds . )

run: container
	mkdir -p testdb
	docker run -v `pwd`/testdb:/app/db $(DOCKERRUNFLAGS) ds

shell: container
	mkdir -p testdb
	docker run -v `pwd`/testdb:/app/db $(DOCKERRUNFLAGS) ds shell

dump: container
	mkdir -p testdb
	docker run -v `pwd`/testdb:/app/db $(DOCKERRUNFLAGS) ds dump
