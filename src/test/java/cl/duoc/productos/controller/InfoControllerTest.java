package cl.duoc.productos.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(InfoController.class)
class InfoControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void infoExponeVersionCommitEInstancia() throws Exception {
        mockMvc.perform(get("/api/info"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.servicio").value("ms-productos"))
                .andExpect(jsonPath("$.version").value("test"))
                .andExpect(jsonPath("$.commit").value("test-commit"))
                .andExpect(jsonPath("$.instancia").isNotEmpty());
    }

    @Test
    void obtenerInstanciaDevuelveElHostname() {
        assertThat(InfoController.obtenerInstancia()).isNotBlank();
    }
}
