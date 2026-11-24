package dockerfile

base := [
	{"Cmd": "from", "Value": ["eclipse-temurin:17-jdk", "AS", "build"], "Stage": 0},
	{"Cmd": "from", "Value": ["eclipse-temurin:17-jre-alpine"], "Stage": 1},
	{"Cmd": "copy", "Value": ["--from=build", "/app.jar", "/app.jar"], "Stage": 1},
	{"Cmd": "user", "Value": ["1001:1001"], "Stage": 1},
	{"Cmd": "healthcheck", "Value": ["CMD", "true"], "Stage": 1},
]

test_dockerfile_correcto if {
	count(deny) == 0 with input as [base]
}

test_rechaza_sin_user if {
	d := [i | some i in base; i.Cmd != "user"]
	some msg in deny with input as [d]
	startswith(msg, "[DOCKER-01]")
}

test_rechaza_user_root if {
	d := array.concat(base, [{"Cmd": "user", "Value": ["root"], "Stage": 1}])
	some msg in deny with input as [d]
	startswith(msg, "[DOCKER-01]")
}

test_rechaza_latest if {
	d := array.concat(base, [{"Cmd": "from", "Value": ["alpine:latest"], "Stage": 1}])
	some msg in deny with input as [d]
	startswith(msg, "[DOCKER-02]")
}

test_permite_heredar_de_etapa_previa if {
	d := array.concat(base, [{"Cmd": "from", "Value": ["build", "AS", "test"], "Stage": 0}])
	count(deny) == 0 with input as [d]
}

test_rechaza_sin_healthcheck if {
	d := [i | some i in base; i.Cmd != "healthcheck"]
	some msg in deny with input as [d]
	startswith(msg, "[DOCKER-03]")
}

test_rechaza_add if {
	d := array.concat(base, [{"Cmd": "add", "Value": ["https://x/y.tar", "/"], "Stage": 1}])
	some msg in deny with input as [d]
	startswith(msg, "[DOCKER-04]")
}

test_rechaza_secretos_en_env if {
	d := array.concat(base, [{"Cmd": "env", "Value": ["DB_PASSWORD", "x"], "Stage": 1}])
	some msg in deny with input as [d]
	startswith(msg, "[DOCKER-05]")
}
