#!/usr/bin/env bash
# Genera tráfico realista contra la API (lecturas, escrituras y algunos errores esperados)
# para que el dashboard muestre datos y se puedan comprobar métricas, logs y alertas.
# Uso: scripts/observabilidad/generar-trafico.sh [URL_BASE] [ITERACIONES]
set -uo pipefail

BASE_URL="${1:-http://localhost:8080}"
ITERACIONES="${2:-30}"
JSON='Content-Type: application/json'

for i in $(seq 1 "$ITERACIONES"); do
  ID=$(curl -s -X POST "$BASE_URL/api/productos" -H "$JSON" \
        -d "{\"nombre\":\"Producto $i\",\"descripcion\":\"tráfico de prueba\",\"precio\":$((1000 + i * 10)),\"stock\":5,\"categoria\":\"demo\"}" \
       | sed -E 's/.*"id":([0-9]+).*/\1/')
  curl -s -o /dev/null "$BASE_URL/api/productos"
  curl -s -o /dev/null "$BASE_URL/api/productos?categoria=demo"
  curl -s -o /dev/null "$BASE_URL/api/productos/$ID"
  curl -s -o /dev/null -X PATCH "$BASE_URL/api/productos/$ID/stock?cantidad=-2"
  # Errores esperados (cada uno se cuenta en productos_errores_total y queda en los logs)
  if (( i % 3 == 0 )); then curl -s -o /dev/null -X PATCH "$BASE_URL/api/productos/$ID/stock?cantidad=-99"; fi   # 409
  if (( i % 4 == 0 )); then curl -s -o /dev/null "$BASE_URL/api/productos/999999"; fi                            # 404
  if (( i % 5 == 0 )); then curl -s -o /dev/null -X POST "$BASE_URL/api/productos" -H "$JSON" -d '{"nombre":""}'; fi # 400
  if (( i % 2 == 0 )); then curl -s -o /dev/null -X DELETE "$BASE_URL/api/productos/$ID"; fi
done
echo "Tráfico generado: $ITERACIONES iteraciones contra $BASE_URL"
