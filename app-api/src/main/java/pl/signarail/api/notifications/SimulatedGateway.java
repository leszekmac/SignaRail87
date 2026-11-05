package pl.signarail.api.notifications;

import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import pl.signarail.api.model.ApiModels.Notification;

/** Symulacja zewnetrznej bramki: stala latencja i losowe awarie. */
@Component
public class SimulatedGateway implements MessageGateway {

    private static final Logger log = LoggerFactory.getLogger(SimulatedGateway.class);

    private final NotificationProperties properties;

    public SimulatedGateway(NotificationProperties properties) {
        this.properties = properties;
    }

    @Override
    public void send(Notification n) {
        try {
            Thread.sleep(properties.gatewayLatencyMs());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Przerwano wysylke", e);
        }
        if (ThreadLocalRandom.current().nextDouble() < properties.gatewayFailureRate()) {
            throw new IllegalStateException("Bramka " + n.channel() + " niedostepna");
        }
        log.info("[{}] do {}: {}", n.channel(), n.recipient(), n.body());
    }
}
