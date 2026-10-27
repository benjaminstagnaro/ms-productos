package cl.duoc.productos.service;

import cl.duoc.productos.exception.ProductoNoEncontradoException;
import cl.duoc.productos.exception.StockInsuficienteException;
import cl.duoc.productos.model.Producto;
import cl.duoc.productos.repository.ProductoRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ProductoServiceTest {

    @Mock
    private ProductoRepository productoRepository;

    @InjectMocks
    private ProductoService productoService;

    private Producto notebook;

    @BeforeEach
    void setUp() {
        notebook = new Producto(1L, "Notebook", "Notebook 14 pulgadas", new BigDecimal("599990"), 10, "computacion");
    }

    @Test
    @DisplayName("listar devuelve todos los productos del repositorio")
    void listarDevuelveTodos() {
        when(productoRepository.findAll()).thenReturn(List.of(notebook));

        assertThat(productoService.listar()).containsExactly(notebook);
    }

    @Test
    @DisplayName("listarPorCategoria filtra por categoría")
    void listarPorCategoria() {
        when(productoRepository.findByCategoriaIgnoreCase("computacion")).thenReturn(List.of(notebook));

        assertThat(productoService.listarPorCategoria("computacion")).hasSize(1);
    }

    @Test
    @DisplayName("buscarPorId devuelve el producto cuando existe")
    void buscarPorIdExistente() {
        when(productoRepository.findById(1L)).thenReturn(Optional.of(notebook));

        assertThat(productoService.buscarPorId(1L).getNombre()).isEqualTo("Notebook");
    }

    @Test
    @DisplayName("buscarPorId lanza excepción cuando el producto no existe")
    void buscarPorIdInexistente() {
        when(productoRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> productoService.buscarPorId(99L))
                .isInstanceOf(ProductoNoEncontradoException.class)
                .hasMessageContaining("99");
    }

    @Test
    @DisplayName("crear ignora el id enviado por el cliente y guarda el producto")
    void crearIgnoraId() {
        Producto nuevo = new Producto(50L, "Mouse", null, new BigDecimal("9990"), 5, "accesorios");
        when(productoRepository.save(any(Producto.class))).thenAnswer(inv -> {
            Producto p = inv.getArgument(0);
            assertThat(p.getId()).isNull();
            p.setId(2L);
            return p;
        });

        Producto creado = productoService.crear(nuevo);

        assertThat(creado.getId()).isEqualTo(2L);
    }

    @Test
    @DisplayName("actualizar reemplaza los datos del producto existente")
    void actualizarExistente() {
        Producto cambios = new Producto(null, "Notebook Pro", "Nueva descripción", new BigDecimal("799990"), 3, "computacion");
        when(productoRepository.findById(1L)).thenReturn(Optional.of(notebook));
        when(productoRepository.save(any(Producto.class))).thenAnswer(inv -> inv.getArgument(0));

        Producto actualizado = productoService.actualizar(1L, cambios);

        assertThat(actualizado.getId()).isEqualTo(1L);
        assertThat(actualizado.getNombre()).isEqualTo("Notebook Pro");
        assertThat(actualizado.getDescripcion()).isEqualTo("Nueva descripción");
        assertThat(actualizado.getPrecio()).isEqualByComparingTo("799990");
        assertThat(actualizado.getStock()).isEqualTo(3);
        assertThat(actualizado.getCategoria()).isEqualTo("computacion");
    }

    @Test
    @DisplayName("actualizar lanza excepción si el producto no existe")
    void actualizarInexistente() {
        when(productoRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> productoService.actualizar(99L, notebook))
                .isInstanceOf(ProductoNoEncontradoException.class);
        verify(productoRepository, never()).save(any());
    }

    @Test
    @DisplayName("eliminar borra el producto cuando existe")
    void eliminarExistente() {
        when(productoRepository.existsById(1L)).thenReturn(true);

        productoService.eliminar(1L);

        verify(productoRepository).deleteById(1L);
    }

    @Test
    @DisplayName("eliminar lanza excepción si el producto no existe")
    void eliminarInexistente() {
        when(productoRepository.existsById(99L)).thenReturn(false);

        assertThatThrownBy(() -> productoService.eliminar(99L))
                .isInstanceOf(ProductoNoEncontradoException.class);
        verify(productoRepository, never()).deleteById(any());
    }

    @Test
    @DisplayName("ajustarStock suma unidades al stock")
    void ajustarStockSuma() {
        when(productoRepository.findById(1L)).thenReturn(Optional.of(notebook));
        when(productoRepository.save(any(Producto.class))).thenAnswer(inv -> inv.getArgument(0));

        assertThat(productoService.ajustarStock(1L, 5).getStock()).isEqualTo(15);
    }

    @Test
    @DisplayName("ajustarStock permite dejar el stock exactamente en cero")
    void ajustarStockHastaCero() {
        when(productoRepository.findById(1L)).thenReturn(Optional.of(notebook));
        when(productoRepository.save(any(Producto.class))).thenAnswer(inv -> inv.getArgument(0));

        assertThat(productoService.ajustarStock(1L, -10).getStock()).isZero();
    }

    @Test
    @DisplayName("ajustarStock rechaza dejar el stock negativo (caso crítico de negocio)")
    void ajustarStockInsuficiente() {
        when(productoRepository.findById(1L)).thenReturn(Optional.of(notebook));

        assertThatThrownBy(() -> productoService.ajustarStock(1L, -11))
                .isInstanceOf(StockInsuficienteException.class)
                .hasMessageContaining("disponible 10");
        verify(productoRepository, never()).save(any());
    }
}
