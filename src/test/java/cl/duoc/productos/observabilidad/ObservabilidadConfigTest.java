package cl.duoc.productos.observabilidad;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

class ObservabilidadConfigTest {

    private final ObservabilidadConfig config = new ObservabilidadConfig();

    @Test
    void agregaEtiquetasDeServicioVersionYCommitCorto() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        registry.config().meterFilter(config.etiquetasComunes("ms-productos", "1.1.0", "a1b2c3d4e5f6"));

        Counter contador = registry.counter("prueba");

        assertThat(contador.getId().getTag("application")).isEqualTo("ms-productos");
        assertThat(contador.getId().getTag("version")).isEqualTo("1.1.0");
        assertThat(contador.getId().getTag("commit")).isEqualTo("a1b2c3d");
    }

    @Test
    void conservaCommitsCortos() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        registry.config().meterFilter(config.etiquetasComunes("ms-productos", "dev", "local"));

        assertThat(registry.counter("prueba").getId().getTag("commit")).isEqualTo("local");
    }

    @Test
    void activaHistogramaSoloParaPeticionesHttp() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        registry.config().meterFilter(config.histogramaLatenciaHttp());

        Timer http = registry.timer("http.server.requests");
        http.record(Duration.ofMillis(50));
        Timer otro = registry.timer("otro.timer");
        otro.record(Duration.ofMillis(50));

        assertThat(http.takeSnapshot().histogramCounts()).isNotEmpty();
        assertThat(otro.takeSnapshot().histogramCounts()).isEmpty();
    }
}
