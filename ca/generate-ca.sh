#!/bin/bash

cd "$(dirname "$0")"

set -x
set -e


# Default values (can be overridden)
outputFolder="./out"
configFolder="./config"
caSecretName="root-ca"
caSecretNameSpace="trust-anchor"
k3sFolder="../k3s"


# --- Parse named parameters ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --outputFolder)
      outputFolder="$2"
      shift 2
      ;;
    --configFolder)
      configFolder=("$2")
      shift 2
      ;;
    --caSecreteName)
      configFolder=("$2")
      shift 2
      ;;
    --caSecretNameSpace)
      configFolder=("$2")
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p ${outputFolder}
echo -n "" > ${outputFolder}/index.txt
echo -n "01" > ${outputFolder}/serial
echo -n "1000" > ${outputFolder}/crlnumber


export OUTPUT_FOLDER=$outputFolder

# Only create ca if it does not exist. It allows to update the client certificates whitout having to update the ca everywhere
if [ ! -f ${outputFolder}/ca/certs/cacert.pem ]; then

  mkdir -p ${outputFolder}/ca/private
  mkdir -p ${outputFolder}/ca/csr
  mkdir -p ${outputFolder}/ca/certs

  # generate key
  openssl genrsa -out ${outputFolder}/ca/private/cakey.pem 4096
  # create CA Request
  openssl req -new -x509 -set_serial 01 -days 3650 \
    -config ${configFolder}/openssl.cnf \
    -extensions v3_ca \
    -key ${outputFolder}/ca/private/cakey.pem \
    -out ${outputFolder}/ca/csr/cacert.pem \
    -subj "/C=DE/ST=Saxony/L=Dresden/O=FICODES CA/CN=FICODES-CA/serialNumber=01"

  ## Convert x509 CA cert
  openssl x509 -in ${outputFolder}/ca/csr/cacert.pem -out ${outputFolder}/ca/certs/cacert.pem -outform PEM

  openssl pkcs8 -topk8 -nocrypt -in ${outputFolder}/ca/private/cakey.pem -out ${outputFolder}/ca/private/cakey-pkcs8.pem

else
  echo "CA already exists, skipping generation."
fi

kubectl create secret generic ${caSecretName} --from-file=${outputFolder}/ca/certs/cacert.pem --namespace ${caSecretNameSpace} -o yaml --dry-run=client > ${k3sFolder}/base-cluster/trust-anchor/root-ca.yaml
kubectl create secret generic gx-registry-keypair --from-file=PRIVATE_KEY=${outputFolder}/ca/private/cakey-pkcs8.pem --from-file=X509_CERTIFICATE=${outputFolder}/ca/certs/cacert.pem --namespace infra -o yaml --dry-run=client > ${k3sFolder}/base-cluster/infra/gx-registry/secret.yaml
ca=$(cat ${outputFolder}/ca/certs/cacert.pem | sed '/-----BEGIN CERTIFICATE-----/d' | sed '/-----END CERTIFICATE-----/d' | tr -d '\n')
yq -i "(.spec.template.spec.initContainers[] | select(.name == \"local-trust\") | .env[] | select(.name == \"ROOT_CA\")).value = \"$ca\"" ${k3sFolder}/base-cluster/infra/gx-registry/deployment-registry.yaml
