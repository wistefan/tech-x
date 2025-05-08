#!/bin/bash

cd "$(dirname "$0")"

set -x
set -e


# Default values (can be overridden)
outputFolder="./out"
configFolder="./config"
caOutputFolder="./ca"
caConfigFolder="./ca"

# Defaults for client parameters
CN="fdsc-operator.org"
DNS_NAMES=()
C="BE"
ST="BRUSSELS"
L="Brussels"
O="Data Space Operator"
OU="It"
INTERMEDIATE_NAME="FICODES-INTERMEDIATE"

# --- Parse named parameters ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cn)
      CN="$2"
      shift 2
      ;;
    --dns)
      DNS_NAMES+=("$2")
      shift 2
      ;;
    --country)
      C="$2"
      shift 2
      ;;
    --state)
      ST="$2"
      shift 2
      ;;
    --locality)
      L="$2"
      shift 2
      ;;
    --org)
      O="$2"
      shift 2
      ;;
    --ou)
      OU="$2"
      shift 2
      ;;
    --intermediateName)
      INTERMEDIATE_NAME="$2"
      shift 2
      ;;
    --outputFolder)
      outputFolder="$2"
      shift 2
      ;;
    --caConfigFolder)
      caConfigFolder="$2"
      shift 2
      ;;
    --caOutputFolder)
      caOutputFolder="$2"
      shift 2
      ;;
    --configFolder)
      configFolder="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

export REQ_DN=$(cat <<EOF
C = $C
ST = $ST
L = $L
O = $O
OU = $OU
CN = $CN
EOF
)

# --- Generate subjectAltName block ---
export ALT_NAMES=""
i=1
for dns in "${DNS_NAMES[@]}"; do
  ALT_NAMES+="DNS.$i = $dns"$'\n'
  ((i++))
done

echo $ALT_NAMES
echo $REQ_DN

mkdir -p ${outputFolder}

# --- Generate final config ---

envsubst < ${configFolder}/openssl-client-template.cnf > ${outputFolder}/openssl-client-final.cnf

# required by the ca-openssl config
export OUTPUT_FOLDER=$caOutputFolder

if [ ! -f "${outputFolder}/intermediate/private/intermediate.cakey.pem" ] || [ ! -f "${outputFolder}/intermediate/certs/intermediate.cacert.pem" ]; then

  # Intermediate
  mkdir -p ${outputFolder}/intermediate/private
  mkdir -p ${outputFolder}/intermediate/csr
  mkdir -p ${outputFolder}/intermediate/certs

  openssl genrsa -out ${outputFolder}/intermediate/private/intermediate.cakey.pem 4096
  openssl req -new -sha256 -set_serial 02 -config ${configFolder}/openssl-intermediate.cnf \
    -subj "/C=DE/ST=Saxony/L=Dresden/O=FICODES CA/CN=${INTERMEDIATE_NAME}/emailAddress=ca@ficodes.com/serialNumber=02" \
    -key ${outputFolder}/intermediate/private/intermediate.cakey.pem \
    -out ${outputFolder}/intermediate/csr/intermediate.csr.pem
  openssl ca -config ${caConfigFolder}/openssl.cnf -extensions v3_intermediate_ca -days 2650 -notext \
    -batch -in ${outputFolder}/intermediate/csr/intermediate.csr.pem \
    -out ${outputFolder}/intermediate/certs/intermediate.cacert.pem
  openssl x509 -in ${outputFolder}/intermediate/certs/intermediate.cacert.pem -out ${outputFolder}/intermediate/certs/intermediate.cacert.pem -outform PEM
  openssl x509 -noout -text -in ${outputFolder}/intermediate/certs/intermediate.cacert.pem

  cat ${outputFolder}/intermediate/certs/intermediate.cacert.pem ${caOutputFolder}/ca/certs/cacert.pem > ${outputFolder}/intermediate/certs/ca-chain-bundle.cert.pem

else
  echo "Intermediate CA already exists, skipping generation."
fi


# client
mkdir -p ${outputFolder}/client/private
mkdir -p ${outputFolder}/client/csr
mkdir -p ${outputFolder}/client/certs

openssl ecparam -name prime256v1 -genkey -noout -out ${outputFolder}/client/private/client.key.pem
#openssl genrsa -out ${outputFolder}/client/private/client.key.pem 4096
openssl req -new -set_serial 03 -key ${outputFolder}/client/private/client.key.pem -out ${outputFolder}/client/csr/client.csr \
  -config ${outputFolder}/openssl-client-final.cnf
openssl x509 -req -in ${outputFolder}/client/csr/client.csr -CA ${outputFolder}/intermediate/certs/ca-chain-bundle.cert.pem \
  -CAkey ${outputFolder}/intermediate/private/intermediate.cakey.pem -out ${outputFolder}/client/certs/client.cert.pem \
  -CAcreateserial -days 1825 -sha256 -extfile ${outputFolder}/openssl-client-final.cnf \
  -copy_extensions=copyall \
  -extensions v3_req

openssl x509 -in ${outputFolder}/client/certs/client.cert.pem -out ${outputFolder}/client/certs/client.cert.pem -outform PEM

cat ${outputFolder}/client/certs/client.cert.pem ${outputFolder}/intermediate/certs/ca-chain-bundle.cert.pem > ${outputFolder}/client/certs/client-chain-bundle.cert.pem

