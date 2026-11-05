CREATE OR REPLACE PACKAGE BODY pkg_bledy AS
    PROCEDURE zglos(p_kod IN PLS_INTEGER, p_komunikat IN VARCHAR2) IS
    BEGIN
        RAISE_APPLICATION_ERROR(p_kod, p_komunikat);
    END zglos;

    PROCEDURE zapisz(p_zrodlo IN VARCHAR2, p_kontekst IN VARCHAR2 DEFAULT NULL) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_kod  NUMBER := SQLCODE;
        v_msg  VARCHAR2(4000) := SUBSTR(SQLERRM, 1, 4000);
        v_stos VARCHAR2(4000) := SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 4000);
    BEGIN
        INSERT INTO dziennik_bledow (zrodlo, kod_bledu, komunikat, stos, kontekst)
        VALUES (p_zrodlo, v_kod, v_msg, v_stos, p_kontekst);
        COMMIT;
    END zapisz;
END pkg_bledy;
/
