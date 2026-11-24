# Políticas para el Dockerfile (CIS Docker Benchmark §4 e ISO/IEC 27001:2022 A.8.9).
# Complementan a hadolint: hadolint revisa buenas prácticas generales y estas reglas
# exigen las decisiones de seguridad propias del proyecto.
package dockerfile

instrucciones := input[0] if is_array(input[0])

instrucciones := input if not is_array(input[0])

etapa_final := max({i.Stage | some i in instrucciones})

finales := [i | some i in instrucciones; i.Stage == etapa_final]

# DOCKER-01 (CIS 4.1) · La imagen final corre con un usuario sin privilegios
deny contains "[DOCKER-01] La etapa final no define USER: el contenedor correría como root" if {
	count([i | some i in finales; i.Cmd == "user"]) == 0
}

deny contains msg if {
	usuarios := [i | some i in finales; i.Cmd == "user"]
	ultimo := usuarios[count(usuarios) - 1]
	usuario := split(ultimo.Value[0], ":")[0]
	usuario in {"root", "0"}
	msg := sprintf("[DOCKER-01] La etapa final corre como '%s'", [usuario])
}

# DOCKER-02 · Imágenes base con versión explícita (builds reproducibles)
deny contains msg if {
	some i in instrucciones
	i.Cmd == "from"
	imagen := i.Value[0]
	not contains(imagen, ":")
	not contains(imagen, "@")
	not es_etapa_previa(imagen)
	msg := sprintf("[DOCKER-02] FROM %s no fija versión", [imagen])
}

deny contains msg if {
	some i in instrucciones
	i.Cmd == "from"
	endswith(i.Value[0], ":latest")
	msg := sprintf("[DOCKER-02] FROM %s usa 'latest'", [i.Value[0]])
}

# Una etapa anterior del mismo Dockerfile (FROM dependencies AS test)
es_etapa_previa(nombre) if {
	some i in instrucciones
	i.Cmd == "from"
	count(i.Value) == 3
	lower(i.Value[2]) == lower(nombre)
}

# DOCKER-03 (CIS 4.6) · HEALTHCHECK para que el orquestador detecte réplicas colgadas
deny contains "[DOCKER-03] La imagen final no define HEALTHCHECK" if {
	count([i | some i in finales; i.Cmd == "healthcheck"]) == 0
}

# DOCKER-04 (CIS 4.9) · COPY en lugar de ADD (ADD descarga URLs y descomprime archivos)
deny contains msg if {
	some i in instrucciones
	i.Cmd == "add"
	msg := sprintf("[DOCKER-04] Usar COPY en lugar de ADD: ADD %s", [concat(" ", i.Value)])
}

# DOCKER-05 (CIS 4.10) · Sin secretos en ENV/ARG (quedan grabados en las capas de la imagen)
patron_secreto := `(?i)(password|passwd|secret|token|api_?key|private_?key)`

deny contains msg if {
	some i in instrucciones
	i.Cmd in {"env", "arg"}
	some v in i.Value
	regex.match(patron_secreto, split(v, "=")[0])
	msg := sprintf("[DOCKER-05] %s %s parece contener un secreto", [upper(i.Cmd), split(v, "=")[0]])
}
