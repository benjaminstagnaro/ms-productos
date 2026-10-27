package cl.duoc.productos.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Expone la versión y el commit con que se construyó la imagen (trazabilidad)
 * y el nombre del contenedor que respondió (permite comprobar el balanceo entre réplicas).
 */
@RestController
@RequestMapping("/api/info")
public class InfoController {

    private final String nombreServicio;
    private final String version;
    private final String commit;

    public InfoController(@Value("${spring.application.name}") String nombreServicio,
                          @Value("${app.version}") String version,
                          @Value("${app.commit}") String commit) {
        this.nombreServicio = nombreServicio;
        this.version = version;
        this.commit = commit;
    }

    @GetMapping
    public Map<String, String> info() {
        Map<String, String> info = new LinkedHashMap<>();
        info.put("servicio", nombreServicio);
        info.put("version", version);
        info.put("commit", commit);
        info.put("instancia", obtenerInstancia());
        return info;
    }

    static String obtenerInstancia() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "desconocida";
        }
    }
}
