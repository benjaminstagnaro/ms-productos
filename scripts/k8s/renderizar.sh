#!/usr/bin/env bash
# Genera los manifiestos finales del entorno en la nube (overlay k8s/overlays/nube)
# con la imagen exacta que construyó el pipeline. Lo usan la validación, la auditoría
# de cumplimiento y el despliegue, así los tres revisan exactamente lo mismo.
#
# Uso: scripts/k8s/renderizar.sh <imagen:etiqueta> [simulacion]
#   simulacion (solo para demostrar que los controles funcionan):
#     despliegue-defectuoso  -> la app apunta a una base de datos inexistente (nunca queda "Ready")
#     politica-kubernetes    -> contenedor privilegiado y como root (lo debe rechazar la auditoría)
set -euo pipefail

IMAGEN="${1:?Indica la imagen, ej: ghcr.io/usuario/ms-productos:1.1.0-abc1234}"
SIMULACION="${2:-ninguna}"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
KUSTOMIZE="${KUSTOMIZE:-kubectl kustomize}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OVERLAY="$(realpath --relative-to="$TMP" "$RAIZ/k8s/overlays/nube")"

cat > "$TMP/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - $OVERLAY
images:
  - name: ghcr.io/benjaminstagnaro/ms-productos
    newName: ${IMAGEN%:*}
    newTag: "${IMAGEN##*:}"
YAML

case "$SIMULACION" in
  ninguna) ;;
  despliegue-defectuoso)
    cat >> "$TMP/kustomization.yaml" <<'YAML'
patches:
  - target: { kind: Deployment, name: ms-productos }
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value: { name: DB_URL, value: "jdbc:mysql://mysql-que-no-existe:3306/productos_db" }
YAML
    ;;
  politica-kubernetes)
    cat >> "$TMP/kustomization.yaml" <<'YAML'
patches:
  - target: { kind: Deployment, name: ms-productos }
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/securityContext
        value: { privileged: true, runAsUser: 0, allowPrivilegeEscalation: true }
      - op: remove
        path: /spec/template/spec/containers/0/resources/limits
YAML
    ;;
  *) echo "Simulación desconocida: $SIMULACION" >&2; exit 2 ;;
esac

# shellcheck disable=SC2086
$KUSTOMIZE "$TMP"
