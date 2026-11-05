package pl.signarail.api.notifications;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import pl.signarail.api.db.NotificationRepository;
import pl.signarail.api.model.ApiModels.Notification;

/**
 * Przepompowuje skrzynke z bazy do ograniczonej kolejki w pamieci, z ktorej czytaja pracownicy.
 *
 * <p>Baza jest zrodlem prawdy, kolejka tylko buforem: po restarcie aplikacji niepotwierdzone wiersze
 * wracaja do obiegu po wygasnieciu dzierzawy (PKG_POWIADOMIENIA). Pobieranie tylko tylu wierszy, ile
 * miesci sie w kolejce, daje naturalny backpressure, gdy bramka nie nadaza.
 */
@Component
public class NotificationDispatcher {

    private static final Logger log = LoggerFactory.getLogger(NotificationDispatcher.class);

    private final NotificationRepository repository;
    private final MessageGateway gateway;
    private final NotificationProperties properties;
    private final BlockingQueue<Notification> queue;
    private final AtomicLong delivered = new AtomicLong();
    private final AtomicLong failed = new AtomicLong();
    private ExecutorService workers;

    public NotificationDispatcher(NotificationRepository repository, MessageGateway gateway,
                                  NotificationProperties properties) {
        this.repository = repository;
        this.gateway = gateway;
        this.properties = properties;
        this.queue = new ArrayBlockingQueue<>(properties.queueCapacity());
    }

    @PostConstruct
    void startWorkers() {
        if (!properties.enabled()) {
            return;
        }
        workers = Executors.newFixedThreadPool(properties.workers(),
                Thread.ofVirtual().name("powiadomienia-", 0).factory());
        for (int i = 0; i < properties.workers(); i++) {
            workers.submit(this::workerLoop);
        }
    }

    @PreDestroy
    void stopWorkers() {
        if (workers != null) {
            workers.shutdownNow();
        }
    }

    @Scheduled(fixedDelayString = "${signarail.notifications.poll-interval-ms}")
    public void poll() {
        if (!properties.enabled()) {
            return;
        }
        int capacity = Math.min(queue.remainingCapacity(), properties.batchSize());
        if (capacity == 0) {
            return;
        }
        try {
            // Dokladac moze tylko ten watek, wiec sprawdzona pojemnosc jest pewna.
            repository.claimBatch(capacity).forEach(queue::offer);
        } catch (RuntimeException e) {
            log.warn("Nie udalo sie pobrac partii powiadomien: {}", e.getMessage());
        }
    }

    void workerLoop() {
        while (!Thread.currentThread().isInterrupted()) {
            try {
                process(queue.take());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    void process(Notification notification) {
        try {
            gateway.send(notification);
        } catch (RuntimeException e) {
            failed.incrementAndGet();
            repository.reject(notification.id(), e.getMessage());
            return;
        }
        repository.acknowledge(notification.id());
        delivered.incrementAndGet();
    }

    public int queueDepth() {
        return queue.size();
    }

    public long delivered() {
        return delivered.get();
    }

    public long failed() {
        return failed.get();
    }
}
