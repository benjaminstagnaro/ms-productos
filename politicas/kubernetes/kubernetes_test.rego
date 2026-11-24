# Pruebas unitarias de las políticas (conftest verify): demuestran que cada regla
# detecta el problema y que un manifiesto correcto pasa sin observaciones.
package kubernetes

contenedor_ok := {
	"name": "app",
	"image": "ghcr.io/org/app:1.0.0-abc1234",
	"resources": {"requests": {"cpu": "100m", "memory": "128Mi"}, "limits": {"cpu": "1", "memory": "256Mi"}},
	"readinessProbe": {"httpGet": {"path": "/ready", "port": 8081}},
	"livenessProbe": {"httpGet": {"path": "/live", "port": 8081}},
	"securityContext": {
		"allowPrivilegeEscalation": false,
		"readOnlyRootFilesystem": true,
		"capabilities": {"drop": ["ALL"]},
	},
}

deployment(c) := {
	"kind": "Deployment",
	"metadata": {"name": "app"},
	"spec": {
		"replicas": 2,
		"template": {
			"metadata": {"labels": {"app": "app"}},
			"spec": {
				"automountServiceAccountToken": false,
				"securityContext": {"runAsNonRoot": true, "seccompProfile": {"type": "RuntimeDefault"}},
				"containers": [c],
			},
		},
	},
}

test_deployment_correcto_no_tiene_observaciones if {
	count(deny) == 0 with input as deployment(contenedor_ok)
	count(warn) == 0 with input as deployment(contenedor_ok)
}

test_rechaza_contenedor_privilegiado if {
	c := json.patch(contenedor_ok, [{"op": "add", "path": "/securityContext/privileged", "value": true}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-01]")
}

test_rechaza_escalamiento_de_privilegios if {
	c := json.patch(contenedor_ok, [{"op": "remove", "path": "/securityContext/allowPrivilegeEscalation"}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-02]")
}

test_rechaza_root if {
	c := json.patch(contenedor_ok, [{"op": "add", "path": "/securityContext/runAsUser", "value": 0}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-03]")
}

test_rechaza_capacidades if {
	c := json.patch(contenedor_ok, [{"op": "replace", "path": "/securityContext/capabilities/drop", "value": ["NET_RAW"]}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-04]")
}

test_rechaza_sin_limites if {
	c := json.patch(contenedor_ok, [{"op": "remove", "path": "/resources/limits"}])
	some msg in deny with input as deployment(c)
	contains(msg, "[K8S-05]")
}

test_rechaza_imagen_latest if {
	c := json.patch(contenedor_ok, [{"op": "replace", "path": "/image", "value": "ghcr.io/org/app:latest"}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-06]")
}

test_rechaza_imagen_sin_etiqueta if {
	c := json.patch(contenedor_ok, [{"op": "replace", "path": "/image", "value": "registry:5000/app"}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-06]")
}

test_rechaza_sin_sondas if {
	c := json.patch(contenedor_ok, [{"op": "remove", "path": "/readinessProbe"}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-07]")
}

test_rechaza_escritura_sin_excepcion if {
	c := json.patch(contenedor_ok, [{"op": "remove", "path": "/securityContext/readOnlyRootFilesystem"}])
	some msg in deny with input as deployment(c)
	startswith(msg, "[K8S-08]")
}

test_acepta_escritura_con_excepcion_documentada if {
	c := json.patch(contenedor_ok, [{"op": "remove", "path": "/securityContext/readOnlyRootFilesystem"}])
	d := json.patch(deployment(c), [{"op": "add", "path": "/spec/template/metadata/annotations", "value": {"cumplimiento/excepcion-readonly": "motivo"}}])
	count(deny) == 0 with input as d
	some msg in warn with input as d
	startswith(msg, "[K8S-08]")
}

test_rechaza_host_network if {
	d := json.patch(deployment(contenedor_ok), [{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}])
	some msg in deny with input as d
	startswith(msg, "[K8S-09]")
}

test_rechaza_secret_versionado if {
	some msg in deny with input as {"kind": "Secret", "metadata": {"name": "db"}, "stringData": {"pass": "x"}}
	startswith(msg, "[K8S-10]")
}

test_rechaza_nodeport if {
	some msg in deny with input as {"kind": "Service", "metadata": {"name": "app"}, "spec": {"type": "NodePort"}}
	startswith(msg, "[K8S-11]")
}

test_advierte_una_sola_replica if {
	d := json.patch(deployment(contenedor_ok), [{"op": "replace", "path": "/spec/replicas", "value": 1}])
	some msg in warn with input as d
	startswith(msg, "[K8S-14]")
}
