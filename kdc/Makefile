DOCKERRUNFLAGS=-it -e TERM='$(TERM)' -v `cd .. && pwd`/testdb:/app/db

container:
	docker build --pull=false --tag kdc --file Dockerfile --target kdc .

run: container
	mkdir -p ../testdb
	docker run $(DOCKERRUNFLAGS) kdc

shell: container
	mkdir -p testdb
	docker run $(DOCKERRUNFLAGS) kdc shell

