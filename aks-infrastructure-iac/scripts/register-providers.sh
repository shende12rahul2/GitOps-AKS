#!/usr/bin/env bash
# Phase 1 prerequisite: register resource providers and preview/opt-in features
# used by this POC. Idempotent. Requires Owner or Contributor on the subscription.
set -euo pipefail
sub="${1:?subscription id}"
az account set --subscription "$sub"

for ns in Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.Network Microsoft.Storage \
          Microsoft.KeyVault Microsoft.DBforPostgreSQL Microsoft.Cache Microsoft.ManagedIdentity \
          Microsoft.OperationalInsights Microsoft.Insights Microsoft.Monitor Microsoft.AlertsManagement \
          Microsoft.Dashboard Microsoft.PolicyInsights Microsoft.Compute Microsoft.DevTestLab; do
  az provider register --namespace "$ns" --output none
  echo "registered $ns"
done

# Encryption at host for AKS nodes and the jumpbox (temp disks, caches).
az feature register --namespace Microsoft.Compute --name EncryptionAtHost --output none
until [ "$(az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state -o tsv)" = "Registered" ]; do sleep 20; done
az provider register --namespace Microsoft.Compute --output none

# Private-only Application Gateway v2 (no public IP). Generally available, but
# still enabled per subscription through feature registration.
az feature register --namespace Microsoft.Network --name EnableApplicationGatewayNetworkIsolation --output none
echo "Waiting for EnableApplicationGatewayNetworkIsolation..."
until [ "$(az feature show --namespace Microsoft.Network --name EnableApplicationGatewayNetworkIsolation --query properties.state -o tsv)" = "Registered" ]; do sleep 20; done
az provider register --namespace Microsoft.Network --output none
echo "done"
