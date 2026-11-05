package pl.signarail.api.web;

import java.sql.SQLException;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/** Tlumaczy kody bledow z PKG_BLEDY na RFC 9457. */
@RestControllerAdvice
public class ApiExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    private static final Map<Integer, HttpStatus> STATUS_BY_ORA_CODE = Map.ofEntries(
            Map.entry(20001, HttpStatus.BAD_REQUEST),
            Map.entry(20002, HttpStatus.NOT_FOUND),
            Map.entry(20010, HttpStatus.CONFLICT),
            Map.entry(20011, HttpStatus.CONFLICT),
            Map.entry(20012, HttpStatus.CONFLICT),
            Map.entry(20013, HttpStatus.LOCKED),
            Map.entry(20014, HttpStatus.UNPROCESSABLE_ENTITY),
            Map.entry(20020, HttpStatus.CONFLICT),
            Map.entry(20021, HttpStatus.CONFLICT),
            Map.entry(20022, HttpStatus.CONFLICT),
            Map.entry(20023, HttpStatus.CONFLICT),
            Map.entry(20024, HttpStatus.CONFLICT),
            Map.entry(20025, HttpStatus.CONFLICT));

    @ExceptionHandler(DataAccessException.class)
    public ProblemDetail handleDatabaseError(DataAccessException e) {
        SQLException sql = findSqlException(e);
        HttpStatus status = sql == null ? null : STATUS_BY_ORA_CODE.get(sql.getErrorCode());
        if (status == null) {
            // Szczegoly techniczne zostaja w logu, nie w odpowiedzi.
            log.error("Nieobsluzony blad bazy danych", e);
            return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, "Blad przetwarzania zadania");
        }
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, businessMessage(sql));
        problem.setProperty("errorCode", "ORA-" + sql.getErrorCode());
        return problem;
    }

    private static SQLException findSqlException(Throwable e) {
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof SQLException sql) {
                return sql;
            }
        }
        return null;
    }

    /** Komunikat ORA niesie stos wywolan PL/SQL; klient dostaje tylko pierwsza linie bez prefiksu. */
    static String businessMessage(SQLException e) {
        String first = e.getMessage().lines().findFirst().orElse("");
        return first.replaceFirst("^ORA-\\d+:\\s*", "");
    }
}
