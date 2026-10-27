package cl.duoc.productos;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.net.URI;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Prueba de integración: levanta el contexto completo de Spring con H2
 * y recorre el flujo principal de la API, incluido el healthcheck.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ProductosApplicationTests {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void healthcheckRespondeUp() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void flujoCompletoCrearConsultarYDescontarStock() throws Exception {
        String json = """
                {"nombre":"Audífonos","descripcion":"Bluetooth","precio":24990,"stock":3,"categoria":"audio"}
                """;

        String location = mockMvc.perform(post("/api/productos").contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNumber())
                .andReturn().getResponse().getHeader("Location");
        String ruta = URI.create(location).getPath();

        mockMvc.perform(get("/api/productos").param("categoria", "audio"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].nombre").value("Audífonos"));

        mockMvc.perform(patch(ruta + "/stock").param("cantidad", "-2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stock").value(1));

        mockMvc.perform(patch(ruta + "/stock").param("cantidad", "-5"))
                .andExpect(status().isConflict());
    }
}
