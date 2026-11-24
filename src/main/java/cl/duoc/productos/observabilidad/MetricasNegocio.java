package cl.duoc.productos.observabilidad;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

/**
 * Métricas propias del microservicio (además de las que Spring Boot entrega por defecto:
 * peticiones HTTP, JVM, CPU, pool de conexiones, etc.).
 *
 * Prometheus las lee desde /actuator/prometheus con el prefijo "productos_".
 * Las etiquetas tienen valores acotados (nunca datos ingresados por el cliente)
 * para no generar series ilimitadas en Prometheus.
 */
@Component
public class MetricasNegocio {

    private static final String ERRORES = "productos.errores";

    private final MeterRegistry registry;
    private final Counter creados;
    private final Counter eliminados;
    private final Counter stockIngresos;
    private final Counter stockEgresos;
    private final Counter stockRechazos;

    public MetricasNegocio(MeterRegistry registry) {
        this.registry = registry;
        this.creados = Counter.builder("productos.creados")
                .description("Productos creados en el catálogo")
                .register(registry);
        this.eliminados = Counter.builder("productos.eliminados")
                .description("Productos eliminados del catálogo")
                .register(registry);
        this.stockIngresos = Counter.builder("productos.stock.movimientos")
                .description("Unidades de stock movidas")
                .tag("tipo", "ingreso")
                .register(registry);
        this.stockEgresos = Counter.builder("productos.stock.movimientos")
                .description("Unidades de stock movidas")
                .tag("tipo", "egreso")
                .register(registry);
        this.stockRechazos = Counter.builder("productos.stock.rechazos")
                .description("Operaciones rechazadas porque el stock quedaría negativo")
                .register(registry);
    }

    public void productoCreado() {
        creados.increment();
    }

    public void productoEliminado() {
        eliminados.increment();
    }

    /** Registra un movimiento de stock: positivo = ingreso, negativo = egreso. */
    public void movimientoStock(int cantidad) {
        if (cantidad >= 0) {
            stockIngresos.increment(cantidad);
        } else {
            stockEgresos.increment(Math.abs((double) cantidad));
        }
    }

    public void stockRechazado() {
        stockRechazos.increment();
    }

    /**
     * Cuenta un error devuelto por la API.
     *
     * @param tipo   categoría acotada del error (no_encontrado, validacion, stock_insuficiente, interno...)
     * @param status código HTTP devuelto
     */
    public void errorRegistrado(String tipo, int status) {
        Counter.builder(ERRORES)
                .description("Errores devueltos por la API, por tipo y código HTTP")
                .tag("tipo", tipo)
                .tag("status", String.valueOf(status))
                .register(registry)
                .increment();
    }
}
