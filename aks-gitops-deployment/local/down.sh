#!/usr/bin/env bash
# Removes everything local/up.sh created (namespaces apps, data, airflow, argocd).
set -euo pipefail
kubectl -n argocd delete applicationset microservices-local --ignore-not-found
kubectl -n argocd delete application local-infra --ignore-not-found
helm uninstall airflow -n airflow 2>/dev/null || true
for s in frontend user-service product-service order-service notification-service; do helm uninstall "$s" -n apps 2>/dev/null || true; done
helm uninstall argocd -n argocd 2>/dev/null || true
kubectl delete namespace apps data airflow argocd --ignore-not-found --wait=false
echo "Deletion started. Local images stay in the k3s image store (k3s crictl rmi aks-poc/...)."
