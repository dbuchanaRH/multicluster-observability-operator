#!/bin/bash

export KUBECONFIG="${SHARED_DIR}/hub-1.kc"
export CTX_HUB_CLUSTER=$(kubectl config current-context)
# Extract hub cluster info from JSON
HUB_API_URL=$(jq -r '.api_url' "${SHARED_DIR}/hub-1.json") &>/dev/null
TEMP_CA_FILE=$(mktemp)

# Writing hub's CA to a temp file
kubectl get cm kube-root-ca.crt -n kube-public -o jsonpath='{.data.ca\.crt}' >${TEMP_CA_FILE}

clusteradm init --wait --context ${CTX_HUB_CLUSTER} &>/dev/null
set +x
HUB_TOKEN=$(clusteradm get token --context ${CTX_HUB_CLUSTER})

IS_HUB_TOKEN=true
if [[ -z ${HUB_TOKEN} ]]; then
  echo "Error: Failed to get hub token..."
  echo "Skipping join..."
  IS_HUB_TOKEN=false
fi
set -x

declare -A CSR_CREATED=()

for ((i = 1; i <= CLUSTERPOOL_MANAGED_COUNT; i++)); do
  if $IS_HUB_TOKEN && [[ -n ${SHARED_DIR} ]] && [[ -f "${SHARED_DIR}/managed-${i}.json" ]]; then

    export KUBECONFIG="${SHARED_DIR}/managed-${i}.kc"
    export CTX_MANAGED_CLUSTER=$(kubectl config current-context)

    echo "Join managed-${i} to hub"

    set +x
    clusteradm join \
      --hub-token ${HUB_TOKEN} \
      --hub-apiserver ${HUB_API_URL} \
      --wait \
      --cluster-name "managed-${i}" \
      --context ${CTX_MANAGED_CLUSTER} \
      --ca-file "$TEMP_CA_FILE"
    set -x
    CSR_CREATED[$i]=$i
  fi
done

export KUBECONFIG="${SHARED_DIR}/hub-1.kc"

# Need to wait brefore accepting. Wait for each join to process and need timeout for each join.
echo "Waiting for CSR from each managed cluster..."
for j in {1..60}; do
  for ((i = 1; i <= CLUSTERPOOL_MANAGED_COUNT; i++)); do
    if $IS_HUB_TOKEN && [[ -n ${CSR_CREATED[$i]} ]] && [[ $(kubectl get csr --context ${CTX_HUB_CLUSTER} 2>/dev/null | grep managed-${i}) ]]; then
      unset CSR_CREATED[$i]
      clusteradm accept --clusters "managed-${i}" --context ${CTX_HUB_CLUSTER} &>/dev/null
    fi
    if [[ ${#CSR_CREATED[@]} -eq 0 ]]; then
      break 2
    fi
  done
  if [[ ${j} -eq 60 ]]; then
    for managed_num in ${!CSR_CREATED[@]}; do
      echo "timeout wait for CSR for managed-${managed_num} is not created."
    done
    break
  fi
  echo "retrying in 10s..."
  sleep 10
done

# Checking that managed clusters were successfully added
kubectl get managedcluster --context ${CTX_HUB_CLUSTER}
