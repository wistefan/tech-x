#!/bin/bash

cd "$(dirname "$0")"

set -x
set -e

k3sFolder="../k3s"
targetNamespace="trust-anchor"
certsOutputFolder="./out"

# --- Parse named parameters ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --k3sFolder)
      k3sFolder="$2"
      shift 2
      ;;
    --certsOutputFolder)
      certsOutputFolder=("$2")
      shift 2
      ;;
    --targetNamespace)
      targetNamespace=("$2")
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# update infra namespace
kubectl create secret tls local-wildcard --cert=${certsOutputFolder}/client/certs/client-chain-bundle.cert.pem --key=${certsOutputFolder}/client/private/client.key.pem --namespace infra -o yaml --dry-run=client > ${k3sFolder}/base-cluster/infra/local-wildcard.yaml

# update the user namespace
kubectl create secret generic cert-chain --from-file=${certsOutputFolder}/client/certs/client-chain-bundle.cert.pem --namespace ${targetNamespace} -o yaml --dry-run=client > ${k3sFolder}/base-cluster/${targetNamespace}/cert-chain.yaml
kubectl create secret generic signing-key --from-file=${certsOutputFolder}/client/private/client.key.pem --namespace ${targetNamespace} -o yaml --dry-run=client > ${k3sFolder}/base-cluster/${targetNamespace}/signing-key.yaml
