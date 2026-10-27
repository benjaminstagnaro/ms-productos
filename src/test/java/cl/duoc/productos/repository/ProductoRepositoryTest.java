package cl.duoc.productos.repository;

import cl.duoc.productos.model.Producto;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
class ProductoRepositoryTest {

    @Autowired
    private ProductoRepository productoRepository;

    @Test
    void guardaYGeneraId() {
        Producto guardado = productoRepository.save(
                new Producto(null, "Teclado", "Mecánico", new BigDecimal("39990"), 7, "accesorios"));

        assertThat(guardado.getId()).isNotNull();
        assertThat(productoRepository.findById(guardado.getId())).isPresent();
    }

    @Test
    void buscaPorCategoriaSinDistinguirMayusculas() {
        productoRepository.save(new Producto(null, "Monitor", null, new BigDecimal("149990"), 4, "Computacion"));
        productoRepository.save(new Producto(null, "Silla", null, new BigDecimal("89990"), 2, "muebles"));

        List<Producto> resultado = productoRepository.findByCategoriaIgnoreCase("COMPUTACION");

        assertThat(resultado).extracting(Producto::getNombre).containsExactly("Monitor");
    }
}
