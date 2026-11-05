package pl.signarail.api.notifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Collections;
import java.util.List;
import org.junit.jupiter.api.Test;
import pl.signarail.api.db.NotificationRepository;
import pl.signarail.api.model.ApiModels.Notification;

class NotificationDispatcherTest {

    private static final Notification MESSAGE = new Notification(7, "SMS", "+48500100200", "Opoznienie", 1);

    private final NotificationRepository repository = mock(NotificationRepository.class);
    private final MessageGateway gateway = mock(MessageGateway.class);

    private NotificationDispatcher dispatcher(int queueCapacity, int batchSize) {
        return new NotificationDispatcher(repository, gateway,
                new NotificationProperties(true, batchSize, queueCapacity, 1, 0, 0));
    }

    @Test
    void acknowledgesAfterSuccessfulSend() {
        NotificationDispatcher dispatcher = dispatcher(10, 10);
        dispatcher.process(MESSAGE);
        verify(repository).acknowledge(7);
        verify(repository, never()).reject(anyLong(), org.mockito.ArgumentMatchers.anyString());
        assertThat(dispatcher.delivered()).isEqualTo(1);
    }

    @Test
    void rejectsSoDatabaseSchedulesRetryWhenGatewayFails() {
        doThrow(new IllegalStateException("Bramka SMS niedostepna")).when(gateway).send(MESSAGE);
        NotificationDispatcher dispatcher = dispatcher(10, 10);
        dispatcher.process(MESSAGE);
        verify(repository).reject(eq(7L), contains("niedostepna"));
        verify(repository, never()).acknowledge(anyLong());
        assertThat(dispatcher.failed()).isEqualTo(1);
    }

    @Test
    void neverClaimsMoreThanQueueCanHold() {
        when(repository.claimBatch(2)).thenReturn(List.of(MESSAGE, MESSAGE));
        NotificationDispatcher dispatcher = dispatcher(2, 50);
        dispatcher.poll();
        assertThat(dispatcher.queueDepth()).isEqualTo(2);
        dispatcher.poll();                               // kolejka pelna: baza nie jest pytana ponownie
        verify(repository).claimBatch(2);
    }

    @Test
    void databaseOutageDoesNotKillThePoller() {
        when(repository.claimBatch(5)).thenThrow(new org.springframework.dao.QueryTimeoutException("x"))
                .thenReturn(Collections.emptyList());
        NotificationDispatcher dispatcher = dispatcher(5, 5);
        dispatcher.poll();
        dispatcher.poll();
        verify(repository, org.mockito.Mockito.times(2)).claimBatch(5);
    }
}
