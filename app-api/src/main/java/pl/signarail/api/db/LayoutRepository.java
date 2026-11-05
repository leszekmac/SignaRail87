package pl.signarail.api.db;

import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import pl.signarail.api.model.ApiModels.DccCommand;
import pl.signarail.api.model.ApiModels.LayoutCourse;
import pl.signarail.api.model.ApiModels.PowerBudget;
import pl.signarail.api.model.ApiModels.TrackBlock;

@Repository
public class LayoutRepository {

    private final JdbcTemplate jdbc;

    public LayoutRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void prepare(long courseId) {
        jdbc.update("{call pkg_h0_controller.przygotuj_sklad_makiety(?)}", courseId);
    }

    public void start(long courseId) {
        jdbc.update("{call pkg_h0_controller.uruchom_kurs(?)}", courseId);
    }

    public List<TrackBlock> blocks() {
        return jdbc.query("""
                SELECT kod_bloku, dlugosc_mm, status_blokady, id_kursu_przebiegu
                  FROM h0_bloki_torowe ORDER BY id_bloku""",
                (rs, i) -> new TrackBlock(rs.getString(1), rs.getInt(2), rs.getString(3),
                        rs.getObject(4, Long.class)));
    }

    public List<LayoutCourse> courses() {
        return jdbc.query("""
                SELECT id_kursu, identyfikator_rejsu, status_kursu, scenariusz_pogodowy,
                       id_lokomotywy, predkosc_docelowa_kmh, miejsca_w_skladzie
                  FROM h0_harmonogram_kursow ORDER BY id_kursu""",
                (rs, i) -> new LayoutCourse(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4),
                        rs.getObject(5, Long.class), rs.getObject(6, Integer.class), rs.getObject(7, Integer.class)));
    }

    public List<DccCommand> commands(int limit) {
        return jdbc.query("""
                SELECT id_zadania, id_kursu, typ_polecenia, ramka_hex, opis, status
                  FROM h0_kolejka_dcc ORDER BY id_zadania DESC FETCH FIRST ? ROWS ONLY""",
                (rs, i) -> new DccCommand(rs.getLong(1), rs.getObject(2, Long.class), rs.getString(3),
                        rs.getString(4), rs.getString(5), rs.getString(6)), limit);
    }

    public PowerBudget power() {
        return jdbc.queryForObject("""
                SELECT pkg_h0_controller.bilans_pradu_ma, (SELECT SUM(limit_pradu_ma) FROM h0_centrale)
                  FROM dual""",
                (rs, i) -> new PowerBudget(rs.getInt(1), rs.getInt(2)));
    }
}
