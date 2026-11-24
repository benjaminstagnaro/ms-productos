#!/usr/bin/env bash
# Pruebas de humo contra el entorno desplegado.
# Uso: ./scripts/smoke-test.sh [URL_BASE] [MIN_INSTANCIAS]
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
MIN_INSTANCIAS="${2:-1}"

paso() { echo ""; echo "==> $1"; }

paso "1. Healthcheck (sonda de readiness publicada en la API)"
curl -fsS "$BASE_URL/readyz" | grep -q '"status":"UP"'
echo "OK: servicio UP"

paso "1b. Actuator y métricas NO deben estar expuestos hacia afuera"
for RUTA in /actuator/health /actuator/prometheus; do
  CODIGO=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL$RUTA")
  [ "$CODIGO" = "404" ] || { echo "ERROR: $RUTA respondió $CODIGO desde afuera (se esperaba 404)"; exit 1; }
done
echo "OK: /actuator solo es accesible por el puerto interno de gestión"

paso "2. Versión desplegada (trazabilidad)"
curl -fsS "$BASE_URL/api/info"
echo ""
REQUEST_ID=$(curl -fsS -D - -o /dev/null "$BASE_URL/api/info" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-request-id" {print $2}')
[ -n "$REQUEST_ID" ] || { echo "ERROR: la respuesta no trae X-Request-Id"; exit 1; }
echo "OK: X-Request-Id=$REQUEST_ID (permite buscar la petición en los logs)"

paso "3. Crear producto"
RESPUESTA=$(curl -fsS -X POST "$BASE_URL/api/productos" \
  -H 'Content-Type: application/json' \
  -d '{"nombre":"Producto smoke test","descripcion":"Creado por el pipeline","precio":1990,"stock":10,"categoria":"pruebas"}')
ID=$(echo "$RESPUESTA" | sed -E 's/.*"id":([0-9]+).*/\1/')
echo "OK: creado con id $ID"

paso "4. Consultar producto"
curl -fsS "$BASE_URL/api/productos/$ID" | grep -q 'Producto smoke test'
echo "OK"

paso "5. Descontar stock (regla de negocio)"
curl -fsS -X PATCH "$BASE_URL/api/productos/$ID/stock?cantidad=-3" | grep -q '"stock":7'
CODIGO=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "$BASE_URL/api/productos/$ID/stock?cantidad=-100")
[ "$CODIGO" = "409" ] || { echo "ERROR: se esperaba 409 y llegó $CODIGO"; exit 1; }
echo "OK: stock 7 y rechazo de stock negativo (409)"

paso "6. Validación de datos (400)"
CODIGO=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/api/productos" \
  -H 'Content-Type: application/json' -d '{"nombre":""}')
[ "$CODIGO" = "400" ] || { echo "ERROR: se esperaba 400 y llegó $CODIGO"; exit 1; }
echo "OK"

paso "7. Eliminar producto"
curl -fsS -X DELETE "$BASE_URL/api/productos/$ID"
CODIGO=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/productos/$ID")
[ "$CODIGO" = "404" ] || { echo "ERROR: se esperaba 404 y llegó $CODIGO"; exit 1; }
echo "OK"

paso "8. Balanceo de carga entre réplicas (mínimo $MIN_INSTANCIAS)"
INSTANCIAS=$(for _ in $(seq 1 30); do
  curl -fsS "$BASE_URL/api/info" | sed -E 's/.*"instancia":"([^"]+)".*/\1/'
  echo ""
done | sort -u | grep -v '^$')
CANTIDAD=$(echo "$INSTANCIAS" | wc -l | tr -d ' ')
echo "Instancias que respondieron ($CANTIDAD):"
echo "$INSTANCIAS"
[ "$CANTIDAD" -ge "$MIN_INSTANCIAS" ] || { echo "ERROR: respondieron $CANTIDAD réplicas, se esperaban al menos $MIN_INSTANCIAS"; exit 1; }

echo ""
echo "Todas las pruebas de humo pasaron."
