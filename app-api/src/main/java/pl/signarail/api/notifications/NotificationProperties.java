package pl.signarail.api.notifications;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("signarail.notifications")
public record NotificationProperties(
        boolean enabled,
        int batchSize,
        int queueCapacity,
        int workers,
        double gatewayFailureRate,
        int gatewayLatencyMs) {
}
