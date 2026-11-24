package cl.duoc.productos.controller;

import cl.duoc.productos.exception.ProductoNoEncontradoException;
import cl.duoc.productos.exception.StockInsuficienteException;
import cl.duoc.productos.model.Producto;
import cl.duoc.productos.observabilidad.MetricasNegocio;
import cl.duoc.productos.service.ProductoService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.endsWith;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ProductoController.class)
class ProductoControllerTest {

    private static final String PRODUCTO_JSON = """
            {"nombre":"Notebook","descripcion":"14 pulgadas","precio":599990,"stock":10,"categoria":"computacion"}
            """;

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private ProductoService productoService;

    // El manejador global de errores cuenta cada error en una métrica
    @MockitoBean
    private MetricasNegocio metricas;

    private Producto notebook() {
        return new Producto(1L, "Notebook", "14 pulgadas", new BigDecimal("599990"), 10, "computacion");
    }

    @Test
    void listarDevuelve200ConLaLista() throws Exception {
        when(productoService.listar()).thenReturn(List.of(notebook()));

        mockMvc.perform(get("/api/productos"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].nombre").value("Notebook"));
    }

    @Test
    void listarConCategoriaUsaElFiltro() throws Exception {
        when(productoService.listarPorCategoria("computacion")).thenReturn(List.of(notebook()));

        mockMvc.perform(get("/api/productos").param("categoria", "computacion"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].categoria").value("computacion"));
        verify(productoService, never()).listar();
    }

    @Test
    void listarConCategoriaVaciaDevuelveTodos() throws Exception {
        when(productoService.listar()).thenReturn(List.of());

        mockMvc.perform(get("/api/productos").param("categoria", " "))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
        verify(productoService).listar();
    }

    @Test
    void buscarPorIdDevuelve200() throws Exception {
        when(productoService.buscarPorId(1L)).thenReturn(notebook());

        mockMvc.perform(get("/api/productos/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1))
                .andExpect(jsonPath("$.stock").value(10));
    }

    @Test
    void buscarPorIdInexistenteDevuelve404() throws Exception {
        when(productoService.buscarPorId(99L)).thenThrow(new ProductoNoEncontradoException(99L));

        mockMvc.perform(get("/api/productos/99"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.mensaje").value("No existe un producto con id 99"));
    }

    @Test
    void crearDevuelve201ConLocation() throws Exception {
        when(productoService.crear(any(Producto.class))).thenReturn(notebook());

        mockMvc.perform(post("/api/productos").contentType(MediaType.APPLICATION_JSON).content(PRODUCTO_JSON))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", endsWith("/api/productos/1")))
                .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    void crearIgnoraCamposQueElClienteNoPuedeAsignar() throws Exception {
        String conId = """
                {"id":999,"nombre":"Notebook","precio":599990,"stock":10,"categoria":"computacion"}
                """;
        when(productoService.crear(any(Producto.class))).thenReturn(notebook());

        mockMvc.perform(post("/api/productos").contentType(MediaType.APPLICATION_JSON).content(conId))
                .andExpect(status().isCreated());

        ArgumentCaptor<Producto> enviado = ArgumentCaptor.forClass(Producto.class);
        verify(productoService).crear(enviado.capture());
        assertThat(enviado.getValue().getId()).isNull();
        assertThat(enviado.getValue().getNombre()).isEqualTo("Notebook");
    }

    @Test
    void crearConDatosInvalidosDevuelve400() throws Exception {
        String invalido = """
                {"nombre":"","precio":-5,"stock":-1,"categoria":""}
                """;

        mockMvc.perform(post("/api/productos").contentType(MediaType.APPLICATION_JSON).content(invalido))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errores.nombre").exists())
                .andExpect(jsonPath("$.errores.precio").exists())
                .andExpect(jsonPath("$.errores.stock").exists())
                .andExpect(jsonPath("$.errores.categoria").exists());
        verify(productoService, never()).crear(any());
    }

    @Test
    void actualizarDevuelve200() throws Exception {
        when(productoService.actualizar(eq(1L), any(Producto.class))).thenReturn(notebook());

        mockMvc.perform(put("/api/productos/1").contentType(MediaType.APPLICATION_JSON).content(PRODUCTO_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Notebook"));
    }

    @Test
    void eliminarDevuelve204() throws Exception {
        mockMvc.perform(delete("/api/productos/1"))
                .andExpect(status().isNoContent());
        verify(productoService).eliminar(1L);
    }

    @Test
    void eliminarInexistenteDevuelve404() throws Exception {
        doThrow(new ProductoNoEncontradoException(99L)).when(productoService).eliminar(99L);

        mockMvc.perform(delete("/api/productos/99"))
                .andExpect(status().isNotFound());
    }

    @Test
    void ajustarStockDevuelve200() throws Exception {
        Producto conMasStock = notebook();
        conMasStock.setStock(15);
        when(productoService.ajustarStock(1L, 5)).thenReturn(conMasStock);

        mockMvc.perform(patch("/api/productos/1/stock").param("cantidad", "5"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stock").value(15));
    }

    @Test
    void ajustarStockInsuficienteDevuelve409() throws Exception {
        when(productoService.ajustarStock(1L, -50)).thenThrow(new StockInsuficienteException(1L, 10, -50));

        mockMvc.perform(patch("/api/productos/1/stock").param("cantidad", "-50"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value(409));
        verify(metricas).errorRegistrado("stock_insuficiente", 409);
    }

    @Test
    void idConFormatoInvalidoDevuelve400() throws Exception {
        mockMvc.perform(get("/api/productos/abc"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.mensaje").value("La petición no tiene el formato esperado"));
        verify(metricas).errorRegistrado("peticion_mal_formada", 400);
    }

    @Test
    void jsonMalFormadoDevuelve400() throws Exception {
        mockMvc.perform(post("/api/productos").contentType(MediaType.APPLICATION_JSON).content("{no es json"))
                .andExpect(status().isBadRequest());
        verify(productoService, never()).crear(any());
    }

    @Test
    void ajustarStockSinCantidadDevuelve400() throws Exception {
        mockMvc.perform(patch("/api/productos/1/stock"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void metodoNoPermitidoConservaSuCodigo405() throws Exception {
        mockMvc.perform(delete("/api/productos"))
                .andExpect(status().isMethodNotAllowed())
                .andExpect(jsonPath("$.status").value(405));
        verify(metricas).errorRegistrado("peticion_invalida", 405);
    }

    @Test
    void errorInesperadoDevuelve500SinDetallesInternos() throws Exception {
        when(productoService.listar()).thenThrow(new IllegalStateException("detalle interno que no debe filtrarse"));

        mockMvc.perform(get("/api/productos"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.mensaje").value("Error interno del servidor"));
        verify(metricas).errorRegistrado("interno", 500);
    }

    @Test
    void cadaRespuestaIncluyeRequestId() throws Exception {
        mockMvc.perform(get("/api/productos").header("X-Request-Id", "prueba-123"))
                .andExpect(header().string("X-Request-Id", "prueba-123"));
    }
}
