# First argument sets the location of /etc directory.
path_to_etc=${1:?"Path to /etc must be the first parameter."}

shift  # Cut off $1 so that the rest of $@ is a list of names.
if [ -z "$*" ]; then
    echo "No service names passed!"
    exit 1
fi

# Allow environment to override openssl config path.
openssl_conf_path=${CT_OPENSSL_CONF_PATH:-/etc/ssl/ct-openssl.conf}

echo "Setting up credential directory structure..."
mkdir -p $path_to_etc/creds/root/certs
mkdir -p $path_to_etc/creds/root/keys
mkdir -p $path_to_etc/creds/services/certs
mkdir -p $path_to_etc/creds/services/keys

mkdir -p tmp && cd tmp

echo "Generating root certs..."
openssl genrsa -passout pass:1111 -des3 -out ca.key.pem 4096

openssl req -passin pass:1111 -new -x509 -days 7300 -key ca.key.pem -out ca.cert.pem -subj  "/C=FR/ST=Paris/L=Paris/O=Test/OU=Test/CN=root"

echo "Generating intermediate certs..."
openssl genrsa -passout pass:1111 -des3 -out ca-intermediate.key.pem 4096

openssl req -passin pass:1111 -new -key ca-intermediate.key.pem -out ca-intermediate.csr -subj  "/C=FR/ST=Paris/L=Paris/O=Test/OU=Test/CN=intermediate"

openssl x509 -req -passin pass:1111 -days 365 -extensions v3_intermediate_ca -extfile $openssl_conf_path -in ca-intermediate.csr -CA ca.cert.pem -CAkey ca.key.pem -set_serial 01 -out ca-intermediate.cert.pem

openssl rsa -passin pass:1111 -in ca-intermediate.key.pem -out ca-intermediate.key.pem

cp ca-intermediate.key.pem $path_to_etc/creds/root/keys/ca-intermediate.key.pem
cp ca.key.pem $path_to_etc/creds/root/keys/ca.key.pem
cp ca.cert.pem  $path_to_etc/creds/root/certs/ca.cert.pem
cp ca-intermediate.cert.pem  $path_to_etc/creds/root/certs/ca-intermediate.cert.pem

echo "Generating service certs..."
for server_name in "$@"
do
    openssl genrsa -passout pass:1111 -des3 -out $server_name.key.pem 4096

    openssl req -passin pass:1111 -new -key $server_name.key.pem -out $server_name.csr -subj  "/C=FR/ST=Paris/L=Paris/O=Test/OU=Test/CN=${server_name}.local.clicktherapeutics.com"

    openssl x509 -req -passin pass:1111 -days 365 -in $server_name.csr -CA ca-intermediate.cert.pem -CAkey ca-intermediate.key.pem -set_serial 01 -out $server_name.cert.pem

    openssl rsa -passin pass:1111 -in $server_name.key.pem -out $server_name.key.pem

    echo "copying files to /etc/creds dir"
    cat $server_name.cert.pem ca-intermediate.cert.pem ca.cert.pem > $path_to_etc/creds/services/certs/$server_name-chain.cert.pem
    cp $server_name.key.pem $path_to_etc/creds/services/keys
done

echo "Cleaning up..."
cd ..
rm -rf tmp
