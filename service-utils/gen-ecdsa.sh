set -e  # Crash on any error.

# First argument sets the location of /etc directory.
path_to_etc=${1:?"An absolute path to /etc must be the first parameter."}

shift  # Cut off $1 so that the rest of $@ is the list of names.
if [ -z "$*" ]; then
    echo "No service names passed!"
    exit 1
fi

# We do not want to bring `make` to every image and then play with makefiles.
# Instead we check the presence of the expected files ourselves.

KEYS_DIR=${path_to_etc}/creds/services/keys
CERTS_DIR=${path_to_etc}/creds/services/certs

TMP="tmp-gen-ecsda-$$"

mkdir ${TMP} && cd ${TMP}

echo "Making sure credential directory structure is present..."
mkdir -p ${KEYS_DIR}
mkdir -p ${CERTS_DIR}

already_present_names=""

for server_name in "$@"
do
    # Check if we have any work to do.
    if [ -f ${KEYS_DIR}/${server_name}-signing-key.pem ] && [ -f ${CERTS_DIR}/${server_name}-signing-pubkey.pem ]; then
        already_present_names="${already_present_names} ${server_name}"
    else
        echo "Generating ECDSA private key for ${server_name}..."
        openssl ecparam -name secp256k1 -genkey -noout -out ${server_name}-signing-key.pem
        cp ${server_name}-signing-key.pem ${KEYS_DIR}

        echo "Generating ECDSA public key for ${server_name}..."
        openssl ec -in ${server_name}-signing-key.pem -pubout -out ${server_name}-signing-pubkey.pem
        cp ${server_name}-signing-pubkey.pem ${CERTS_DIR}
    fi
done

if [ "${already_present_names}" ]; then
    echo "Keys already present for:${already_present_names}."
fi



echo "Cleaning up ${TMP}..."
cd ..
rm -rf ${TMP}
