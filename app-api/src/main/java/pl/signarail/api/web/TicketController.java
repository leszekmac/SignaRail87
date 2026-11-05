package pl.signarail.api.web;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import pl.signarail.api.db.TicketRepository;
import pl.signarail.api.model.ApiModels.BookTicketRequest;
import pl.signarail.api.model.ApiModels.DelayReport;
import pl.signarail.api.model.ApiModels.DelayResult;
import pl.signarail.api.model.ApiModels.Ticket;

/** PL/SQL nie zatwierdza transakcji; granica @Transactional jest tutaj. */
@RestController
@RequestMapping("/api")
@Validated
public class TicketController {

    private final TicketRepository repository;

    public TicketController(TicketRepository repository) {
        this.repository = repository;
    }

    @PostMapping("/book-ticket")
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public Ticket bookTicket(@Valid @RequestBody BookTicketRequest request,
                             @RequestHeader(name = "Idempotency-Key", required = false)
                             @Size(max = 64) String idempotencyKey) {
        return repository.book(request, idempotencyKey);
    }

    @DeleteMapping("/tickets/{ticketNumber}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional
    public void cancelTicket(@PathVariable String ticketNumber) {
        repository.cancel(ticketNumber);
    }

    @PostMapping("/delays")
    @ResponseStatus(HttpStatus.ACCEPTED)
    @Transactional
    public DelayResult reportDelay(@Valid @RequestBody DelayReport report) {
        return repository.reportDelay(report.courseId(), report.minutes(), report.reason());
    }
}
