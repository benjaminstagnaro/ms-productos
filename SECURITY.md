# Política de seguridad

## Versiones con soporte

Solo la versión desplegada desde la rama `main` recibe correcciones de seguridad.

## Cómo reportar una vulnerabilidad

No abras un *issue* público. Usa **Security → Report a vulnerability** en este repositorio
(reporte privado de GitHub) indicando:

- componente afectado (endpoint, dependencia, imagen o manifiesto),
- pasos para reproducirlo e impacto estimado.

Se responde dentro de 5 días hábiles. Las vulnerabilidades confirmadas se corrigen en una rama,
pasan por el pipeline completo (pruebas, Snyk, SonarCloud y auditoría de cumplimiento) y se
documentan en el README.

## Controles automáticos

Cada cambio pasa por los controles descritos en la sección de cumplimiento del [README](README.md):
detección de secretos, análisis de dependencias e imagen, análisis estático, políticas de
Kubernetes y del Dockerfile, y verificación post-despliegue con rollback automático.
