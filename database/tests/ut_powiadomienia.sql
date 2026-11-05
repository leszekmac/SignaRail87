CREATE OR REPLACE PACKAGE ut_powiadomienia AS
    --%suite(Skrzynka powiadomien)
    --%rollback(auto)

    --%beforeeach
    PROCEDURE przygotuj;

    --%test(Partia rezerwuje wiersze: drugi odczyt ich nie dostaje)
    PROCEDURE rezerwacja_partii;
    --%test(Potwierdzenie konczy obsluge)
    PROCEDURE potwierdzenie;
    --%test(Odrzucenie planuje ponowienie z odstepem)
    PROCEDURE ponowienie;
    --%test(Po wyczerpaniu prob wiersz trafia do martwych)
    PROCEDURE martwe;
    --%test(Po wygasnieciu dzierzawy wiersz wraca do kolejki)
    PROCEDURE dzierzawa;
END ut_powiadomienia;
/
CREATE OR REPLACE PACKAGE BODY ut_powiadomienia AS
    g_id NUMBER;

    PROCEDURE przygotuj IS
        v_kurs NUMBER; v_id NUMBER; v_nr VARCHAR2(20); v_m NUMBER; v_c NUMBER; v NUMBER;
    BEGIN
        SELECT id_kursu INTO v_kurs FROM kursy_rozkladowe WHERE id_pociagu = 1 AND data_kursu = TRUNC(SYSDATE) + 3;
        pkg_rezerwacja.kup_bilet(v_kurs, 'RZE', 'KRK', 'P', 'p@example.com', NULL,
            o_id_rezerwacji => v_id, o_nr_biletu => v_nr, o_id_miejsca => v_m, o_cena => v_c);
        pkg_rozklad.zglos_opoznienie(v_kurs, 10, NULL, v);
        SELECT id_powiadomienia INTO g_id FROM powiadomienia WHERE id_rezerwacji = v_id;
    END;

    FUNCTION pobierz RETURN NUMBER IS
        c SYS_REFCURSOR;
        v_id NUMBER; v_k VARCHAR2(5); v_o VARCHAR2(120); v_t VARCHAR2(400); v_p NUMBER;
        v_ile NUMBER := 0;
    BEGIN
        pkg_powiadomienia.pobierz_partie(10, c);
        LOOP
            FETCH c INTO v_id, v_k, v_o, v_t, v_p;
            EXIT WHEN c%NOTFOUND;
            v_ile := v_ile + 1;
        END LOOP;
        CLOSE c;
        RETURN v_ile;
    END;

    FUNCTION status RETURN VARCHAR2 IS
        v VARCHAR2(8);
    BEGIN
        SELECT p.status INTO v FROM powiadomienia p WHERE id_powiadomienia = g_id;
        RETURN v;
    END;

    PROCEDURE rezerwacja_partii IS
    BEGIN
        ut.expect(pobierz).to_equal(1);
        ut.expect(pobierz).to_equal(0);
        ut.expect(status).to_equal('W_TOKU');
    END;

    PROCEDURE potwierdzenie IS
        v NUMBER;
    BEGIN
        v := pobierz;
        pkg_powiadomienia.potwierdz(g_id);
        ut.expect(status).to_equal('WYSLANE');
    END;

    PROCEDURE ponowienie IS
        v NUMBER; v_term TIMESTAMP;
    BEGIN
        v := pobierz;
        pkg_powiadomienia.odrzuc(g_id, 'bramka SMS niedostepna');
        SELECT nastepna_proba INTO v_term FROM powiadomienia WHERE id_powiadomienia = g_id;
        ut.expect(status).to_equal('NOWE');
        ut.expect(v_term > SYSTIMESTAMP).to_be_true;
    END;

    PROCEDURE martwe IS
        v NUMBER;
    BEGIN
        UPDATE powiadomienia SET proby = pkg_powiadomienia.c_max_prob WHERE id_powiadomienia = g_id;
        pkg_powiadomienia.odrzuc(g_id, 'trwaly blad');
        ut.expect(status).to_equal('MARTWE');
        ut.expect(pobierz).to_equal(0);
    END;

    PROCEDURE dzierzawa IS
        v NUMBER;
    BEGIN
        v := pobierz;
        UPDATE powiadomienia SET nastepna_proba = SYSTIMESTAMP - INTERVAL '1' SECOND
         WHERE id_powiadomienia = g_id;
        ut.expect(pobierz).to_equal(1);
    END;
END ut_powiadomienia;
/
