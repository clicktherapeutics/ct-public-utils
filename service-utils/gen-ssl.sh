# Die on errors immediately.
set -e

# First argument sets the location of /etc directory.
path_to_etc=${1:?"An absolute path to /etc must be the first parameter."}

shift  # Cut off $1 so that the rest of $@ is a list of names.
if [ -z "$*" ]; then
    echo "No service names passed!"
    exit 1
fi

# Allow environment to override openssl config file.
openssl_conf_file=${CT_OPENSSL_CONF_FILE:-/etc/ssl/ct-openssl.conf}
if [ ! -f  "${openssl_conf_file}" ]; then
    echo "No openssl config file at '${openssl_conf_file}'."
    exit 1
fi

ROOT_CERTS=${path_to_etc}/creds/root/certs
ROOT_KEYS=${path_to_etc}/creds/root/keys
SVC_CERTS=${path_to_etc}/creds/services/certs
SVC_KEYS=${path_to_etc}/creds/services/keys

TMP="tmp-gen-ssl-$$"  # Temporary work dir name.

enter_tmp_dir() {
    mkdir ${TMP} && cd ${TMP}
}

leave_tmp_dir() {
    echo "Cleaning up ${TMP}..."
    cd ..
    rm -rf ${TMP}
}

echo "Making sure credential directory structure is present..."
mkdir -p ${ROOT_CERTS}
mkdir -p ${ROOT_KEYS}
mkdir -p ${SVC_CERTS}
mkdir -p ${SVC_KEYS}

##
# CA generation.

# Check if we even have any work to do. (We don't want `make` run in every container.)
# See `cp` statements below for the logic of the names.
ALL_FOUND="yes"
(
    [ -f ${ROOT_KEYS}/ca-intermediate.key.pem ] &&
    [ -f ${ROOT_KEYS}/ca.key.pem ] &&
    [ -f ${ROOT_CERTS}/ca.cert.pem ] &&
    [ -f ${ROOT_CERTS}/ca-intermediate.cert.pem ]
) || ALL_FOUND="no"

if [ ${ALL_FOUND} = "yes" ]; then
    echo "Root keys and certificates are already present."
else
    # NOTE: Since we're re-generating the CA, any certs and keys lying around are no more valid.
    # Remove them.
    echo "Generating root certs."
    
    echo "Removing any pre-existing keys and certs."
    rm -rf ${SVC_CERTS}/*
    rm -rf ${SVC_KEYS}/*

    enter_tmp_dir

    openssl genrsa -passout pass:1111 -des3 -out ca.key.pem 4096

    openssl req -passin pass:1111 -new -x509 -days 7300 -key ca.key.pem -out ca.cert.pem \
            -subj "/C=FR/ST=Paris/L=Paris/O=Test/OU=Test/CN=root"

    echo "Generating intermediate certs..."
    openssl genrsa -passout pass:1111 -des3 -out ca-intermediate.key.pem 4096

    openssl req -passin pass:1111 -new -key ca-intermediate.key.pem -out ca-intermediate.csr \
            -subj "/C=FR/ST=Paris/L=Paris/O=Test/OU=Test/CN=intermediate"

    openssl x509 -req -passin pass:1111 -days 365 -extensions v3_intermediate_ca -extfile ${openssl_conf_file} \
            -in ca-intermediate.csr -CA ca.cert.pem -CAkey ca.key.pem -set_serial 01 -out ca-intermediate.cert.pem

    openssl rsa -passin pass:1111 -in ca-intermediate.key.pem -out ca-intermediate.key.pem

    cp ca-intermediate.key.pem ${ROOT_KEYS}/ca-intermediate.key.pem
    cp ca.key.pem ${ROOT_KEYS}/ca.key.pem
    cp ca.cert.pem  ${ROOT_CERTS}/ca.cert.pem
    cp ca-intermediate.cert.pem  ${ROOT_CERTS}/ca-intermediate.cert.pem

    leave_tmp_dir
fi

##
# Server keys generation.

# NOTE: if CA generation above was run, all keys were removed.
# If it was not, we may need to generate just some extra service keys using the existing root cert.

already_present_names=""

for server_name in "$@"; do
    if [ -f ${SVC_KEYS}/${server_name}.key.pem ] && [ ${SVC_CERTS}/${server_name}-chain.cert.pem ]; then
        already_present_names="${already_present_names} ${server_name}"
    else
        enter_tmp_dir

        echo "Generating service certs for ${server_name}."
        openssl genrsa -passout pass:1111 -des3 -out ${server_name}.key.pem 4096

        openssl req -passin pass:1111 -new -key ${server_name}.key.pem -out ${server_name}.csr \
                -subj  "/C=FR/ST=Paris/L=Paris/O=Test/OU=Test/CN=${server_name}.local.clicktherapeutics.com"

        openssl x509 -req -passin pass:1111 -days 365 -in ${server_name}.csr \
                -CA ${ROOT_CERTS}/ca-intermediate.cert.pem -CAkey ${ROOT_KEYS}/ca-intermediate.key.pem \
                -set_serial 01 -out ${server_name}.cert.pem

        openssl rsa -passin pass:1111 -in ${server_name}.key.pem -out ${server_name}.key.pem

        echo "copying files to /etc/creds dir"
        cat ${server_name}.cert.pem ${ROOT_CERTS}/ca-intermediate.cert.pem ${ROOT_CERTS}/ca.cert.pem > ${SVC_CERTS}/${server_name}-chain.cert.pem
        cp ${server_name}.key.pem ${SVC_KEYS}

        leave_tmp_dir
    fi
done

if [ "${already_present_names}" ]; then
    echo "Certs and keys are already present for:${already_present_names}."
fi
