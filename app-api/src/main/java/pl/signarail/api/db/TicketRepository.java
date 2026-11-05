package pl.signarail.api.db;

import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import pl.signarail.api.model.ApiModels.BookTicketRequest;
import pl.signarail.api.model.ApiModels.DelayResult;
import pl.signarail.api.model.ApiModels.Ticket;

@Repository
public class TicketRepository {

    private final JdbcTemplate jdbc;

    public TicketRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Ticket book(BookTicketRequest r, String idempotencyKey) {
        return jdbc.execute(
                con -> con.prepareCall("{call pkg_rezerwacja.kup_bilet(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)}"),
                (CallableStatement cs) -> {
                    cs.setLong(1, r.courseId());
                    cs.setString(2, r.from());
                    cs.setString(3, r.to());
                    cs.setString(4, r.passenger());
                    cs.setString(5, r.email());
                    cs.setString(6, r.phone());
                    if (r.seatId() == null) {
                        cs.setNull(7, Types.NUMERIC);
                    } else {
                        cs.setLong(7, r.seatId());
                    }
                    cs.setInt(8, r.travelClass() == null ? 2 : r.travelClass());
                    cs.setString(9, idempotencyKey);
                    cs.registerOutParameter(10, Types.NUMERIC);
                    cs.registerOutParameter(11, Types.VARCHAR);
                    cs.registerOutParameter(12, Types.NUMERIC);
                    cs.registerOutParameter(13, Types.NUMERIC);
                    cs.execute();
                    BigDecimal price = cs.getBigDecimal(13);
                    return new Ticket(cs.getLong(10), cs.getString(11), cs.getLong(12), price);
                });
    }

    public void cancel(String ticketNumber) {
        jdbc.update("{call pkg_rezerwacja.anuluj_bilet(?)}", ticketNumber);
    }

    public DelayResult reportDelay(long courseId, int minutes, String reason) {
        return jdbc.execute(
                con -> con.prepareCall("{call pkg_rozklad.zglos_opoznienie(?, ?, ?, ?)}"),
                (CallableStatement cs) -> {
                    cs.setLong(1, courseId);
                    cs.setInt(2, minutes);
                    cs.setString(3, reason);
                    cs.registerOutParameter(4, Types.NUMERIC);
                    cs.execute();
                    return new DelayResult(courseId, minutes, cs.getInt(4));
                });
    }
}
