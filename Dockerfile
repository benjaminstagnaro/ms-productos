# syntax=docker/dockerfile:1

# ================================================================
# Etapa 1: dependencias (descarga y cacheo de dependencias)
# Solo se invalida cuando cambia el pom.xml, así los builds siguientes son rápidos.
# ================================================================
FROM eclipse-temurin:17-jdk AS dependencies
WORKDIR /app
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
# sed elimina posibles fin de línea de Windows (CRLF) que romperían el script
RUN sed -i 's/\r$//' mvnw && chmod +x mvnw && ./mvnw dependency:go-offline -B -ntp

# ================================================================
# Etapa 2: tests (si una prueba falla, la imagen NO se construye)
# Hereda de "dependencies", por lo que reutiliza el caché de ~/.m2
# ================================================================
FROM dependencies AS test
COPY src ./src
RUN ./mvnw test -B -ntp

# ================================================================
# Etapa 3: compilación (depende de que "test" haya pasado)
# ================================================================
FROM test AS compile
RUN ./mvnw package -DskipTests -B -ntp

# ================================================================
# Etapa 4: producción
# Imagen mínima: solo JRE (sin JDK, Maven ni código fuente) sobre Alpine.
# ================================================================
FROM eclipse-temurin:17-jre-alpine AS prod

# Datos que el pipeline graba en la imagen para trazabilidad (commit -> imagen -> contenedor)
ARG APP_VERSION=dev
ARG GIT_COMMIT=local
ARG BUILD_DATE=unknown
ARG SOURCE_URL=""

LABEL org.opencontainers.image.title="ms-productos" \
      org.opencontainers.image.description="Microservicio de gestión de productos" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="${SOURCE_URL}"

# Seguridad: la aplicación se ejecuta con un usuario sin privilegios, nunca como root.
# UID numérico para que Kubernetes pueda verificar runAsNonRoot.
RUN addgroup -S -g 1001 spring && adduser -S -u 1001 -G spring spring

WORKDIR /app
COPY --from=compile --chown=spring:spring /app/target/*.jar app.jar

# La JVM respeta los límites de memoria del contenedor (definidos en docker-compose / k8s)
ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

USER 1001:1001
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
