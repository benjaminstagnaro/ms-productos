#!/usr/bin/env bash
# Comprueba que la observabilidad realmente funciona (no solo que los contenedores corren):
#   - Prometheus lee métricas de TODAS las réplicas y tiene cargadas las reglas de alerta
#   - existen las métricas propias del microservicio y las del pipeline
#   - Loki recibió logs de la aplicación
#   - Grafana cargó el dashboard
# Uso: scripts/observabilidad/verificar-observabilidad.sh <min_replicas> [prometheus] [loki] [grafana]
set -euo pipefail

MIN_REPLICAS="${1:-1}"
PROM="${2:-http://127.0.0.1:9090}"
LOKI="${3:-http://127.0.0.1:3100}"
GRAFANA="${4:-http://127.0.0.1:3000}"
FALLAS=0

ok()    { echo "  ✔ $1"; }
falla() { echo "  ✘ $1"; FALLAS=$((FALLAS + 1)); }
consultar() {
  curl -fsS --get "$PROM/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "0")'
}
esperar() {   # esperar <descripción> <consulta PromQL> <mínimo>
  local valor=0
  for _ in $(seq 1 18); do
    valor=$(consultar "$2")
    python3 -c "import sys; sys.exit(0 if float('$valor') >= float('$3') else 1)" && { ok "$1: $valor"; return 0; }
    sleep 5
  done
  falla "$1: $valor (se esperaba >= $3)"
}

echo "==> Prometheus ($PROM)"
esperar "Réplicas de ms-productos monitoreadas" 'count(up{job="ms-productos"} == 1)' "$MIN_REPLICAS"
esperar "Métricas HTTP del microservicio" 'count(http_server_requests_seconds_count{application="ms-productos"})' 1
esperar "Métricas de negocio (productos creados)" 'sum(productos_creados_total)' 1
esperar "Errores registrados por la API" 'sum(productos_errores_total)' 1
esperar "Métricas de CPU/memoria de la JVM" 'count(process_cpu_usage{application="ms-productos"})' "$MIN_REPLICAS"
GRUPOS=$(curl -fsS "$PROM/api/v1/rules" | python3 -c 'import json,sys; g=json.load(sys.stdin)["data"]["groups"]; print(len([x for x in g if x["name"].startswith(("ms-productos","cicd"))]))')
[ "$GRUPOS" -ge 3 ] && ok "Grupos de reglas de alerta cargados: $GRUPOS" || falla "Reglas de alerta cargadas: $GRUPOS (se esperaban 3)"
if [ "${VERIFICAR_CICD:-false}" = "true" ]; then
  esperar "Métricas del pipeline en Pushgateway" 'count(cicd_cobertura_lineas_ratio)' 1
fi

echo "==> Loki ($LOKI)"
LOGS=0
for _ in $(seq 1 18); do
  LOGS=$(curl -fsS --get "$LOKI/loki/api/v1/query_range" \
           --data-urlencode 'query={app="ms-productos"}' --data-urlencode 'limit=500' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" \
         | python3 -c 'import json,sys; print(sum(len(s["values"]) for s in json.load(sys.stdin)["data"]["result"]))' || echo 0)
  [ "$LOGS" -gt 0 ] && break
  sleep 5
done
[ "$LOGS" -gt 0 ] && ok "Líneas de log de ms-productos en Loki: $LOGS" || falla "Loki no tiene logs de ms-productos"
ERRORES_LOG=$(curl -fsS --get "$LOKI/loki/api/v1/query_range" \
                --data-urlencode 'query={app="ms-productos", level=~"WARN|ERROR"}' --data-urlencode "start=$(( $(date +%s) - 900 ))000000000" \
              | python3 -c 'import json,sys; print(sum(len(s["values"]) for s in json.load(sys.stdin)["data"]["result"]))' || echo 0)
[ "$ERRORES_LOG" -gt 0 ] && ok "Logs WARN/ERROR indexados por nivel: $ERRORES_LOG" || falla "No se encontraron logs WARN/ERROR etiquetados por nivel"

if [ -n "$GRAFANA" ] && [ "$GRAFANA" != "-" ]; then
  echo "==> Grafana ($GRAFANA)"
  if curl -fsS "$GRAFANA/api/search?query=ms-productos" | grep -q 'ms-productos-devops'; then
    ok "Dashboard 'ms-productos · DevOps' cargado"
  else
    falla "Grafana no tiene el dashboard"
  fi
fi

echo ""
if [ "$FALLAS" -gt 0 ]; then
  echo "La verificación de observabilidad encontró $FALLAS problema(s)"
  exit 1
fi
echo "Observabilidad verificada: métricas, alertas, logs y dashboard funcionando"
