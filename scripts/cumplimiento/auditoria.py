#!/usr/bin/env python3
"""
Auditoría automatizada de cumplimiento de ms-productos.

Ejecuta todos los controles de seguridad y calidad que exige el proyecto, los mapea a
normas del sector (ISO/IEC 27001:2022, CIS Benchmarks, OWASP Top 10 2021, NIST SSDF)
y genera un reporte (JSON + Markdown) que queda como evidencia de auditoría en cada
ejecución del pipeline.

Severidades:
  CRITICA / ALTA  -> si fallan, la auditoría termina con error y el pipeline se DETIENE
  MEDIA           -> queda como advertencia en el reporte

Uso:
  python3 scripts/cumplimiento/auditoria.py --imagen ghcr.io/usuario/ms-productos:1.1.0-abc1234 \
      [--simulacion-k8s politica-kubernetes] [--repo usuario/ms-productos] [--salida reporte-cumplimiento]

Herramientas necesarias en el PATH: gitleaks, hadolint, conftest, kubectl (para kustomize).
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]

# ---------------------------------------------------------------------------
# Catálogo de controles: id -> (descripción, severidad, normas)
# ---------------------------------------------------------------------------
CONTROLES = {
    "SEC-01": ("Sin secretos en los archivos del repositorio", "CRITICA",
               "ISO 27001 A.8.4 / A.5.17 · OWASP A07:2021 · NIST SSDF PS.1"),
    "SEC-02": ("Sin secretos en el historial de commits", "CRITICA",
               "ISO 27001 A.8.4 / A.5.17 · NIST SSDF PS.1"),
    "DOC-00": ("Dockerfile sin malas prácticas (hadolint)", "ALTA",
               "CIS Docker Benchmark §4 · ISO 27001 A.8.9"),
    "DOCKER-01": ("Imagen final con usuario sin privilegios", "CRITICA", "CIS Docker 4.1 · ISO 27001 A.8.2"),
    "DOCKER-02": ("Imágenes base con versión fija (no latest)", "ALTA", "ISO 27001 A.8.9 / A.8.32"),
    "DOCKER-03": ("HEALTHCHECK definido", "MEDIA", "CIS Docker 4.6"),
    "DOCKER-04": ("COPY en lugar de ADD", "MEDIA", "CIS Docker 4.9"),
    "DOCKER-05": ("Sin secretos en ENV/ARG", "CRITICA", "CIS Docker 4.10 · ISO 27001 A.5.17"),
    "K8S-01": ("Sin contenedores privilegiados", "CRITICA", "PSS Restricted · CIS Kubernetes §5.2 · ISO 27001 A.8.2"),
    "K8S-02": ("Sin escalamiento de privilegios", "CRITICA", "PSS Restricted · CIS Kubernetes §5.2"),
    "K8S-03": ("Contenedores sin root", "CRITICA", "PSS Restricted · CIS Kubernetes §5.2"),
    "K8S-04": ("Capacidades de Linux eliminadas", "ALTA", "PSS Restricted · CIS Kubernetes §5.2"),
    "K8S-05": ("Requests y límites de CPU/memoria", "ALTA", "ISO 27001 A.8.6 (gestión de capacidad)"),
    "K8S-06": ("Imagen inmutable y trazable (sin latest)", "ALTA", "ISO 27001 A.8.32 · NIST SSDF PS.3"),
    "K8S-07": ("Sondas readiness y liveness", "ALTA", "ISO 27001 A.8.14 (redundancia) / A.8.16"),
    "K8S-08": ("Sistema de archivos de solo lectura o excepción documentada", "ALTA", "PSS · CIS Kubernetes §5.2"),
    "K8S-09": ("Aislamiento del nodo (sin hostNetwork/hostPID/hostPath)", "CRITICA", "PSS Baseline · CIS Kubernetes §5.2"),
    "K8S-10": ("Secretos de producción fuera de Git", "CRITICA", "ISO 27001 A.5.17 · OWASP A05:2021"),
    "K8S-11": ("Sin NodePort en producción", "ALTA", "ISO 27001 A.8.20 (seguridad de redes)"),
    "POL-00": ("Las políticas tienen pruebas unitarias y pasan", "MEDIA", "ISO 27001 A.8.29 (pruebas de seguridad)"),
    "REPO-01": ("Permisos mínimos del GITHUB_TOKEN en el pipeline", "ALTA", "ISO 27001 A.8.2 / A.5.15 · OWASP A01:2021"),
    "REPO-02": ("Acciones de terceros fijadas por commit SHA", "ALTA", "OWASP A08:2021 · NIST SSDF PO.3 · SLSA"),
    "REPO-03": ("Archivo .env fuera del repositorio", "CRITICA", "ISO 27001 A.5.17"),
    "REPO-04": ("Dependabot vigila Maven, Docker y Actions", "ALTA", "ISO 27001 A.8.8 · OWASP A06:2021"),
    "REPO-05": ("Política de seguridad publicada (SECURITY.md)", "MEDIA", "ISO 27001 A.5.24 / A.6.8"),
    "REPO-06": ("Responsables de revisión definidos (CODEOWNERS)", "MEDIA", "ISO 27001 A.8.4 / A.8.32"),
    "REPO-07": ("Rama main protegida (PR + checks obligatorios)", "ALTA", "ISO 27001 A.8.32 / A.8.4 · NIST SSDF PS.1"),
    "REPO-08": ("Cobertura mínima de pruebas >= 80 % configurada", "CRITICA", "ISO 27001 A.8.29 · NIST SSDF PW.8"),
    "REPO-09": ("Compuertas de seguridad activas en el pipeline", "CRITICA", "ISO 27001 A.8.8 / A.8.25 · NIST SSDF RV.1"),
    "REPO-10": ("Actuator y métricas solo en puerto interno", "ALTA", "OWASP A05:2021 · ISO 27001 A.8.9"),
    "OBS-01": ("Logs estructurados y métricas habilitadas", "MEDIA", "ISO 27001 A.8.15 / A.8.16 · OWASP A09:2021"),
}
BLOQUEANTES = {"CRITICA", "ALTA"}

resultados = {}   # id -> {"resultado": aprobado|fallido|advertencia, "detalle": [..]}


def registrar(cid, ok, detalle=None, advertencia=False):
    r = resultados.setdefault(cid, {"resultado": "aprobado", "detalle": []})
    if detalle:
        r["detalle"].extend(detalle if isinstance(detalle, list) else [detalle])
    if not ok:
        r["resultado"] = "fallido"
    elif advertencia and r["resultado"] == "aprobado":
        r["resultado"] = "advertencia"


def ejecutar(cmd, **kw):
    return subprocess.run(cmd, cwd=RAIZ, capture_output=True, text=True, **kw)


def leer(ruta):
    p = RAIZ / ruta
    return p.read_text(encoding="utf-8") if p.exists() else ""


# ---------------------------------------------------------------------------
# 1. Secretos (gitleaks)
# ---------------------------------------------------------------------------
def controles_secretos():
    for cid, modo in (("SEC-01", "dir"), ("SEC-02", "git")):
        reporte = f"/tmp/gitleaks-{modo}.json"
        r = ejecutar(["gitleaks", modo, ".", "--redact", "--no-banner", "--exit-code", "0",
                      "--report-format", "json", "--report-path", reporte])
        if r.returncode != 0:
            registrar(cid, False, f"gitleaks no pudo ejecutarse: {r.stderr.strip()[-300:]}")
            continue
        hallazgos = json.loads(Path(reporte).read_text() or "[]")
        registrar(cid, not hallazgos, [f"{h['RuleID']} en {h['File']}:{h.get('StartLine')}" for h in hallazgos])


# ---------------------------------------------------------------------------
# 2. Dockerfile (hadolint + políticas propias)
# ---------------------------------------------------------------------------
def controles_dockerfile():
    r = ejecutar(["hadolint", "--no-color", "--failure-threshold", "warning", "Dockerfile"])
    registrar("DOC-00", r.returncode == 0, [l for l in r.stdout.splitlines() if l.strip()])
    conftest("politicas/dockerfile", "Dockerfile", ["--parser", "dockerfile"], prefijo="DOCKER-")


# ---------------------------------------------------------------------------
# 3. Kubernetes (políticas Rego sobre los manifiestos REALES de producción)
# ---------------------------------------------------------------------------
def controles_kubernetes(imagen, simulacion):
    r = ejecutar(["bash", "scripts/k8s/renderizar.sh", imagen, simulacion])
    if r.returncode != 0:
        registrar("K8S-06", False, f"No se pudieron generar los manifiestos: {r.stderr.strip()[-300:]}")
        return
    render = Path("/tmp/auditoria-k8s.yaml")
    render.write_text(r.stdout)
    conftest("politicas/kubernetes", str(render), [], prefijo="K8S-")
    for carpeta in ("politicas/kubernetes", "politicas/dockerfile"):
        v = ejecutar(["conftest", "verify", "--no-color", "--policy", carpeta])
        registrar("POL-00", v.returncode == 0, [l for l in v.stdout.splitlines() if "FAIL" in l or "tests," in l])


def conftest(politica, archivo, extra, prefijo):
    r = ejecutar(["conftest", "test", "--no-color", "--all-namespaces", "--output", "json",
                  "--policy", politica, *extra, archivo])
    try:
        salida = json.loads(r.stdout)
    except json.JSONDecodeError:
        for cid in CONTROLES:
            if cid.startswith(prefijo):
                registrar(cid, False, f"conftest falló: {r.stderr.strip()[-300:]}")
        return
    for cid in CONTROLES:
        if cid.startswith(prefijo):
            registrar(cid, True)
    for doc in salida:
        for f in doc.get("failures") or []:
            m = re.match(r"\[([A-Z0-9-]+)\]", f["msg"])
            registrar(m.group(1) if m else prefijo + "??", False, f["msg"])
        for w in doc.get("warnings") or []:
            m = re.match(r"\[([A-Z0-9-]+)\]", w["msg"])
            if m and m.group(1) in CONTROLES:
                registrar(m.group(1), True, w["msg"], advertencia=True)


# ---------------------------------------------------------------------------
# 4. Configuración del repositorio y del pipeline
# ---------------------------------------------------------------------------
def controles_repositorio(repo):
    workflows = {p.name: p.read_text(encoding="utf-8") for p in (RAIZ / ".github/workflows").glob("*.y*ml")}

    # REPO-01: permisos globales mínimos
    sin_permisos = [n for n, t in workflows.items()
                    if not re.search(r"^permissions:\s*\n\s+contents:\s*read\s*$", t, re.M)
                    and not re.search(r"^permissions:\s*(read-all|\{\})", t, re.M)]
    registrar("REPO-01", not sin_permisos, [f"{n}: falta 'permissions: contents: read' global" for n in sin_permisos])

    # REPO-02: acciones de terceros fijadas por SHA
    no_fijadas = []
    for n, t in workflows.items():
        for uso in re.findall(r"uses:\s*([^\s#]+)", t):
            if uso.startswith(("./", "actions/", "github/")):
                continue
            if not re.search(r"@[0-9a-f]{40}$", uso):
                no_fijadas.append(f"{n}: {uso}")
    registrar("REPO-02", not no_fijadas, no_fijadas)

    # REPO-03: .env nunca versionado
    rastreados = ejecutar(["git", "ls-files", ".env", "*.env", "**/.env"]).stdout.split()
    ignorado = ".env" in leer(".gitignore").split()
    registrar("REPO-03", not rastreados and ignorado,
              [f"archivo versionado: {f}" for f in rastreados] + ([] if ignorado else [".env no está en .gitignore"]))

    # REPO-04: Dependabot
    dep = leer(".github/dependabot.yml")
    faltan = [e for e in ("maven", "docker", "github-actions") if f'"{e}"' not in dep and f"'{e}'" not in dep
              and f": {e}\n" not in dep]
    registrar("REPO-04", not faltan, [f"Dependabot no vigila: {e}" for e in faltan])

    # REPO-05 / REPO-06
    registrar("REPO-05", (RAIZ / "SECURITY.md").exists(), None if (RAIZ / "SECURITY.md").exists() else "falta SECURITY.md")
    co = (RAIZ / ".github/CODEOWNERS").exists()
    registrar("REPO-06", co, None if co else "falta .github/CODEOWNERS")

    # REPO-07: protección de la rama main (rulesets o protección clásica), vía API de GitHub
    proteccion_rama(repo)

    # REPO-08: umbral de cobertura no se puede bajar sin que la auditoría lo detecte
    m = re.search(r"<jacoco\.cobertura\.minima>([0-9.]+)</jacoco\.cobertura\.minima>", leer("pom.xml"))
    umbral = float(m.group(1)) if m else 0
    registrar("REPO-08", umbral >= 0.80, f"umbral configurado: {umbral:.0%}")

    # REPO-09: las compuertas de seguridad siguen en el pipeline
    ci = workflows.get("ci-cd.yml", "")
    compuertas = {
        "Snyk bloquea severidad alta (dependencias)": "--severity-threshold=high",
        "Snyk bloquea severidad crítica (imagen)": "--severity-threshold=critical",
        "SonarCloud espera el Quality Gate": "-Dsonar.qualitygate.wait=true",
        "Pruebas + cobertura (mvn verify)": "clean verify",
        "Despliegue depende de la auditoría": "auditoria-cumplimiento",
    }
    faltan = [d for d, patron in compuertas.items() if patron not in ci]
    registrar("REPO-09", not faltan, [f"falta: {d}" for d in faltan] or [f"{len(compuertas)} compuertas activas"])

    # REPO-10: Actuator fuera del puerto público
    props = leer("src/main/resources/application.properties")
    expuesto = re.search(r"management\.endpoints\.web\.exposure\.include=.*\*", props)
    puerto = "management.server.port=" in props
    registrar("REPO-10", puerto and not expuesto,
              ([] if puerto else ["Actuator comparte el puerto de la API"]) + (["exposición con '*'"] if expuesto else []))

    # OBS-01: observabilidad mínima
    obs = "logging.structured.format.console" in props and "prometheus" in props
    registrar("OBS-01", obs, None if obs else "faltan logs estructurados o el endpoint de Prometheus", advertencia=not obs)


def proteccion_rama(repo):
    if not repo:
        registrar("REPO-07", True, "no se indicó el repositorio (--repo): control omitido", advertencia=True)
        return
    token = os.environ.get("GITHUB_TOKEN", "")

    def api(ruta):
        req = urllib.request.Request(f"https://api.github.com/repos/{repo}/{ruta}",
                                     headers={"Accept": "application/vnd.github+json",
                                              **({"Authorization": f"Bearer {token}"} if token else {})})
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.load(resp)

    try:
        reglas = {r["type"] for r in api("rules/branches/main")}
        rama = api("branches/main")
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        registrar("REPO-07", False, f"no se pudo consultar la API de GitHub: {e}")
        return
    clasica = rama.get("protected") and rama.get("protection", {}).get("required_status_checks", {}).get("contexts")
    ruleset = {"pull_request", "required_status_checks"} <= reglas
    detalle = [f"reglas activas en main: {', '.join(sorted(reglas)) or 'ninguna'}"]
    if not (ruleset or clasica):
        detalle.append("main debe exigir Pull Request y checks obligatorios (ver README, sección de cumplimiento)")
    registrar("REPO-07", bool(ruleset or clasica), detalle)


# ---------------------------------------------------------------------------
# Reporte
# ---------------------------------------------------------------------------
def generar_reporte(salida, imagen):
    filas = []
    for cid, (desc, sev, norma) in CONTROLES.items():
        r = resultados.get(cid, {"resultado": "no_evaluado", "detalle": []})
        filas.append({"id": cid, "control": desc, "severidad": sev, "normas": norma, **r})
    conteo = {k: sum(1 for f in filas if f["resultado"] == k) for k in ("aprobado", "fallido", "advertencia")}
    bloqueantes = [f for f in filas if f["resultado"] == "fallido" and f["severidad"] in BLOQUEANTES]
    advertencias_media = [f for f in filas if f["resultado"] == "fallido" and f["severidad"] not in BLOQUEANTES]
    datos = {
        "fecha_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "commit": os.environ.get("GITHUB_SHA", "local"),
        "ejecucion": os.environ.get("GITHUB_RUN_ID", "local"),
        "imagen": imagen,
        "resumen": conteo,
        "aprobada": not bloqueantes,
        "controles": filas,
    }
    Path(f"{salida}.json").write_text(json.dumps(datos, indent=2, ensure_ascii=False))

    icono = {"aprobado": "✅", "fallido": "❌", "advertencia": "⚠️", "no_evaluado": "➖"}
    md = ["## 🛡️ Auditoría de cumplimiento", "",
          f"**Resultado:** {'APROBADA' if not bloqueantes else 'RECHAZADA — el pipeline se detiene'} · "
          f"{conteo['aprobado']} aprobados · {conteo['fallido']} fallidos · {conteo['advertencia']} con advertencia", "",
          "| Control | Descripción | Severidad | Normas | Resultado | Detalle |", "|---|---|---|---|---|---|"]
    for f in filas:
        det = "<br>".join(d.replace("|", "\\|") for d in f["detalle"][:6])
        md.append(f"| {f['id']} | {f['control']} | {f['severidad']} | {f['normas']} | {icono[f['resultado']]} | {det} |")
    Path(f"{salida}.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as s:
            s.write("\n".join(md) + "\n")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as o:
            o.write(f"aprobados={conteo['aprobado']}\nfallidos={conteo['fallido']}\n"
                    f"advertencias={conteo['advertencia']}\n")

    print("\n".join(md))
    for f in bloqueantes:
        print(f"::error title=Cumplimiento {f['id']} ({f['severidad']})::{f['control']}: {'; '.join(f['detalle'][:3])}")
    for f in advertencias_media:
        print(f"::warning title=Cumplimiento {f['id']}::{f['control']}: {'; '.join(f['detalle'][:3])}")
    return not bloqueantes


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--imagen", required=True)
    p.add_argument("--simulacion-k8s", default="ninguna")
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    p.add_argument("--salida", default="reporte-cumplimiento")
    a = p.parse_args()

    controles_secretos()
    controles_dockerfile()
    controles_kubernetes(a.imagen, a.simulacion_k8s)
    controles_repositorio(a.repo)
    raise SystemExit(0 if generar_reporte(a.salida, a.imagen) else 1)


if __name__ == "__main__":
    main()
