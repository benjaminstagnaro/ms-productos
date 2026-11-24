#!/usr/bin/env bash
# Despliegue del microservicio en Kubernetes con protección del entorno productivo.
#
#   1. Crea el namespace y, solo la primera vez, el Secret con contraseñas aleatorias.
#   2. Aplica los manifiestos (misma imagen que se probó y escaneó) y la configuración
#      de observabilidad (PodMonitor, reglas de alerta y dashboard).
#   3. Espera el rolling update. Si las réplicas nuevas no quedan sanas, ROLLBACK automático.
#   4. Pruebas de humo contra el servicio. Si fallan, ROLLBACK.
#   5. Verificación con Prometheus: todas las réplicas reportan métricas y la tasa de
#      errores 5xx es menor al umbral. Si no, ROLLBACK.
#
# Como el Deployment usa maxUnavailable=0, mientras la versión nueva no está sana la
# anterior sigue atendiendo: una versión defectuosa nunca deja al servicio sin réplicas.
#
# Uso:  IMAGEN=ghcr.io/usuario/ms-productos:1.1.0-abc1234 scripts/k8s/desplegar.sh
# Variables opcionales: SIMULACION=despliegue-defectuoso, TIMEOUT_ROLLOUT=240s,
#                       PROVEEDOR=aks|kind, UMBRAL_ERRORES=0.05
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
NS=ms-productos
IMAGEN="${IMAGEN:?Falta la variable IMAGEN}"
SIMULACION="${SIMULACION:-ninguna}"
TIMEOUT_ROLLOUT="${TIMEOUT_ROLLOUT:-240s}"
PROVEEDOR="${PROVEEDOR:-aks}"
UMBRAL_ERRORES="${UMBRAL_ERRORES:-0.05}"
PROMETHEUS_SVC="${PROMETHEUS_SVC:-kube-prometheus-stack-prometheus}"
INICIO=$(date +%s)
PIDS_PF=()

paso() { echo ""; echo "==> $1"; }
salida() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT"; return 0; }
resumen() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; return 0; }
limpiar() { for pid in "${PIDS_PF[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done; }
trap limpiar EXIT

# Abre un túnel local hacia un Service del clúster (no requiere exponerlo a Internet)
tunel() {
  local namespace=$1 servicio=$2 puerto_local=$3 puerto_remoto=$4
  kubectl -n "$namespace" port-forward "svc/$servicio" "$puerto_local:$puerto_remoto" >/dev/null 2>&1 &
  PIDS_PF+=($!)
  for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:$puerto_local" && return 0
    sleep 1
  done
  echo "No se pudo abrir el túnel a $servicio" >&2
  return 1
}

diagnostico() {
  paso "Diagnóstico de la versión rechazada"
  kubectl -n "$NS" get pods -o wide || true
  kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -n 15 || true
  local pod
  pod=$(kubectl -n "$NS" get pods -l app=ms-productos --sort-by=.metadata.creationTimestamp \
          -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)
  if [ -n "$pod" ]; then
    echo "--- Últimas líneas de log de $pod (versión nueva)"
    kubectl -n "$NS" logs "$pod" --tail=25 2>/dev/null || true
  fi
}

rollback() {
  local motivo=$1
  echo "::error title=Despliegue rechazado::$motivo"
  diagnostico
  if [ -n "${REVISION_ANTERIOR:-}" ]; then
    paso "ROLLBACK automático a la revisión $REVISION_ANTERIOR"
    kubectl -n "$NS" rollout undo deployment/ms-productos --to-revision="$REVISION_ANTERIOR"
    kubectl -n "$NS" rollout status deployment/ms-productos --timeout=300s
    IMAGEN_ACTUAL=$(kubectl -n "$NS" get deployment ms-productos -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "Producción sigue funcionando con: $IMAGEN_ACTUAL"
    resumen "## ⛔ Despliegue rechazado y revertido"
    resumen "| Motivo | Acción | Versión que sigue en producción |"
    resumen "|---|---|---|"
    resumen "| $motivo | \`kubectl rollout undo\` a la revisión $REVISION_ANTERIOR | \`$IMAGEN_ACTUAL\` |"
  else
    echo "Era el primer despliegue: no hay una versión anterior a la cual volver."
    resumen "## ⛔ Despliegue rechazado: $motivo (primer despliegue, sin versión anterior)"
  fi
  salida resultado rechazado
  exit 1
}

paso "1. Namespace y credenciales"
kubectl apply -f "$RAIZ/k8s/base/namespace.yaml"
if ! kubectl -n "$NS" get secret ms-productos-secret >/dev/null 2>&1; then
  echo "Primer despliegue: se generan contraseñas aleatorias para MySQL (nunca salen del clúster)"
  kubectl -n "$NS" create secret generic ms-productos-secret \
    --from-literal=MYSQL_ROOT_PASSWORD="$(openssl rand -hex 16)" \
    --from-literal=DB_USER=productos \
    --from-literal=DB_PASSWORD="$(openssl rand -hex 16)"
fi
REVISION_ANTERIOR=$(kubectl -n "$NS" get deployment ms-productos \
  -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || true)
IMAGEN_ANTERIOR=$(kubectl -n "$NS" get deployment ms-productos \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
echo "Versión actual en producción: ${IMAGEN_ANTERIOR:-(ninguna)} (revisión ${REVISION_ANTERIOR:-0})"

paso "2. Aplicar manifiestos ($IMAGEN)"
[ "$SIMULACION" != "ninguna" ] && echo "::warning title=Simulación::Se despliega una versión defectuosa a propósito ($SIMULACION)"
bash "$RAIZ/scripts/k8s/renderizar.sh" "$IMAGEN" "$SIMULACION" > /tmp/ms-productos-render.yaml
kubectl apply -f /tmp/ms-productos-render.yaml
# Anotación visible en "kubectl rollout history": qué commit y ejecución generó cada revisión
kubectl -n "$NS" annotate deployment/ms-productos --overwrite \
  kubernetes.io/change-cause="imagen=$IMAGEN ejecucion=${GITHUB_RUN_ID:-manual} commit=${GITHUB_SHA:-local}"
bash "$RAIZ/scripts/k8s/renderizar-observabilidad.sh" | kubectl apply -f -

paso "3. Esperar el rolling update (máximo $TIMEOUT_ROLLOUT)"
kubectl -n "$NS" rollout status statefulset/mysql --timeout=300s
if ! kubectl -n "$NS" rollout status deployment/ms-productos --timeout="$TIMEOUT_ROLLOUT"; then
  rollback "las réplicas nuevas no quedaron sanas dentro de $TIMEOUT_ROLLOUT"
fi
FIN_ROLLOUT=$(date +%s)
kubectl -n "$NS" get pods -o wide

paso "4. Pruebas de humo"
tunel "$NS" ms-productos 18080 80
if ! bash "$RAIZ/scripts/smoke-test.sh" http://127.0.0.1:18080 1; then
  rollback "las pruebas de humo fallaron"
fi

URL_PUBLICA=""
if [ "$PROVEEDOR" = "aks" ]; then
  paso "4b. IP pública del servicio"
  for _ in $(seq 1 36); do
    IP=$(kubectl -n "$NS" get svc ms-productos -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$IP" ] && break
    sleep 5
  done
  if [ -n "${IP:-}" ]; then
    URL_PUBLICA="http://$IP"
    echo "API pública: $URL_PUBLICA/api/productos"
    bash "$RAIZ/scripts/smoke-test.sh" "$URL_PUBLICA" 2 || rollback "las pruebas de humo por la IP pública fallaron"
  else
    echo "::warning::Azure aún no asigna la IP pública; se omite la prueba externa"
  fi
fi

paso "5. Verificación con Prometheus (salud post-despliegue)"
tunel monitoring "$PROMETHEUS_SVC" 19090 9090
consultar() {
  curl -fsS --get http://127.0.0.1:19090/api/v1/query --data-urlencode "query=$1" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "0")'
}
REPLICAS=$(kubectl -n "$NS" get deployment ms-productos -o jsonpath='{.status.readyReplicas}')
MONITOREADAS=0
for _ in $(seq 1 24); do
  MONITOREADAS=$(consultar 'count(up{job="ms-productos", namespace="ms-productos"} == 1)')
  [ "${MONITOREADAS%.*}" -ge "$REPLICAS" ] && break
  sleep 10
done
echo "Réplicas listas: $REPLICAS · réplicas que Prometheus ve activas: $MONITOREADAS"
[ "${MONITOREADAS%.*}" -ge "$REPLICAS" ] || rollback "Prometheus no logra leer métricas de todas las réplicas"

# Tráfico de verificación y medición de la tasa de errores 5xx de la versión nueva
for _ in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:18080/api/productos; done
sleep 20
TASA_ERRORES=$(consultar 'sum(rate(http_server_requests_seconds_count{application="ms-productos", namespace="ms-productos", status=~"5.."}[2m])) / clamp_min(sum(rate(http_server_requests_seconds_count{application="ms-productos", namespace="ms-productos"}[2m])), 1e-9)')
echo "Tasa de errores 5xx: $TASA_ERRORES (umbral $UMBRAL_ERRORES)"
if python3 -c "import sys; sys.exit(0 if float('$TASA_ERRORES') <= float('$UMBRAL_ERRORES') else 1)"; then
  echo "OK: la versión nueva cumple el objetivo de errores"
else
  rollback "la tasa de errores 5xx ($TASA_ERRORES) supera el umbral $UMBRAL_ERRORES"
fi

DURACION=$((FIN_ROLLOUT - INICIO))
salida resultado aprobado
salida duracion_despliegue "$DURACION"
salida url_publica "$URL_PUBLICA"
resumen "## 🚀 Despliegue en Kubernetes ($PROVEEDOR)"
resumen "| Dato | Valor |"
resumen "|---|---|"
resumen "| Imagen | \`$IMAGEN\` |"
resumen "| Versión anterior | \`${IMAGEN_ANTERIOR:-ninguna}\` |"
resumen "| Tiempo de despliegue (aplicar → réplicas listas) | ${DURACION} s |"
resumen "| Réplicas listas / monitoreadas | $REPLICAS / $MONITOREADAS |"
resumen "| Tasa de errores 5xx | $TASA_ERRORES |"
[ -n "$URL_PUBLICA" ] && resumen "| API pública | $URL_PUBLICA/api/productos |"
echo ""
echo "Despliegue aprobado en ${DURACION} s"
