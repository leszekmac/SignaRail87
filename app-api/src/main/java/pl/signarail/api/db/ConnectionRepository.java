package pl.signarail.api.db;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import oracle.jdbc.OracleTypes;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import pl.signarail.api.model.ApiModels.Connection;
import pl.signarail.api.model.ApiModels.Leg;
import pl.signarail.api.model.ApiModels.Station;

@Repository
public class ConnectionRepository {

    private final JdbcTemplate jdbc;

    public ConnectionRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Station> stations() {
        return jdbc.query("SELECT kod_stacji, nazwa FROM stacje ORDER BY nazwa",
                (rs, i) -> new Station(rs.getString(1), rs.getString(2)));
    }

    public List<Connection> find(String from, String to, LocalDateTime since, int maxTransfers, int limit) {
        return jdbc.execute(
                con -> con.prepareCall("{call pkg_rozklad.znajdz_polaczenie(?, ?, ?, ?, ?, ?)}"),
                (java.sql.CallableStatement cs) -> {
                    cs.setString(1, from);
                    cs.setString(2, to);
                    cs.setTimestamp(3, Timestamp.valueOf(since));
                    cs.setInt(4, maxTransfers);
                    cs.setInt(5, limit);
                    cs.registerOutParameter(6, OracleTypes.CURSOR);
                    cs.execute();
                    try (ResultSet rs = (ResultSet) cs.getObject(6)) {
                        return group(rs);
                    }
                });
    }

    /** Kursor zwraca odcinki posortowane po polaczeniu; API zwraca je zagniezdzone. */
    static List<Connection> group(ResultSet rs) throws SQLException {
        Map<Integer, List<Leg>> legs = new LinkedHashMap<>();
        Map<Integer, int[]> summary = new LinkedHashMap<>();
        while (rs.next()) {
            int id = rs.getInt("id_polaczenia");
            legs.computeIfAbsent(id, k -> new ArrayList<>()).add(new Leg(
                    rs.getLong("id_kursu"), rs.getString("numer_pociagu"), rs.getString("kategoria"),
                    rs.getString("kod_od"), rs.getString("stacja_od"),
                    rs.getTimestamp("odjazd").toLocalDateTime(),
                    rs.getString("kod_do"), rs.getString("stacja_do"),
                    rs.getTimestamp("przyjazd").toLocalDateTime()));
            summary.put(id, new int[] {rs.getInt("przesiadki"), rs.getInt("czas_podrozy_min")});
        }
        List<Connection> result = new ArrayList<>();
        legs.forEach((id, list) -> result.add(new Connection(id, list.getFirst().departure(),
                list.getLast().arrival(), summary.get(id)[0], summary.get(id)[1], list)));
        return result;
    }
}
