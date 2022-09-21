. /lib/init/vars.sh
. /lib/lsb/init-functions


IAM_SERVICE=${IAM_SERVICE:-IAM}
IAM_KDC_HOSTNAME="${IAM_KDC_HOSTNAME:-$(hostname)}"
DBROOT="/app/db"
LDAPI="/run/slapd/ldapi"
DBPATH="${DBROOT}/kdc"
self="$IAM_SERVICE[${IAM_KDC_HOSTNAME}]"

KDC_DAEMON=/usr/lib/heimdal-servers/kdc
KDC_ARGS="--config-file=${DBPATH}/kdc.conf --addresses=0.0.0.0"

KADMIND_DAEMON=/usr/lib/heimdal-servers/kadmind
KADMIND_ARGS="--config-file=${DBPATH}/kadmin.conf -r ${DS_REALM_KRB} --keytab=${DBPATH}/kadmin.kt --debug"

#KPASSWDD_ARGS="--config-file=${DBPATH}/kpasswd.conf"
#PRIMARY_ARGS="--config-file=${DBPATH}/primary.conf -r ${DS_REALM_KRB} --hostname=${IAM_KDC_HOSTNAME}"
#REPLICA_ARGS="--config-file=${DBPATH}/replica.conf -r ${DS_REALM_KRB} --hostname=${IAM_KDC_HOSTNAME}"

ds_wait()
{
	while true ; do
		if [ -S ${LDAPI} ] ; then
			ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config "*" >/dev/null 2>&1
			result=$?
			if [ $result -eq 0 ] ; then
				printf "%s: LDAP connection established successfully\n" "${self}" >&2
				break
			fi
		fi
		if [ -z "$_availmsg" ] ; then
			printf "%s: waiting for directory service to become available...\n" "${self}" >&2
			_availmsg=1
		fi
		sleep 2
	done
}

kdc_wait()
{
	if ! [ -f ${DBPATH}/realm ]; then
		printf "%s: waiting for realm to be initialised by the KDC...\n" "${self}" >&2
		while ! [ -f ${DBPATH}/realm ] ; do
			sleep 1
		done
		printf "%s: realm initialised\n" "${self}" >&2
	fi
}

krb5conf_update()
{
	printf "%s: updating /etc/krb5.conf for %s\n" "${self}" "${DS_REALM_KRB}" >&2
	rm -f /etc/krb5.conf
	sed \
		-e "s!@DS_REALM_KRB@!${DS_REALM_KRB}!g" \
		< /app/etc/krb5.conf.in > /etc/krb5.conf
}

kadmin_prepare()
{
	krb5conf_update
	ds_wait
	kdc_wait
	if test -r /app/etc/kadmin.conf.in && ! test -r ${DBPATH}/kadmin.conf ; then
		sed \
			-e "s!@DS_REALM_KRB@!${DS_REALM_KRB}!g" \
			-e "s!@DS_REALM_DN@!${DS_REALM_DN}!g" \
			< /app/etc/kadmin.conf.in > ${DBPATH}/kadmin.conf
	fi
	rm -f /etc/heimdal-kdc/kadmin.conf
	if test -r ${DBPATH}/kadmin.conf ; then
		ln -s ${DBPATH}/kadmin.conf /etc/heimdal-kdc/kadmin.conf
	fi

	if ! test -f ${DBPATH}/kadmind.acl ; then
		printf "%s: WARNING: Remote administration is not possible: kdc/kadmind.acl is missing\n" "${self}" >&2
	fi
}

kdc_bootstrap()
{
	printf "%s: initialising realm %s\n" "$self" "${DS_REALM_KRB}" >&2
	printf "%s: generating %s master key\n" "$self" "${DS_REALM_KRB}" >&2
	kstash --random-key  --key-file=${DBPATH}/m-key || return
	printf "%s: initialising realm database for %s\n" "$self" "${DS_REALM_KRB}" >&2
	kadmin -l init --realm-max-ticket-life=unlimited --realm-max-renewable-life=unlimited "${DS_REALM_KRB}" || return

	echo 'admin/admin all' > ${DBPATH}/kadmind.acl
	printf "%s: storing kadmin principal's key (kadmin/admin@%s)\n" "$self" "${DS_REALM_KRB}" >&2
	kadmin -l ext -k "${DBPATH}/kadmin.kt" "kadmin/admin@${DS_REALM_KRB}" || true

	printf "%s: adding admin/admin@%s\n" "$self" "${DS_REALM_KRB}"
	newpw=$(pwgen -C 4 4 | sed -e 's! !-!g' -e 's!-$!!')
	rm -f ${DBPATH}/admin-pw
	touch ${DBPATH}/admin-pw
	chmod 600 ${DBPATH}/admin-pw
	if [ -z "$IAM_KDC_ADMINPW" ] ; then
		echo "${newpw}" > ${DBPATH}/admin-pw
		printf "%s: NOTICE: initial account password written to %s\n" "${self}" "${DBPATH}/admin-pw" >&2
	else
		printf "%s: NOTICE: overriding admin/admin's password via IAM_KDC_ADMINPW\n" "${self}" >&2
		printf "%s: NOTICE: account password will NOT be written to %s\n" "${self}" "${DBPATH}/admin-pw" >&2
		newpw="${IAM_KDC_ADMINPW}"
	fi
	kadmin -l add -p "${newpw}" --use-defaults "admin/admin@${DS_REALM_KRB}" || return
	unset newpw

		# we should really just check the principal list via kadmin
#	if ! grep "^$IAM_KDC_HOSTNAME\$" "${DBPATH}/iprop-hosts" >/dev/null 2>&1 ; then
#		printf "%s: adding replication principal iprop/%s@%s\n" "$self" "$IAM_KDC_HOSTNAME" "${DS_REALM_KRB}" >&2
#		kadmin -l add --random-key --use-defaults "iprop/${IAM_KDC_HOSTNAME}@${DS_REALM_KRB}"
#		echo "$IAM_KDC_HOSTNAME" >> "${DBPATH}/iprop-hosts"
#		touch ${DBPATH}/slaves
#	fi

#	printf "%s: storing replication principal's key (iprop/%s@%s)\n" "$self" "$IAM_KDC_HOSTNAME" "${DS_REALM_KRB}" >&2
#	kadmin -l ext "iprop/${IAM_KDC_HOSTNAME}@${DS_REALM_KRB}" || true

	echo "${DS_REALM_KRB}" >${DBPATH}/realm

}

kdc_prepare()
{
	krb5conf_update
	ds_wait

	bootstrap=no
	if ! test -d ${DBPATH} ; then
		if [ -z "${DS_REALM_KRB}" ] ; then
			printf "%s: ERROR: no realm database and no realm name specified (DS_REALM_KRB), cannot start\n" "${self}" >&2
			return 100
		fi
		bootstrap=yes
	fi

	mkdir -p ${DBPATH}
	chmod 700 ${DBPATH}

	printf "%s: updating /etc/krb5.conf for %s\n" "${self}" "${DS_REALM_KRB}" >&2
	rm -f /etc/krb5.conf
	sed \
		-e "s!@DS_REALM_KRB@!${DS_REALM_KRB}!g" \
		< /app/etc/krb5.conf.in > /etc/krb5.conf

	if test -r /app/etc/kdc.conf.in && ! test -r ${DBPATH}/kdc.conf ; then
		sed \
			-e "s!@DS_REALM_KRB@!${DS_REALM_KRB}!g" \
			-e "s!@DS_REALM_DN@!${DS_REALM_DN}!g" \
			< /app/etc/kdc.conf.in > ${DBPATH}/kdc.conf
	fi
	rm -f /etc/heimdal-kdc/kdc.conf
	if test -r ${DBPATH}/kdc.conf ; then
		ln -s ${DBPATH}/kdc.conf /etc/heimdal-kdc/kdc.conf
	fi
	if [ "$bootstrap" = yes ] ; then
		kdc_bootstrap || return
	fi
}
