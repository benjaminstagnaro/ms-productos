#!/usr/bin/env bash
# Publica en el Pushgateway las métricas de calidad y despliegue de esta ejecución del
# pipeline. Prometheus las guarda como series de tiempo y Grafana las muestra en la fila
# "CI/CD" del dashboard (tiempo de despliegue, cobertura, pruebas, vulnerabilidades...).
#
# Uso: PUSHGATEWAY_URL=http://127.0.0.1:9091 ENTORNO=produccion scripts/observabilidad/publicar-metricas-cicd.sh
# Las métricas llegan por variables de entorno (las calculan los jobs anteriores del pipeline).
set -euo pipefail

URL="${PUSHGATEWAY_URL:?Falta PUSHGATEWAY_URL}"
ENTORNO="${ENTORNO:-produccion}"
AHORA=$(date +%s)

num() { local v="${1:-}"; [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && echo "$v" || echo "NaN"; }

METRICAS=$(cat <<PROM
# HELP cicd_despliegue_duracion_segundos Duración del despliegue (aplicar manifiestos -> réplicas listas).
# TYPE cicd_despliegue_duracion_segundos gauge
cicd_despliegue_duracion_segundos $(num "${DURACION_DESPLIEGUE:-}")
# HELP cicd_pipeline_duracion_segundos Lead time: inicio de la ejecución del pipeline -> versión funcionando.
# TYPE cicd_pipeline_duracion_segundos gauge
cicd_pipeline_duracion_segundos $(num "${DURACION_PIPELINE:-}")
# HELP cicd_despliegue_timestamp_segundos Momento del último despliegue exitoso (epoch).
# TYPE cicd_despliegue_timestamp_segundos gauge
cicd_despliegue_timestamp_segundos $AHORA
# HELP cicd_despliegue_info Versión desplegada (las etiquetas identifican commit y ejecución).
# TYPE cicd_despliegue_info gauge
cicd_despliegue_info{version="${VERSION:-desconocida}",commit="${COMMIT:-desconocido}",ejecucion="${EJECUCION:-0}"} 1
# HELP cicd_cobertura_lineas_ratio Cobertura de líneas medida por JaCoCo (0-1).
# TYPE cicd_cobertura_lineas_ratio gauge
cicd_cobertura_lineas_ratio $(num "${COBERTURA_LINEAS:-}")
# HELP cicd_cobertura_ramas_ratio Cobertura de ramas medida por JaCoCo (0-1).
# TYPE cicd_cobertura_ramas_ratio gauge
cicd_cobertura_ramas_ratio $(num "${COBERTURA_RAMAS:-}")
# HELP cicd_pruebas_total Pruebas automatizadas ejecutadas.
# TYPE cicd_pruebas_total gauge
cicd_pruebas_total $(num "${PRUEBAS_TOTAL:-}")
# HELP cicd_pruebas_fallidas Pruebas fallidas o con error.
# TYPE cicd_pruebas_fallidas gauge
cicd_pruebas_fallidas $(num "${PRUEBAS_FALLIDAS:-}")
# HELP cicd_quality_gate_aprobado 1 si SonarCloud aprobó el Quality Gate.
# TYPE cicd_quality_gate_aprobado gauge
cicd_quality_gate_aprobado $(num "${QUALITY_GATE:-}")
# HELP cicd_vulnerabilidades Vulnerabilidades encontradas por Snyk por severidad y origen.
# TYPE cicd_vulnerabilidades gauge
cicd_vulnerabilidades{origen="dependencias",severidad="critical"} $(num "${VULN_DEP_CRITICAL:-0}")
cicd_vulnerabilidades{origen="dependencias",severidad="high"} $(num "${VULN_DEP_HIGH:-0}")
cicd_vulnerabilidades{origen="dependencias",severidad="medium"} $(num "${VULN_DEP_MEDIUM:-0}")
cicd_vulnerabilidades{origen="dependencias",severidad="low"} $(num "${VULN_DEP_LOW:-0}")
cicd_vulnerabilidades{origen="imagen",severidad="critical"} $(num "${VULN_IMG_CRITICAL:-0}")
cicd_vulnerabilidades{origen="imagen",severidad="high"} $(num "${VULN_IMG_HIGH:-0}")
# HELP cicd_auditoria_controles Controles de la auditoría de cumplimiento por resultado.
# TYPE cicd_auditoria_controles gauge
cicd_auditoria_controles{resultado="aprobado"} $(num "${AUDITORIA_APROBADOS:-}")
cicd_auditoria_controles{resultado="fallido"} $(num "${AUDITORIA_FALLIDOS:-}")
cicd_auditoria_controles{resultado="advertencia"} $(num "${AUDITORIA_ADVERTENCIAS:-}")
PROM
)

echo "$METRICAS" | grep -v '^#'
# PUT reemplaza el grupo completo: siempre queda la foto de la última ejecución
echo "$METRICAS" | curl -fsS -X PUT --data-binary @- "$URL/metrics/job/cicd/entorno/$ENTORNO"
echo "Métricas del pipeline publicadas en $URL (entorno=$ENTORNO)"
