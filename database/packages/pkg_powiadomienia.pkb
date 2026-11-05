CREATE OR REPLACE PACKAGE BODY pkg_powiadomienia AS

    PROCEDURE pobierz_partie(p_limit IN PLS_INTEGER, o_wynik OUT SYS_REFCURSOR) IS
        CURSOR c IS
            SELECT id_powiadomienia
              FROM powiadomienia
             WHERE CASE WHEN status IN ('NOWE', 'W_TOKU') THEN nastepna_proba END <= SYSTIMESTAMP
               FOR UPDATE SKIP LOCKED;
        v_id SYS.ODCINUMBERLIST;
    BEGIN
        OPEN c;
        FETCH c BULK COLLECT INTO v_id LIMIT p_limit;
        CLOSE c;

        FORALL i IN 1 .. v_id.COUNT
            UPDATE powiadomienia
               SET status = 'W_TOKU',
                   proby = proby + 1,
                   nastepna_proba = SYSTIMESTAMP + NUMTODSINTERVAL(c_dzierzawa_s, 'SECOND')
             WHERE id_powiadomienia = v_id(i);

        OPEN o_wynik FOR
            SELECT p.id_powiadomienia, p.kanal, p.odbiorca, p.tresc, p.proby
              FROM powiadomienia p
             WHERE p.id_powiadomienia IN (SELECT column_value FROM TABLE(v_id));
    END pobierz_partie;

    PROCEDURE potwierdz(p_id IN NUMBER) IS
    BEGIN
        UPDATE powiadomienia
           SET status = 'WYSLANE', wyslano = SYSTIMESTAMP, ostatni_blad = NULL
         WHERE id_powiadomienia = p_id;
    END potwierdz;

    PROCEDURE odrzuc(p_id IN NUMBER, p_blad IN VARCHAR2) IS
    BEGIN
        UPDATE powiadomienia
           SET status = CASE WHEN proby >= c_max_prob THEN 'MARTWE' ELSE 'NOWE' END,
               nastepna_proba = SYSTIMESTAMP + NUMTODSINTERVAL(POWER(2, proby), 'SECOND'),
               ostatni_blad = SUBSTR(p_blad, 1, 200)
         WHERE id_powiadomienia = p_id;
    END odrzuc;
END pkg_powiadomienia;
/
