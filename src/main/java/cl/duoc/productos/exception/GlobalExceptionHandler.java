package cl.duoc.productos.exception;

import cl.duoc.productos.observabilidad.MetricasNegocio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Manejo centralizado de errores. Además de responder con un JSON uniforme,
 * cada error se registra en el log y se cuenta en la métrica "productos_errores_total"
 * (por tipo y código HTTP), que alimenta el panel "Errores registrados" del dashboard.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private final MetricasNegocio metricas;

    public GlobalExceptionHandler(MetricasNegocio metricas) {
        this.metricas = metricas;
    }

    @ExceptionHandler(ProductoNoEncontradoException.class)
    public ResponseEntity<Map<String, Object>> manejarNoEncontrado(ProductoNoEncontradoException ex) {
        return registrarYResponder(HttpStatus.NOT_FOUND, "no_encontrado", ex.getMessage(), null);
    }

    @ExceptionHandler(StockInsuficienteException.class)
    public ResponseEntity<Map<String, Object>> manejarStockInsuficiente(StockInsuficienteException ex) {
        return registrarYResponder(HttpStatus.CONFLICT, "stock_insuficiente", ex.getMessage(), null);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> manejarValidacion(MethodArgumentNotValidException ex) {
        Map<String, String> errores = new LinkedHashMap<>();
        for (FieldError error : ex.getBindingResult().getFieldErrors()) {
            errores.put(error.getField(), error.getDefaultMessage());
        }
        return registrarYResponder(HttpStatus.BAD_REQUEST, "validacion", "Datos de entrada inválidos", errores);
    }

    @ExceptionHandler({MethodArgumentTypeMismatchException.class, HttpMessageNotReadableException.class,
            MissingServletRequestParameterException.class})
    public ResponseEntity<Map<String, Object>> manejarPeticionMalFormada(Exception ex) {
        return registrarYResponder(HttpStatus.BAD_REQUEST, "peticion_mal_formada",
                "La petición no tiene el formato esperado", null);
    }

    /**
     * Cualquier otra excepción. Las excepciones estándar de Spring (ruta inexistente, método no permitido...)
     * conservan su código HTTP; el resto es un error interno que se registra con su traza completa.
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> manejarInesperado(Exception ex) {
        if (ex instanceof ErrorResponse errorResponse) {
            HttpStatus estado = HttpStatus.resolve(errorResponse.getStatusCode().value());
            if (estado != null) {
                return registrarYResponder(estado, "peticion_invalida", estado.getReasonPhrase(), null);
            }
        }
        log.error("Error no controlado", ex);
        return registrarYResponder(HttpStatus.INTERNAL_SERVER_ERROR, "interno",
                "Error interno del servidor", null);
    }

    private ResponseEntity<Map<String, Object>> registrarYResponder(HttpStatus estado, String tipo, String mensaje,
                                                                    Map<String, String> errores) {
        metricas.errorRegistrado(tipo, estado.value());
        if (estado.is4xxClientError()) {
            log.warn("Petición rechazada: tipo={} status={} mensaje={}", tipo, estado.value(), mensaje);
        }
        Map<String, Object> cuerpo = new LinkedHashMap<>();
        cuerpo.put("timestamp", Instant.now().toString());
        cuerpo.put("status", estado.value());
        cuerpo.put("error", estado.getReasonPhrase());
        cuerpo.put("mensaje", mensaje);
        if (errores != null) {
            cuerpo.put("errores", errores);
        }
        return ResponseEntity.status(estado).body(cuerpo);
    }
}
