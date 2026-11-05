package pl.signarail.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;

import java.time.Duration;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;

/** Testy na prawdziwym Oracle: overbooking da sie sprawdzic tylko na realnych transakcjach. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = {
        "signarail.notifications.gateway-failure-rate=0",
        "signarail.notifications.poll-interval-ms=100"})
@EnabledIfEnvironmentVariable(named = "SIGNARAIL_DB_URL", matches = ".+")
class ApiIntegrationTest {

    private static final int CLIENTS = 40;

    @Autowired
    private TestRestTemplate rest;

    @Autowired
    private JdbcTemplate jdbc;

    private long courseId;
    private long seatId;

    @BeforeEach
    void selectFixture() {
        // IC3510, wagon 2. Wiersze testu sa czyszczone, wiec test mozna powtarzac na tej samej bazie.
        courseId = jdbc.queryForObject(
                "SELECT id_kursu FROM kursy_rozkladowe WHERE id_pociagu = 1 AND data_kursu = ?",
                Long.class, java.sql.Date.valueOf(LocalDate.now().plusDays(5)));
        seatId = jdbc.queryForObject(
                "SELECT id_miejsca FROM miejsca WHERE id_wagonu = 2 AND nr_miejsca = 1", Long.class);
        cleanUp();
    }

    @AfterEach
    void cleanUp() {
        jdbc.update("DELETE FROM powiadomienia WHERE id_rezerwacji IN "
                + "(SELECT id_rezerwacji FROM rezerwacje WHERE id_kursu = ?)", courseId);
        jdbc.update("DELETE FROM rezerwacje_odcinki WHERE id_kursu = ?", courseId);
        jdbc.update("DELETE FROM rezerwacje WHERE id_kursu = ?", courseId);
        jdbc.update("UPDATE kursy_rozkladowe SET status = 'PLANOWY', opoznienie_min = 0 WHERE id_kursu = ?", courseId);
    }

    private Map<String, Object> booking(Long seat, String from, String to) {
        Map<String, Object> body = new HashMap<>();
        body.put("courseId", courseId);
        body.put("from", from);
        body.put("to", to);
        body.put("passenger", "Test");
        body.put("email", "test@example.com");
        body.put("seatId", seat);
        return body;
    }

    private ResponseEntity<Map> book(Map<String, Object> body, String idempotencyKey) {
        HttpHeaders headers = new HttpHeaders();
        if (idempotencyKey != null) {
            headers.set("Idempotency-Key", idempotencyKey);
        }
        return rest.exchange("/api/book-ticket", HttpMethod.POST, new HttpEntity<>(body, headers), Map.class);
    }

    /** Wszystkie zadania startuja w tej samej chwili, by naprawde konkurowac o wiersz. */
    private <T> List<T> concurrently(int count, Callable<T> task) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(count);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Future<T>> futures = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                futures.add(pool.submit(() -> {
                    start.await();
                    return task.call();
                }));
            }
            start.countDown();
            List<T> results = new ArrayList<>();
            for (Future<T> f : futures) {
                results.add(f.get());
            }
            return results;
        } finally {
            pool.shutdownNow();
        }
    }

    @Test
    void sameSeatIsSoldExactlyOnceUnderConcurrency() throws Exception {
        List<HttpStatus> statuses = concurrently(CLIENTS,
                () -> HttpStatus.valueOf(book(booking(seatId, "RZE", "KRK"), null).getStatusCode().value()));

        assertThat(statuses).filteredOn(s -> s == HttpStatus.CREATED).hasSize(1);
        assertThat(statuses).doesNotContain(HttpStatus.INTERNAL_SERVER_ERROR);
        assertThat(statuses).allMatch(s -> s == HttpStatus.CREATED || s == HttpStatus.CONFLICT || s == HttpStatus.LOCKED);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM rezerwacje WHERE id_kursu = ?", Integer.class, courseId))
                .isEqualTo(1);
    }

    @Test
    void automaticSelectionGivesEveryClientDifferentSeat() throws Exception {
        List<Map> tickets = concurrently(CLIENTS, () -> book(booking(null, "RZE", "KRK"), null).getBody());

        Set<Object> seats = new HashSet<>();
        tickets.forEach(t -> seats.add(t.get("seatId")));
        assertThat(seats).hasSize(CLIENTS);
    }

    @Test
    void lastSeatsAreNotOversold() throws Exception {
        // W klasie 2 tego skladu jest 60 miejsc, a klientow jest wiecej.
        List<Integer> statuses = concurrently(75,
                () -> book(booking(null, "RZE", "KRK"), null).getStatusCode().value());

        assertThat(statuses).filteredOn(s -> s == 201).hasSizeLessThanOrEqualTo(60);
        assertThat(jdbc.queryForObject("""
                SELECT COUNT(*) FROM (SELECT id_miejsca, lp_odcinka FROM rezerwacje_odcinki
                 WHERE id_kursu = ? GROUP BY id_miejsca, lp_odcinka HAVING COUNT(*) > 1)""",
                Integer.class, courseId)).isZero();
    }

    @Test
    void retriesWithSameKeyCreateOneTicket() throws Exception {
        List<Map> responses = concurrently(10, () -> book(booking(seatId, "RZE", "KRK"), "powtorka-klienta").getBody());

        Set<Object> ticketNumbers = new HashSet<>();
        responses.forEach(r -> ticketNumbers.add(r.get("ticketNumber")));
        assertThat(ticketNumbers).hasSize(1).doesNotContainNull();
    }

    @Test
    void connectionsAreReturnedAsNestedLegs() {
        String url = "/api/connections?from=RZE&to=GDA&departure=" + LocalDate.now().plusDays(5) + "T05:00:00";
        List<Map<String, Object>> connections = rest.getForObject(url, List.class);

        assertThat(connections).isNotEmpty();
        assertThat(connections.getFirst().get("transfers")).isEqualTo(2);
        assertThat((List<?>) connections.getFirst().get("legs")).hasSize(3);
    }

    @Test
    void validationAndBusinessErrorsUseProblemDetails() {
        ResponseEntity<Map> invalid = book(Map.of("courseId", courseId), null);
        assertThat(invalid.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);

        ResponseEntity<Map> unknown = rest.getForEntity(
                "/api/connections?from=XXX&to=RZE&departure=2030-01-01T05:00:00", Map.class);
        assertThat(unknown.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(unknown.getBody().get("detail")).isEqualTo("Nie ma stacji XXX");
    }

    @Test
    void delayReachesPassengersThroughOutboxAndQueue() {
        for (int i = 0; i < 5; i++) {
            assertThat(book(booking(null, "RZE", "KRK"), null).getStatusCode()).isEqualTo(HttpStatus.CREATED);
        }
        ResponseEntity<Map> delay = rest.postForEntity("/api/delays",
                Map.of("courseId", courseId, "minutes", 20, "reason", "Awaria rozjazdu"), Map.class);
        assertThat(delay.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
        assertThat(delay.getBody().get("notificationsQueued")).isEqualTo(5);

        await().atMost(Duration.ofSeconds(10)).untilAsserted(() ->
                assertThat(jdbc.queryForObject("""
                        SELECT COUNT(*) FROM powiadomienia p JOIN rezerwacje r ON r.id_rezerwacji = p.id_rezerwacji
                         WHERE r.id_kursu = ? AND p.status = 'WYSLANE'""", Integer.class, courseId)).isEqualTo(5));
    }
}
