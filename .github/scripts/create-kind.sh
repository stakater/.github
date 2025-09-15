#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <KIND_CLUSTER_NAME>"
    exit 1
fi

CLUSTER_NAME="$1"

if ! command -v kind >/dev/null 2>&1; then
    echo "kind not found, installing..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
    chmod +x ./kind
    mv ./kind /usr/local/bin/kind
else
    echo "kind is already installed."
fi

echo "Creating Kind Cluster..."
if kind get clusters | grep -w "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "Kind cluster $CLUSTER_NAME already exists."
else
    kind create cluster --name "$CLUSTER_NAME" --wait 120s
fi

