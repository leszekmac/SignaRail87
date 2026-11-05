package pl.signarail.api.web;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import pl.signarail.api.db.ConnectionRepository;
import pl.signarail.api.model.ApiModels.Connection;
import pl.signarail.api.model.ApiModels.Station;

@RestController
@RequestMapping("/api")
@Validated
public class ConnectionController {

    private final ConnectionRepository repository;

    public ConnectionController(ConnectionRepository repository) {
        this.repository = repository;
    }

    @GetMapping("/stations")
    public List<Station> stations() {
        return repository.stations();
    }

    @GetMapping("/connections")
    public List<Connection> connections(
            @RequestParam String from,
            @RequestParam String to,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime departure,
            @RequestParam(defaultValue = "2") @Min(0) @Max(4) int maxTransfers,
            @RequestParam(defaultValue = "5") @Min(1) @Max(20) int limit) {
        return repository.find(from, to, departure, maxTransfers, limit);
    }
}
