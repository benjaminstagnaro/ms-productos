package cl.duoc.productos.observabilidad;

import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.Tags;
import io.micrometer.core.instrument.config.MeterFilter;
import io.micrometer.core.instrument.distribution.DistributionStatisticConfig;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * Configuración de las métricas que se exportan a Prometheus.
 * Spring Boot aplica automáticamente todos los beans MeterFilter al registro.
 */
@Configuration
public class ObservabilidadConfig {

    /**
     * Etiquetas comunes en todas las métricas: permiten filtrar en Grafana por servicio
     * y saber qué versión/commit generó cada dato (trazabilidad entre despliegue y métricas).
     */
    @Bean
    MeterFilter etiquetasComunes(@Value("${spring.application.name}") String aplicacion,
                                 @Value("${app.version}") String version,
                                 @Value("${app.commit}") String commit) {
        String commitCorto = commit.length() > 7 ? commit.substring(0, 7) : commit;
        return MeterFilter.commonTags(Tags.of(
                "application", aplicacion,
                "version", version,
                "commit", commitCorto));
    }

    /**
     * Histograma de latencia de las peticiones HTTP: permite calcular percentiles (p95, p99)
     * en Prometheus y medir el objetivo de nivel de servicio (SLO) de 300 ms.
     */
    @Bean
    MeterFilter histogramaLatenciaHttp() {
        return new MeterFilter() {
            @Override
            public DistributionStatisticConfig configure(Meter.Id id, DistributionStatisticConfig config) {
                if (id.getName().startsWith("http.server.requests")) {
                    return DistributionStatisticConfig.builder()
                            .percentilesHistogram(true)
                            .serviceLevelObjectives(
                                    Duration.ofMillis(100).toNanos(),
                                    Duration.ofMillis(300).toNanos(),
                                    Duration.ofSeconds(1).toNanos())
                            .build()
                            .merge(config);
                }
                return config;
            }
        };
    }
}
