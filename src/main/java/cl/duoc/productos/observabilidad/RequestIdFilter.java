package cl.duoc.productos.observabilidad;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Trazabilidad de cada petición:
 * <ul>
 *   <li>Usa el encabezado X-Request-Id si viene (por ejemplo desde nginx) o genera uno nuevo.</li>
 *   <li>Lo agrega a todos los logs de la petición (MDC "request_id") y lo devuelve en la respuesta.</li>
 *   <li>Escribe una línea de log de acceso con método, ruta, código HTTP y duración.</li>
 * </ul>
 * Con el request_id se puede buscar en Loki/Grafana todo lo que pasó en una petición concreta.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Request-Id";
    public static final String MDC_KEY = "request_id";

    private static final Logger log = LoggerFactory.getLogger(RequestIdFilter.class);
    // Solo se aceptan ids "razonables" para evitar inyección de texto en los logs
    private static final Pattern ID_VALIDO = Pattern.compile("^[A-Za-z0-9._-]{1,64}$");

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String requestId = obtenerRequestId(request.getHeader(HEADER));
        long inicio = System.nanoTime();
        MDC.put(MDC_KEY, requestId);
        response.setHeader(HEADER, requestId);
        try {
            chain.doFilter(request, response);
        } finally {
            String ruta = request.getRequestURI();
            if (ruta.startsWith("/api/")) {
                long duracionMs = (System.nanoTime() - inicio) / 1_000_000;
                log.info("{} {} -> {} ({} ms)", request.getMethod(), sinSaltosDeLinea(ruta),
                        response.getStatus(), duracionMs);
            }
            MDC.remove(MDC_KEY);
        }
    }

    static String obtenerRequestId(String recibido) {
        if (recibido != null && ID_VALIDO.matcher(recibido).matches()) {
            return recibido;
        }
        return UUID.randomUUID().toString();
    }

    /** Evita que una ruta manipulada agregue líneas falsas al log (log injection). */
    static String sinSaltosDeLinea(String texto) {
        return texto.replaceAll("[\\r\\n\\t]", "_");
    }
}
