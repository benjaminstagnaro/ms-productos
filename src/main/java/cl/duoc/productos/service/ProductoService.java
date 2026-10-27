package cl.duoc.productos.service;

import cl.duoc.productos.exception.ProductoNoEncontradoException;
import cl.duoc.productos.exception.StockInsuficienteException;
import cl.duoc.productos.model.Producto;
import cl.duoc.productos.repository.ProductoRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class ProductoService {

    private final ProductoRepository productoRepository;

    public ProductoService(ProductoRepository productoRepository) {
        this.productoRepository = productoRepository;
    }

    @Transactional(readOnly = true)
    public List<Producto> listar() {
        return productoRepository.findAll();
    }

    @Transactional(readOnly = true)
    public List<Producto> listarPorCategoria(String categoria) {
        return productoRepository.findByCategoriaIgnoreCase(categoria);
    }

    @Transactional(readOnly = true)
    public Producto buscarPorId(Long id) {
        return productoRepository.findById(id)
                .orElseThrow(() -> new ProductoNoEncontradoException(id));
    }

    @Transactional
    public Producto crear(Producto producto) {
        // El id lo genera la base de datos; se ignora cualquier id enviado por el cliente
        producto.setId(null);
        return productoRepository.save(producto);
    }

    @Transactional
    public Producto actualizar(Long id, Producto datos) {
        Producto existente = buscarPorId(id);
        existente.setNombre(datos.getNombre());
        existente.setDescripcion(datos.getDescripcion());
        existente.setPrecio(datos.getPrecio());
        existente.setStock(datos.getStock());
        existente.setCategoria(datos.getCategoria());
        return productoRepository.save(existente);
    }

    @Transactional
    public void eliminar(Long id) {
        if (!productoRepository.existsById(id)) {
            throw new ProductoNoEncontradoException(id);
        }
        productoRepository.deleteById(id);
    }

    /**
     * Suma (cantidad positiva) o descuenta (cantidad negativa) unidades del stock.
     * Regla de negocio: el stock nunca puede quedar negativo.
     */
    @Transactional
    public Producto ajustarStock(Long id, int cantidad) {
        Producto producto = buscarPorId(id);
        int nuevoStock = producto.getStock() + cantidad;
        if (nuevoStock < 0) {
            throw new StockInsuficienteException(id, producto.getStock(), cantidad);
        }
        producto.setStock(nuevoStock);
        return productoRepository.save(producto);
    }
}
