package pl.signarail.api.notifications;

import pl.signarail.api.model.ApiModels.Notification;

/** Bramka SMS/e-mail. Wyjatek oznacza, ze wiadomosc nalezy ponowic. */
public interface MessageGateway {

    void send(Notification notification);
}
