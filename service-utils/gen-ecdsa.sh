path_to_etc=/etc

mkdir tmp && cd tmp

echo "Setting up credential directory structure..."
mkdir -p $path_to_etc/creds/services/keys
mkdir -p $path_to_etc/creds/services/certs

for server_name in "${@:1}"
do
    echo "Generating ECDSA private key..."
    openssl ecparam -name secp256k1 -genkey -noout -out $server_name-signing-key.pem
    cp $server_name-signing-key.pem $path_to_etc/creds/services/keys

    echo "Generating ECDSA public key..."
    openssl ec -in $server_name-signing-key.pem -pubout -out $server_name-signing-pubkey.pem
    cp $server_name-signing-pubkey.pem $path_to_etc/creds/services/certs
done



echo "Cleaning up..."
cd ..
rm -rf tmp
