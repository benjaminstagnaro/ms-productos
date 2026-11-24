# Políticas de seguridad para los manifiestos de Kubernetes del entorno productivo.
# Basadas en el estándar "Restricted" de Pod Security Standards (Kubernetes),
# CIS Kubernetes Benchmark §5.2 e ISO/IEC 27001:2022 (A.8.9 gestión de la configuración).
#
#   deny -> incumplimiento: la auditoría falla y el pipeline se detiene
#   warn -> recomendación: queda registrada en el reporte, no bloquea
package kubernetes

cargas := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

es_carga if cargas[input.kind]

pod_spec := input.spec.template.spec if es_carga

pod_spec := input.spec if input.kind == "Pod"

anotaciones := object.get(input.spec.template.metadata, "annotations", {}) if es_carga

anotaciones := object.get(input.metadata, "annotations", {}) if input.kind == "Pod"

contenedores contains c if {
	some c in pod_spec.containers
}

contenedores contains c if {
	some c in object.get(pod_spec, "initContainers", [])
}

nombre := sprintf("%s/%s", [input.kind, input.metadata.name])

sc(c) := object.get(c, "securityContext", {})

pod_sc := object.get(pod_spec, "securityContext", {})

# K8S-01 · Contenedores privilegiados
deny contains msg if {
	some c in contenedores
	sc(c).privileged == true
	msg := sprintf("[K8S-01] %s: el contenedor '%s' es privilegiado (acceso total al nodo)", [nombre, c.name])
}

# K8S-02 · Escalamiento de privilegios
deny contains msg if {
	some c in contenedores
	not sc(c).allowPrivilegeEscalation == false
	msg := sprintf("[K8S-02] %s: el contenedor '%s' debe declarar allowPrivilegeEscalation: false", [nombre, c.name])
}

# K8S-03 · Ejecución como root
corre_como_no_root(c) if sc(c).runAsNonRoot == true

corre_como_no_root(c) if {
	pod_sc.runAsNonRoot == true
	not sc(c).runAsNonRoot == false
}

deny contains msg if {
	some c in contenedores
	not corre_como_no_root(c)
	msg := sprintf("[K8S-03] %s: el contenedor '%s' debe ejecutarse sin root (runAsNonRoot: true)", [nombre, c.name])
}

deny contains msg if {
	some c in contenedores
	sc(c).runAsUser == 0
	msg := sprintf("[K8S-03] %s: el contenedor '%s' fuerza runAsUser: 0 (root)", [nombre, c.name])
}

# K8S-04 · Capacidades de Linux
deny contains msg if {
	some c in contenedores
	not "ALL" in object.get(sc(c), ["capabilities", "drop"], [])
	msg := sprintf("[K8S-04] %s: el contenedor '%s' debe eliminar todas las capacidades (capabilities.drop: [ALL])", [nombre, c.name])
}

# K8S-05 · Límites de recursos (evita que un pod deje sin recursos al resto)
deny contains msg if {
	some c in contenedores
	some recurso in ["cpu", "memory"]
	object.get(c, ["resources", "limits", recurso], null) == null
	msg := sprintf("[K8S-05] %s: el contenedor '%s' no define límite de %s", [nombre, c.name, recurso])
}

deny contains msg if {
	some c in contenedores
	some recurso in ["cpu", "memory"]
	object.get(c, ["resources", "requests", recurso], null) == null
	msg := sprintf("[K8S-05] %s: el contenedor '%s' no define reserva (requests) de %s", [nombre, c.name, recurso])
}

# K8S-06 · Imagen inmutable y trazable: etiqueta explícita distinta de "latest"
sin_etiqueta(imagen) if {
	not contains(imagen, "@")
	partes := split(imagen, "/")
	not contains(partes[count(partes) - 1], ":")
}

deny contains msg if {
	some c in contenedores
	sin_etiqueta(c.image)
	msg := sprintf("[K8S-06] %s: la imagen '%s' no tiene etiqueta de versión", [nombre, c.image])
}

deny contains msg if {
	some c in contenedores
	endswith(c.image, ":latest")
	msg := sprintf("[K8S-06] %s: la imagen '%s' usa 'latest' (no se sabe qué versión corre)", [nombre, c.image])
}

# K8S-07 · Sondas de salud (Kubernetes solo envía tráfico a réplicas sanas y reinicia las colgadas)
deny contains msg if {
	input.kind in {"Deployment", "StatefulSet"}
	some c in pod_spec.containers
	some sonda in ["readinessProbe", "livenessProbe"]
	not c[sonda]
	msg := sprintf("[K8S-07] %s: el contenedor '%s' no define %s", [nombre, c.name, sonda])
}

# K8S-08 · Sistema de archivos de solo lectura, salvo excepción documentada
deny contains msg if {
	some c in contenedores
	not sc(c).readOnlyRootFilesystem == true
	not anotaciones["cumplimiento/excepcion-readonly"]
	msg := sprintf("[K8S-08] %s: el contenedor '%s' debe usar readOnlyRootFilesystem: true o documentar la excepción", [nombre, c.name])
}

warn contains msg if {
	motivo := anotaciones["cumplimiento/excepcion-readonly"]
	msg := sprintf("[K8S-08] %s: excepción aprobada a solo lectura: %s", [nombre, motivo])
}

# K8S-09 · Aislamiento del nodo
deny contains msg if {
	some campo in ["hostNetwork", "hostPID", "hostIPC"]
	pod_spec[campo] == true
	msg := sprintf("[K8S-09] %s: usa %s (comparte recursos del nodo)", [nombre, campo])
}

deny contains msg if {
	some v in object.get(pod_spec, "volumes", [])
	v.hostPath
	msg := sprintf("[K8S-09] %s: monta el directorio del nodo '%s' (hostPath)", [nombre, v.hostPath.path])
}

# K8S-10 · Los secretos no se versionan en los manifiestos de producción
deny contains msg if {
	input.kind == "Secret"
	msg := sprintf("[K8S-10] Secret/%s: los secretos de producción no deben estar en el repositorio", [input.metadata.name])
}

# K8S-11 · En producción no se exponen puertos de los nodos
deny contains msg if {
	input.kind == "Service"
	input.spec.type == "NodePort"
	msg := sprintf("[K8S-11] Service/%s: NodePort expone un puerto en cada nodo; usar LoadBalancer o Ingress", [input.metadata.name])
}

# K8S-12 · Perfil seccomp por defecto
warn contains msg if {
	es_carga
	not pod_sc.seccompProfile.type
	msg := sprintf("[K8S-12] %s: se recomienda seccompProfile RuntimeDefault", [nombre])
}

# K8S-13 · Token de la cuenta de servicio solo si se necesita
warn contains msg if {
	es_carga
	not pod_spec.automountServiceAccountToken == false
	msg := sprintf("[K8S-13] %s: se recomienda automountServiceAccountToken: false", [nombre])
}

# K8S-14 · Alta disponibilidad
warn contains msg if {
	input.kind == "Deployment"
	object.get(input.spec, "replicas", 1) < 2
	msg := sprintf("[K8S-14] %s: con menos de 2 réplicas una falla deja el servicio sin atención", [nombre])
}
