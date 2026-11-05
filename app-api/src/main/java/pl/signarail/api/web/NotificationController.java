package pl.signarail.api.web;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import pl.signarail.api.db.NotificationRepository;
import pl.signarail.api.model.ApiModels.NotificationStats;
import pl.signarail.api.notifications.NotificationDispatcher;

@RestController
public class NotificationController {

    private final NotificationRepository repository;
    private final NotificationDispatcher dispatcher;

    public NotificationController(NotificationRepository repository, NotificationDispatcher dispatcher) {
        this.repository = repository;
        this.dispatcher = dispatcher;
    }

    @GetMapping("/api/notifications/stats")
    public NotificationStats stats() {
        Map<String, Long> counts = repository.countByStatus();
        return new NotificationStats(
                counts.getOrDefault("NOWE", 0L), counts.getOrDefault("W_TOKU", 0L),
                counts.getOrDefault("WYSLANE", 0L), counts.getOrDefault("MARTWE", 0L),
                dispatcher.queueDepth(), dispatcher.delivered(), dispatcher.failed());
    }
}
