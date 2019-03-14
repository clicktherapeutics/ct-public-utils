# First argument sets the location of /etc directory.
path_to_etc=${1:?"Path to /etc must be the first parameter."}

shift  # Cut off $1 so that the rest of $@ is a list of names.
if [ -z "$*" ]; then
    echo "No service names passed!"
    exit 1
fi

TMP="tmp-gen-ecsda-$$"

mkdir ${TMP} && cd ${TMP}

echo "Setting up credential directory structure..."
mkdir -p $path_to_etc/creds/services/keys
mkdir -p $path_to_etc/creds/services/certs

for server_name in "$@"
do
    echo "Generating ECDSA private key for ${server_name}..."
    openssl ecparam -name secp256k1 -genkey -noout -out $server_name-signing-key.pem
    cp $server_name-signing-key.pem $path_to_etc/creds/services/keys

    echo "Generating ECDSA public key for ${server_name}..."
    openssl ec -in $server_name-signing-key.pem -pubout -out $server_name-signing-pubkey.pem
    cp $server_name-signing-pubkey.pem $path_to_etc/creds/services/certs
done



echo "Cleaning up ${TMP}..."
cd ..
rm -rf ${TMP}
