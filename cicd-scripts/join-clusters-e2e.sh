#!/bin/bash

# can get hub cluster context
export KUBECONFIG="${SHARED_DIR}/hub-1.kc"
export CTX_HUB_CLUSTER=$(kubectl config current-context)
# Extract hub cluster info from JSON
HUB_API_URL=$(jq -r '.api_url' "${SHARED_DIR}/hub-1.json") &>/dev/null
TEMP_CA_FILE=$(mktemp)

# Writing hub's CA to a temp file
$(kubectl get cm kube-root-ca.crt -n kube-public -o jsonpath='{.data.ca\.crt}' > ${TEMP_CA_FILE})

clusteradm init --wait --context ${CTX_HUB_CLUSTER} &>/dev/null
HUB_TOKEN=$(clusteradm get token --context ${CTX_HUB_CLUSTER})

if [[ -z "${HUB_TOKEN}" ]]; then
    echo "Error: Failed to get hub token...\nSkipping join..."
    # should not try to join if failed to get hub token...
fi
# list of managed clusters
managed_clusters=""
for ((i=1 ; i <= CLUSTERPOOL_MANAGED_COUNT ; i++)); do
  if [[ ! -z "${HUB_TOKEN}" ]] && [[ ! -z "${SHARED_DIR}" ]] && [[ -f "${SHARED_DIR}/managed-${i}.json" ]]; then
    if [[ $i -eq 1 ]]; then
      managed_clusters="managed-${i}"
    else
      managed_clusters+=",managed-${i}"
    fi
    export KUBECONFIG="${SHARED_DIR}/managed-${i}.kc" 
    export CTX_MANAGED_CLUSTER=$(kubectl config current-context)

    echo "Join managed-${i} to hub"

    clusteradm join \
        --hub-token ${HUB_TOKEN} \
        --hub-apiserver ${HUB_API_URL} \
        --wait \
        --cluster-name "managed-${i}" \
        --context ${CTX_MANAGED_CLUSTER} \
        --ca-file "$TEMP_CA_FILE"
  fi
done

kubectl config use ${CTX_HUB_CLUSTER}

# Need to wait brefore accepting. Wait for each join to process and need timeout for each join.
echo "Waiting for CSRs to appear..."

# TODO need to wait for CSR to be created for each managed cluster
# for ((i=1 ; i <= CLUSTERPOOL_MANAGED_COUNT ; i++)); do
#   if [[ ! -z "${HUB_TOKEN}" ]] && [[ ! -z "${SHARED_DIR}" ]] && [[ -f "${SHARED_DIR}/managed-${i}.json" ]]; then

    
#   fi
# done
clusteradm accept --clusters $managed_clusters --context ${CTX_HUB_CLUSTER}
# can move accept logic down here
# Checking for agent that runs on the managed cluster
kubectl -n open-cluster-management-agent get pod --context ${CTX_MANAGED_CLUSTER}

# Checking for agent that runs on the hub cluster
kubectl get managedcluster --context ${CTX_HUB_CLUSTER}