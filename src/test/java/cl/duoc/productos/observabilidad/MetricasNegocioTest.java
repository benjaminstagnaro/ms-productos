package cl.duoc.productos.observabilidad;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class MetricasNegocioTest {

    private SimpleMeterRegistry registry;
    private MetricasNegocio metricas;

    @BeforeEach
    void setUp() {
        registry = new SimpleMeterRegistry();
        metricas = new MetricasNegocio(registry);
    }

    @Test
    void cuentaProductosCreadosYEliminados() {
        metricas.productoCreado();
        metricas.productoCreado();
        metricas.productoEliminado();

        assertThat(registry.get("productos.creados").counter().count()).isEqualTo(2);
        assertThat(registry.get("productos.eliminados").counter().count()).isEqualTo(1);
    }

    @Test
    void separaIngresosYEgresosDeStock() {
        metricas.movimientoStock(5);
        metricas.movimientoStock(-3);
        metricas.movimientoStock(0);

        assertThat(registry.get("productos.stock.movimientos").tag("tipo", "ingreso").counter().count()).isEqualTo(5);
        assertThat(registry.get("productos.stock.movimientos").tag("tipo", "egreso").counter().count()).isEqualTo(3);
    }

    @Test
    void cuentaRechazosDeStock() {
        metricas.stockRechazado();

        assertThat(registry.get("productos.stock.rechazos").counter().count()).isEqualTo(1);
    }

    @Test
    void cuentaErroresPorTipoYCodigo() {
        metricas.errorRegistrado("validacion", 400);
        metricas.errorRegistrado("validacion", 400);
        metricas.errorRegistrado("interno", 500);

        assertThat(registry.get("productos.errores").tags("tipo", "validacion", "status", "400").counter().count())
                .isEqualTo(2);
        assertThat(registry.get("productos.errores").tags("tipo", "interno", "status", "500").counter().count())
                .isEqualTo(1);
    }
}
