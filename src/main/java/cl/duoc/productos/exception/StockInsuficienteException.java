package cl.duoc.productos.exception;

public class StockInsuficienteException extends RuntimeException {

    public StockInsuficienteException(Long id, int stockActual, int cantidadSolicitada) {
        super("Stock insuficiente para el producto " + id + ": disponible " + stockActual
                + ", se intentó descontar " + Math.abs(cantidadSolicitada));
    }
}
