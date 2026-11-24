#!/usr/bin/env bash
# Muestra las direcciones públicas que Azure asignó a la API y a Grafana.
# Nota: se publican por HTTP porque el proyecto no tiene dominio propio; en un entorno
# real se agregaría un Ingress con certificado TLS (cert-manager + Let's Encrypt).
set -euo pipefail

API=$(kubectl -n ms-productos get svc ms-productos -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
GRAFANA=$(kubectl -n monitoring get svc kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[ -n "$API" ] && [ -n "${GITHUB_OUTPUT:-}" ] && echo "api=http://$API/api/productos" >> "$GITHUB_OUTPUT"
{
  echo "## 🌐 Producción en Azure Kubernetes Service"
  echo "| Servicio | Dirección |"
  echo "|---|---|"
  echo "| API | http://$API/api/productos |"
  echo "| Información de la versión | http://$API/api/info |"
  echo "| Grafana (solo lectura sin login) | http://$GRAFANA/d/ms-productos-devops |"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
