package pl.signarail.api;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.SQLException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.UncategorizedSQLException;
import pl.signarail.api.web.ApiExceptionHandler;

class ApiExceptionHandlerTest {

    private final ApiExceptionHandler handler = new ApiExceptionHandler();

    private static UncategorizedSQLException oracleError(int code, String message) {
        return new UncategorizedSQLException("call", "sql", new SQLException(message, "72000", code));
    }

    @ParameterizedTest
    @CsvSource({"20001,400", "20002,404", "20011,409", "20012,409", "20013,423", "20014,422", "20023,409"})
    void mapsBusinessCodesToHttpStatus(int oraCode, int httpStatus) {
        ProblemDetail problem = handler.handleDatabaseError(oracleError(oraCode, "ORA-" + oraCode + ": blad"));
        assertThat(problem.getStatus()).isEqualTo(httpStatus);
    }

    @Test
    void hidesPlsqlStackFromClient() {
        ProblemDetail problem = handler.handleDatabaseError(oracleError(20011,
                "ORA-20011: Miejsce 5 jest zajete\nORA-06512: at \"SIGNARAIL.PKG_REZERWACJA\", line 80"));
        assertThat(problem.getDetail()).isEqualTo("Miejsce 5 jest zajete");
    }

    @Test
    void unknownDatabaseErrorDoesNotLeakDetails() {
        ProblemDetail problem = handler.handleDatabaseError(oracleError(942, "ORA-00942: table does not exist"));
        assertThat(problem.getStatus()).isEqualTo(500);
        assertThat(problem.getDetail()).doesNotContain("ORA-");
    }
}
