. /lib/init/vars.sh
. /lib/lsb/init-functions


IAM_SERVICE=${IAM_SERVICE:-IAM}
IAM_KDC_HOSTNAME="${IAM_KDC_HOSTNAME:-$(hostname)}"
IAM_KDC_USE_MKEY=${IAM_KDC_USE_MKEY:-yes}
IAM_USER_NAME=${IAM_USER_NAME:-admin}
IAM_USER_FULLNAME=${IAM_USER_FULLNAME:-"Realm Administrator"}

DBROOT="/app/db"
LDAPI="/run/slapd/ldapi"
DBPATH="${DBROOT}/kdc"
self="$IAM_SERVICE[${IAM_KDC_HOSTNAME}]"
IAM_SECRETSDIR="${IAM_SECRETSDIR:-${DBROOT}}"
IAM_KADMINDIR="${IAM_KADMINDIR:-${DBROOT}}"

if [ "${IAM_KDC_USE_MKEY}" = "yes" ] ; then
	IAM_KDC_MKEY_OPT="mkey_file = ${DBPATH}/heimdal.mkey"
else
	IAM_KDC_MKEY_OPT=""
fi

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
	if ! [ -f ${DBPATH}/kadmin.kt ]; then
		printf "%s: waiting for realm to be initialised by the KDC...\n" "${self}" >&2
		while ! [ -f ${DBPATH}/kadmin.kt ] ; do
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
		-e "s!@DS_REALM_DN@!${DS_REALM_DN}!g" \
		-e "s!@IAM_KDC_MKEY_OPT@!${IAM_KDC_MKEY_OPT}!g" \
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
			-e "s!@IAM_KDC_MKEY_OPT@!${IAM_KDC_MKEY_OPT}!g" \
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
	if [ "${IAM_KDC_USE_MKEY}" = "yes" ] ; then
		if ! [ -r ${DBPATH}/heimdal.mkey ] ; then
			printf "%s: generating %s master key\n" "$self" "${DS_REALM_KRB}" >&2
			kstash --random-key  --key-file=${DBPATH}/heimdal.mkey || return
		fi
	fi
	printf "%s: initialising realm database for %s\n" "$self" "${DS_REALM_KRB}" >&2
#	kadmin -l init --bare --realm-max-ticket-life=unlimited --realm-max-renewable-life=unlimited "${DS_REALM_KRB}" || return
	kadmin -l cpw -r "krbtgt/${DS_REALM_KRB}"
	echo "${IAM_USER_NAME}/admin all" > ${IAM_KADMINDIR}/kadmind.acl
	printf "%s: storing kadmin principal's key (kadmin/admin@%s)\n" "$self" "${DS_REALM_KRB}" >&2
	kadmin -l cpw -r "kadmin/admin@${DS_REALM_KRB}"

	printf "%s: adding %s@%s and %s/admin@%s\n" "$self" "${IAM_USER_NAME}" "${DS_REALM_KRB}" "${IAM_USER_NAME}" "${DS_REALM_KRB}" >&2
	rm -f ${IAM_SECRETSDIR}/admin-pw ${IAM_SECRETSDIR}/user-pw

	if [ -z "$IAM_KDC_USERPW" ] ; then
		newpw=$(pwgen -C 4 4 | sed -e 's! !-!g' -e 's!-$!!')
		touch ${IAM_SECRETSDIR}/user-pw
		chmod 600 ${IAM_SECRETSDIR}/user-pw
		echo "${newpw}" > ${IAM_SECRETSDIR}/user-pw
		printf "%s: NOTICE: %s's account password written to %s\n" "${self}" "${IAM_USER_NAME}" "${IAM_SECRETSDIR}/user-pw" >&2
	else
		printf "%s: NOTICE: overriding %s's password via IAM_KDC_USERPW\n" "${self}" "${IAM_USER_NAME}" >&2
		printf "%s: NOTICE: account password will NOT be written to %s\n" "${self}" "${IAM_SECRETSDIR}/user-pw" >&2
		newpw="${IAM_KDC_USERPW}"
	fi
	kadmin -l cpw -p "${newpw}" "${IAM_USER_NAME}@${DS_REALM_KRB}"
	unset newpw
	
	if [ -z "$IAM_KDC_ADMINPW" ] ; then
		newpw=$(pwgen -C 4 4 | sed -e 's! !-!g' -e 's!-$!!')
		touch ${IAM_SECRETSDIR}/admin-pw
		chmod 600 ${IAM_SECRETSDIR}/admin-pw
		echo "${newpw}" > ${IAM_SECRETSDIR}/admin-pw
		printf "%s: NOTICE: %s/admin's account password written to %s\n" "${self}" "${IAM_USER_NAME}" "${IAM_SECRETSDIR}/admin-pw" >&2
	else
		printf "%s: NOTICE: overriding %s/admin's password via IAM_KDC_ADMINPW\n" "${self}" "${IAM_USER_NAME}" >&2
		printf "%s: NOTICE: account password will NOT be written to %s\n" "${self}" "${IAM_SECRETSDIR}/admin-pw" >&2
		newpw="${IAM_KDC_ADMINPW}"
	fi
	kadmin -l cpw -p "${newpw}" "${IAM_USER_NAME}/admin@${DS_REALM_KRB}"
	unset newpw

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
			-e "s!@IAM_KDC_MKEY_OPT@!${IAM_KDC_MKEY_OPT}!g" \
			< /app/etc/kdc.conf.in > ${DBPATH}/kdc.conf
	fi
	rm -f /etc/heimdal-kdc/kdc.conf
	if test -r ${DBPATH}/kdc.conf ; then
		ln -s ${DBPATH}/kdc.conf /etc/heimdal-kdc/kdc.conf
	fi
	if [ "$bootstrap" = yes ] ; then
		kdc_bootstrap || return
	fi
	printf "%s: generating kadmin.kt keytab for kadmin/admin@%s\n" "${self}" "${DS_REALM_KRB}" >&2
	kadmin -l ext -k "${IAM_KADMINDIR}/kadmin.kt" "kadmin/admin@${DS_REALM_KRB}" || return
}
