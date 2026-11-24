#!/usr/bin/env bash
# Genera los recursos de observabilidad del microservicio para Kubernetes a partir
# de los MISMOS archivos que usa Docker Compose (una sola fuente de verdad):
#   - PrometheusRule  <- observabilidad/prometheus/reglas/ms-productos.yml
#   - ConfigMap con el dashboard <- observabilidad/grafana/dashboards/ms-productos-devops.json
#     (el sidecar de Grafana lo carga automáticamente por la etiqueta grafana_dashboard=1)
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
NS="${NAMESPACE:-ms-productos}"

cat <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ms-productos
  namespace: $NS
  labels:
    app: ms-productos
    release: kube-prometheus-stack
spec:
YAML
sed 's/^/  /' "$RAIZ/observabilidad/prometheus/reglas/ms-productos.yml"

echo "---"
kubectl create configmap ms-productos-dashboard \
  --namespace "$NS" \
  --from-file="ms-productos-devops.json=$RAIZ/observabilidad/grafana/dashboards/ms-productos-devops.json" \
  --dry-run=client -o yaml \
  | sed -e 's/^metadata:$/metadata:\n  labels:\n    grafana_dashboard: "1"\n  annotations:\n    grafana_folder: ms-productos/'
