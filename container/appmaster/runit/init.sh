#!/bin/bash
set -e
set -x

export FLINK_JOBMANAGER_WEB_PORT="$PORT0"
export FLINK_JOBMANAGER_RPC_PORT="$PORT1" 
export FLINK_BLOB_SERVER_PORT="$PORT2" 
export FLINK_MESOS_ARTIFACT_SERVER_PORT="$PORT3"
export LIBPROCESS_PORT="$PORT4"

# determine scheme and derive WEB
SCHEME=http
OTHER_SCHEME=https
if [[ "${FLINK_SSL_ENABLED}" == true ]]; then
	SCHEME=https
	OTHER_SCHEME=http
fi

export FLINK_UI_WEB_PROXY_BASE="/service/${DCOS_SERVICE_NAME}"

# create directory to hold the security key and cert
mkdir -p /etc/security/flink

# extract cert and key from keystore, write to /etc/security/flink/flink.{crt,key}
if [[ "${FLINK_SSL_ENABLED}" == true ]]; then
	KEYDIR=`mktemp -d`
	trap "rm -rf $KEYDIR" EXIT

	echo "${FLINK_SSL_KEYSTOREBASE64}" | base64 -d > "$KEYDIR/flink.jks"
	ALIAS=$(keytool -list -keystore "$KEYDIR/flink.jks" -storepass "${FLINK_SSL_KEYSTOREPASSWORD}" | grep PrivateKeyEntry | cut -d, -f1 | head -n1)
	if [[ -z "${ALIAS}" ]]; then
		echo "Cannot find private key in keystore"
		exit 1
	fi

	# convert keystore to p12
	keytool -importkeystore -srckeystore "$KEYDIR/flink.jks" -srcalias "${ALIAS}" \
		-srcstorepass "${FLINK_SSL_KEYSTOREPASSWORD}" -destkeystore "$KEYDIR/flink.p12" \
		-deststorepass "${FLINK_SSL_KEYSTOREPASSWORD}" -deststoretype PKCS12

	# export cert and key from p12
	openssl pkcs12 -nokeys -passin pass:"${FLINK_SSL_KEYSTOREPASSWORD}" -in "$KEYDIR/flink.p12" -out /etc/security/flink/flink.crt
	openssl pkcs12 -nocerts -nodes -passin pass:"${FLINK_SSL_KEYSTOREPASSWORD}" -in "$KEYDIR/flink.p12" -out /etc/security/flink/flink.key
	chmod 600 /etc/security/flink/flink.{crt,key}

	rm -rf "$KEYDIR"
fi

# Move hadoop config files, as specified by hdfs.config-url, into place.
if [[ -f hdfs-site.xml && -f core-site.xml ]]; then
    mkdir -p "${HADOOP_CONF_DIR}"
    cp hdfs-site.xml "${HADOOP_CONF_DIR}"
    cp core-site.xml "${HADOOP_CONF_DIR}"
fi

# Move kerberos config file, as specified by security.kerberos.krb5conf, into place.
if [[ -n "${FLINK_SECURITY_KRB5_CONF_BASE64}" ]]; then
    echo "${FLINK_SECURITY_KRB5_CONF_BASE64}" | base64 -d > /etc/krb5.conf
fi

# Move keytab file, as specified by security.kerberos.keytab, under /etc/security/flink.
if [[ -n "${FLINK_SECURITY_KEYTAB_BASE64}" ]]; then
    echo "${FLINK_SECURITY_KEYTAB_BASE64}" | base64 -d > /etc/security/flink/flink-service.keytab
fi


# start service
exec runsvdir -P /etc/service

