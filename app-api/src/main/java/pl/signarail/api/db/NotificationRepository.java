package pl.signarail.api.db;

import java.sql.CallableStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import oracle.jdbc.OracleTypes;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
import pl.signarail.api.model.ApiModels.Notification;

@Repository
public class NotificationRepository {

    private final JdbcTemplate jdbc;

    public NotificationRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Transakcja obejmuje odczyt kursora: rezerwacja wierszy zatwierdza sie po pobraniu partii. */
    @Transactional
    public List<Notification> claimBatch(int limit) {
        return jdbc.execute(
                con -> con.prepareCall("{call pkg_powiadomienia.pobierz_partie(?, ?)}"),
                (CallableStatement cs) -> {
                    cs.setInt(1, limit);
                    cs.registerOutParameter(2, OracleTypes.CURSOR);
                    cs.execute();
                    List<Notification> batch = new ArrayList<>();
                    try (ResultSet rs = (ResultSet) cs.getObject(2)) {
                        while (rs.next()) {
                            batch.add(new Notification(rs.getLong(1), rs.getString(2), rs.getString(3),
                                    rs.getString(4), rs.getInt(5)));
                        }
                    }
                    return batch;
                });
    }

    public void acknowledge(long id) {
        jdbc.update("{call pkg_powiadomienia.potwierdz(?)}", id);
    }

    public void reject(long id, String error) {
        jdbc.update("{call pkg_powiadomienia.odrzuc(?, ?)}", id, error);
    }

    public Map<String, Long> countByStatus() {
        return jdbc.query("SELECT status, COUNT(*) FROM powiadomienia GROUP BY status",
                (rs, i) -> Map.entry(rs.getString(1), rs.getLong(2)))
                .stream().collect(Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
    }
}
