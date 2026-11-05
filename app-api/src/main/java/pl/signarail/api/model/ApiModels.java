package pl.signarail.api.model;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/** Kontrakt REST. Reguly biznesowe zyja w PL/SQL; tu sprawdzany jest tylko ksztalt danych. */
public final class ApiModels {

    private ApiModels() {
    }

    public record Station(String code, String name) {
    }

    public record Leg(long courseId, String trainNumber, String category, String fromCode, String fromName,
                      LocalDateTime departure, String toCode, String toName, LocalDateTime arrival) {
    }

    public record Connection(int id, LocalDateTime departure, LocalDateTime arrival, int transfers,
                             int durationMinutes, List<Leg> legs) {
    }

    public record BookTicketRequest(
            @NotNull Long courseId,
            @NotBlank @Size(max = 8) String from,
            @NotBlank @Size(max = 8) String to,
            @NotBlank @Size(max = 100) String passenger,
            @Email @Size(max = 120) String email,
            @Pattern(regexp = "\\+?[0-9]{9,15}") String phone,
            Long seatId,
            @Min(1) @Max(2) Integer travelClass) {
    }

    public record Ticket(long reservationId, String ticketNumber, long seatId, BigDecimal price) {
    }

    public record DelayReport(
            @NotNull Long courseId,
            @NotNull @PositiveOrZero @Max(1440) Integer minutes,
            @Size(max = 200) String reason) {
    }

    public record DelayResult(long courseId, int minutes, int notificationsQueued) {
    }

    public record Notification(long id, String channel, String recipient, String body, int attempt) {
    }

    public record NotificationStats(long pending, long inProgress, long sent, long dead,
                                    int queueDepth, long deliveredByThisInstance, long failedAttempts) {
    }

    public record TrackBlock(String code, int lengthMm, String status, Long courseId) {
    }

    public record LayoutCourse(long id, String name, String status, String weather, Long locomotiveId,
                               Integer speedKmh, Integer seats) {
    }

    public record DccCommand(long id, Long courseId, String type, String frame, String description, String status) {
    }

    public record PowerBudget(int consumptionMa, int limitMa) {
    }
}
