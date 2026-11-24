package cl.duoc.productos.observabilidad;

import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class RequestIdFilterTest {

    private final RequestIdFilter filtro = new RequestIdFilter();

    @Test
    void reutilizaElRequestIdRecibido() {
        assertThat(RequestIdFilter.obtenerRequestId("abc-123")).isEqualTo("abc-123");
    }

    @Test
    void generaUnIdNuevoSiNoVieneOEsInvalido() {
        assertThat(RequestIdFilter.obtenerRequestId(null)).hasSize(36);
        assertThat(RequestIdFilter.obtenerRequestId("con espacios y\nsalto")).hasSize(36);
        assertThat(RequestIdFilter.obtenerRequestId("x".repeat(65))).hasSize(36);
    }

    @Test
    void eliminaSaltosDeLineaDeLoQueSeEscribeEnElLog() {
        assertThat(RequestIdFilter.sinSaltosDeLinea("/api/a\r\nFALSO")).isEqualTo("/api/a__FALSO");
    }

    @Test
    void agregaElIdAlLogDuranteLaPeticionYLoDevuelveEnLaRespuesta() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/productos");
        request.addHeader(RequestIdFilter.HEADER, "req-42");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicReference<String> idDuranteLaPeticion = new AtomicReference<>();

        filtro.doFilter(request, response, new MockFilterChain() {
            @Override
            public void doFilter(jakarta.servlet.ServletRequest req, jakarta.servlet.ServletResponse res) {
                idDuranteLaPeticion.set(MDC.get(RequestIdFilter.MDC_KEY));
            }
        });

        assertThat(idDuranteLaPeticion.get()).isEqualTo("req-42");
        assertThat(response.getHeader(RequestIdFilter.HEADER)).isEqualTo("req-42");
        assertThat(MDC.get(RequestIdFilter.MDC_KEY)).isNull();
    }

    @Test
    void tambienAgregaElIdEnRutasFueraDeLaApi() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/readyz");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filtro.doFilter(request, response, new MockFilterChain());

        assertThat(response.getHeader(RequestIdFilter.HEADER)).isNotBlank();
    }
}
