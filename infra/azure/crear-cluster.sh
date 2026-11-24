#!/usr/bin/env bash
# Crea el clúster de Kubernetes en Azure (AKS) donde el pipeline despliega ms-productos.
# Pensado para ejecutarse en Azure Cloud Shell (https://shell.azure.com), que ya trae
# az, kubectl y helm. Es idempotente: si el clúster ya existe, solo entrega la credencial.
#
#   bash infra/azure/crear-cluster.sh
#
# Variables opcionales:
#   REGION=eastus  VM_SIZE=Standard_B2ms  GRUPO=rg-ms-productos  CLUSTER=aks-ms-productos
#
# Costo aproximado con los valores por defecto (Azure for Students, crédito de US$100):
#   plano de control gratis (tier Free) + 1 nodo B2ms (~US$2/día) + IP públicas y discos.
#   Para no consumir crédito cuando no se usa:  az aks stop  -g rg-ms-productos -n aks-ms-productos
#   Para volver a encenderlo:                   az aks start -g rg-ms-productos -n aks-ms-productos
#   Para borrar todo al terminar el semestre:   az group delete -n rg-ms-productos
set -euo pipefail

# Azure for Students solo permite crear recursos en algunas regiones. Para verlas:
#   az policy assignment list --query "[].parameters.listOfAllowedLocations.value" -o tsv
REGION="${REGION:-brazilsouth}"
VM_SIZE="${VM_SIZE:-Standard_B2ms}"
GRUPO="${GRUPO:-rg-ms-productos}"
CLUSTER="${CLUSTER:-aks-ms-productos}"

echo "==> Suscripción activa"
az account show --query "{nombre:name, id:id}" -o table

echo "==> Registrando los proveedores de recursos necesarios (solo tarda la primera vez)"
for proveedor in Microsoft.ContainerService Microsoft.Compute Microsoft.Network Microsoft.Storage; do
  az provider register --namespace "$proveedor" --wait
done

echo "==> Grupo de recursos $GRUPO"
if ! az group show --name "$GRUPO" -o none 2>/dev/null; then
  az group create --name "$GRUPO" --location "$REGION" --tags proyecto=ms-productos asignatura=DOY0101 -o none
fi

if az aks show -g "$GRUPO" -n "$CLUSTER" -o none 2>/dev/null; then
  echo "==> El clúster $CLUSTER ya existe"
else
  echo "==> Creando el clúster AKS $CLUSTER (tarda entre 5 y 10 minutos)"
  # - tier Free: el plano de control no se cobra
  # - Azure CNI + Cilium: hace cumplir las NetworkPolicy del proyecto
  # - 1 nodo de 2 vCPU / 8 GB: alcanza para la app, MySQL y la plataforma de observabilidad
  az aks create \
    --resource-group "$GRUPO" \
    --name "$CLUSTER" \
    --location "$REGION" \
    --tier free \
    --node-count 1 \
    --node-vm-size "$VM_SIZE" \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --network-policy cilium \
    --enable-managed-identity \
    --generate-ssh-keys \
    --tags proyecto=ms-productos \
    -o none
fi

echo "==> Probando la conexión"
az aks get-credentials -g "$GRUPO" -n "$CLUSTER" --overwrite-existing -o none
kubectl get nodes -o wide

echo "==> Credencial para GitHub Actions"
ARCHIVO="$HOME/kubeconfig-github-actions.yaml"
az aks get-credentials -g "$GRUPO" -n "$CLUSTER" --admin --file "$ARCHIVO" --overwrite-existing -o none
cat <<MSG

Listo. Falta guardar la credencial en GitHub (una sola vez):

  1. Copia TODO el texto que aparece entre las líneas ===== (es una sola línea larga).
  2. En GitHub: ms-productos > Settings > Environments > produccion > Add environment secret
     Nombre: KUBECONFIG_AKS     Valor: el texto copiado

  El secreto queda asociado al environment "produccion", que solo puede usar la rama main.
  No lo compartas: da acceso de administrador al clúster.

=====
$(base64 -w0 "$ARCHIVO")
=====
MSG
rm -f "$ARCHIVO"
