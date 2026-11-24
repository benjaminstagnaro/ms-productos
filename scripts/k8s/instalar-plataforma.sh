#!/usr/bin/env bash
# Instala o actualiza la plataforma de observabilidad del clúster (namespace "monitoring").
# Es idempotente: el pipeline la ejecuta en cada despliegue y solo cambia lo que difiere.
#
#   kube-prometheus-stack  Prometheus Operator, Prometheus, Alertmanager, Grafana,
#                          node-exporter y kube-state-metrics (CPU/memoria de nodos y pods)
#   loki                   almacenamiento y consulta de logs
#   alloy                  recolector de logs de los pods -> Loki
#   pushgateway            recibe las métricas del pipeline CI/CD
#
# Las versiones de los charts están fijas: una actualización es un cambio revisable en Git.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
NS=monitoring
VALORES="$RAIZ/observabilidad/k8s"

KUBE_PROMETHEUS_STACK_VERSION=93.10.0
LOKI_VERSION=21.6.0
ALLOY_VERSION=1.16.0
PUSHGATEWAY_VERSION=3.11.2

echo "==> Repositorios de charts"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null
helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# La contraseña de Grafana se genera una sola vez y queda solo dentro del clúster
if ! kubectl -n "$NS" get secret grafana-admin >/dev/null 2>&1; then
  echo "==> Creando la contraseña de administrador de Grafana"
  kubectl -n "$NS" create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -base64 18)}"
fi

instalar() {
  local release=$1 chart=$2 version=$3 valores=$4
  echo "==> $release ($chart $version)"
  helm upgrade --install "$release" "$chart" --version "$version" \
    --namespace "$NS" -f "$valores" --wait --timeout 10m
}

instalar kube-prometheus-stack prometheus-community/kube-prometheus-stack "$KUBE_PROMETHEUS_STACK_VERSION" "$VALORES/kube-prometheus-stack.yaml"
instalar loki        grafana-community/loki                      "$LOKI_VERSION"        "$VALORES/loki.yaml"
instalar alloy       grafana/alloy                               "$ALLOY_VERSION"       "$VALORES/alloy.yaml"
instalar pushgateway prometheus-community/prometheus-pushgateway "$PUSHGATEWAY_VERSION" "$VALORES/pushgateway.yaml"

echo "==> Plataforma de observabilidad lista"
kubectl -n "$NS" get pods -o wide
