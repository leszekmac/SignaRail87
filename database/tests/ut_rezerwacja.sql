CREATE OR REPLACE PACKAGE ut_rezerwacja AS
    --%suite(Sprzedaz biletow)
    --%rollback(auto)

    --%test(Sprzedaz automatycznie wybiera miejsce i wylicza cene)
    PROCEDURE sprzedaz_auto;
    --%test(Zapisuje wszystkie odcinki trasy biletu)
    PROCEDURE zajete_odcinki;
    --%test(To samo miejsce na tym samym odcinku jest odrzucane)
    --%throws(-20011)
    PROCEDURE podwojna_sprzedaz;
    --%test(Czesciowo nakladajace sie odcinki sa konfliktem)
    --%throws(-20011)
    PROCEDURE czesciowe_nalozenie;
    --%test(Stykajace sie odcinki A-B i B-C moga dzielic miejsce)
    PROCEDURE odcinki_stykajace;
    --%test(Wybor automatyczny uzywa miejsca zwolnionego na rozlacznym odcinku)
    PROCEDURE auto_ponownie_uzywa_miejsca;
    --%test(Po wyczerpaniu klasy sprzedaz konczy sie bledem)
    --%throws(-20012)
    PROCEDURE brak_miejsc;
    --%test(Ten sam klucz idempotencji zwraca ten sam bilet)
    PROCEDURE idempotencja;
    --%test(Anulowanie zwalnia miejsce)
    PROCEDURE anulowanie;
    --%test(Anulowanie jest idempotentne)
    PROCEDURE anulowanie_dwukrotne;
    --%test(Miejsce spoza skladu)
    --%throws(-20014)
    PROCEDURE miejsce_spoza_skladu;
    --%test(Kurs odwolany)
    --%throws(-20010)
    PROCEDURE kurs_odwolany;
    --%test(Pociag, ktory juz odjechal)
    --%throws(-20010)
    PROCEDURE po_odjezdzie;
    --%test(Odwrocony kierunek)
    --%throws(-20001)
    PROCEDURE odwrocony_kierunek;
    --%test(Stacja poza trasa)
    --%throws(-20001)
    PROCEDURE stacja_poza_trasa;
    --%test(Brak kontaktu do pasazera)
    --%throws(-20001)
    PROCEDURE brak_kontaktu;
    --%test(Oplata minimalna)
    PROCEDURE oplata_minimalna;
END ut_rezerwacja;
/
CREATE OR REPLACE PACKAGE BODY ut_rezerwacja AS
    -- IC3510 pojutrze: RZE - TRN - KRK - KTW - WRO, wagony 1 (kl. 1) i 2 (kl. 2).
    FUNCTION kurs RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT id_kursu INTO v FROM kursy_rozkladowe WHERE id_pociagu = 1 AND data_kursu = TRUNC(SYSDATE) + 2;
        RETURN v;
    END;

    FUNCTION miejsce RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT id_miejsca INTO v FROM miejsca WHERE id_wagonu = 2 AND nr_miejsca = 1;
        RETURN v;
    END;

    FUNCTION kup(
        p_od VARCHAR2, p_do VARCHAR2, p_miejsce NUMBER DEFAULT NULL, p_klasa NUMBER DEFAULT 2,
        p_klucz VARCHAR2 DEFAULT NULL, p_kurs NUMBER DEFAULT NULL
    ) RETURN NUMBER IS
        v_id NUMBER; v_nr VARCHAR2(20); v_m NUMBER; v_c NUMBER;
    BEGIN
        pkg_rezerwacja.kup_bilet(NVL(p_kurs, kurs), p_od, p_do, 'Jan Testowy', 'jan@example.com', NULL,
            p_miejsce, p_klasa, p_klucz, v_id, v_nr, v_m, v_c);
        RETURN v_id;
    END;

    PROCEDURE sprzedaz_auto IS
        v_id NUMBER; v_nr VARCHAR2(20); v_m NUMBER; v_c NUMBER; v_klasa NUMBER;
    BEGIN
        pkg_rezerwacja.kup_bilet(kurs, 'RZE', 'KRK', 'Anna', 'a@example.com', NULL,
            o_id_rezerwacji => v_id, o_nr_biletu => v_nr, o_id_miejsca => v_m, o_cena => v_c);
        SELECT klasa INTO v_klasa FROM miejsca WHERE id_miejsca = v_m;
        ut.expect(v_klasa).to_equal(2);
        ut.expect(v_c).to_equal(60.04);        -- 158 km * 0,38 zl
        ut.expect(v_nr).to_be_like('SR-%');
    END;

    PROCEDURE zajete_odcinki IS
        v_id NUMBER; v_ile NUMBER;
    BEGIN
        v_id := kup('RZE', 'KTW');
        SELECT COUNT(*) INTO v_ile FROM rezerwacje_odcinki WHERE id_rezerwacji = v_id;
        ut.expect(v_ile).to_equal(3);
    END;

    PROCEDURE podwojna_sprzedaz IS
        v NUMBER;
    BEGIN
        v := kup('RZE', 'KRK', miejsce);
        v := kup('RZE', 'KRK', miejsce);
    END;

    PROCEDURE czesciowe_nalozenie IS
        v NUMBER;
    BEGIN
        v := kup('RZE', 'KRK', miejsce);
        v := kup('TRN', 'KTW', miejsce);
    END;

    PROCEDURE odcinki_stykajace IS
        v1 NUMBER; v2 NUMBER;
    BEGIN
        v1 := kup('RZE', 'KRK', miejsce);
        v2 := kup('KRK', 'WRO', miejsce);
        ut.expect(v2).not_to_equal(v1);
    END;

    PROCEDURE auto_ponownie_uzywa_miejsca IS
        v_a NUMBER; v_b NUMBER; v_ma NUMBER; v_mb NUMBER;
    BEGIN
        v_a := kup('RZE', 'KRK');
        v_b := kup('KRK', 'WRO');
        SELECT id_miejsca INTO v_ma FROM rezerwacje WHERE id_rezerwacji = v_a;
        SELECT id_miejsca INTO v_mb FROM rezerwacje WHERE id_rezerwacji = v_b;
        ut.expect(v_mb).to_equal(v_ma);
    END;

    PROCEDURE brak_miejsc IS
        v NUMBER;
    BEGIN
        FOR i IN 1 .. 61 LOOP       -- w skladzie jest 60 miejsc klasy 2
            v := kup('RZE', 'KRK');
        END LOOP;
    END;

    PROCEDURE idempotencja IS
        v1 NUMBER; v2 NUMBER; v_ile NUMBER;
    BEGIN
        v1 := kup('RZE', 'KRK', p_klucz => 'klucz-1');
        v2 := kup('RZE', 'KRK', p_klucz => 'klucz-1');
        SELECT COUNT(*) INTO v_ile FROM rezerwacje WHERE klucz_idempotencji = 'klucz-1';
        ut.expect(v2).to_equal(v1);
        ut.expect(v_ile).to_equal(1);
    END;

    PROCEDURE anulowanie IS
        v NUMBER; v_nr VARCHAR2(20); v_status VARCHAR2(10);
    BEGIN
        v := kup('RZE', 'KRK', miejsce);
        SELECT nr_biletu INTO v_nr FROM rezerwacje WHERE id_rezerwacji = v;
        pkg_rezerwacja.anuluj_bilet(v_nr);
        SELECT status INTO v_status FROM rezerwacje WHERE id_rezerwacji = v;
        ut.expect(v_status).to_equal('ANULOWANA');
        v := kup('RZE', 'KRK', miejsce);       -- miejsce znow dostepne
        ut.expect(v).to_be_not_null;
    END;

    PROCEDURE anulowanie_dwukrotne IS
        v NUMBER; v_nr VARCHAR2(20); v_ile NUMBER;
    BEGIN
        v := kup('RZE', 'KRK');
        SELECT nr_biletu INTO v_nr FROM rezerwacje WHERE id_rezerwacji = v;
        pkg_rezerwacja.anuluj_bilet(v_nr);
        pkg_rezerwacja.anuluj_bilet(v_nr);
        SELECT COUNT(*) INTO v_ile FROM rezerwacje_odcinki WHERE id_rezerwacji = v;
        ut.expect(v_ile).to_equal(0);
    END;

    PROCEDURE miejsce_spoza_skladu IS
        v NUMBER; v_m NUMBER;
    BEGIN
        SELECT MIN(id_miejsca) INTO v_m FROM miejsca WHERE id_wagonu = 5;
        v := kup('RZE', 'KRK', v_m);
    END;

    PROCEDURE kurs_odwolany IS
        v NUMBER; v_kurs NUMBER := kurs;
    BEGIN
        UPDATE kursy_rozkladowe SET status = 'ODWOLANY' WHERE id_kursu = v_kurs;
        v := kup('RZE', 'KRK');
    END;

    PROCEDURE po_odjezdzie IS
        v NUMBER; v_kurs NUMBER := kurs;
    BEGIN
        UPDATE kursy_postoje SET odjazd = SYSDATE - 1 / 24, przyjazd = SYSDATE - 1 / 24
         WHERE id_kursu = v_kurs AND lp = 1;
        v := kup('RZE', 'KRK');
    END;

    PROCEDURE odwrocony_kierunek IS
        v NUMBER;
    BEGIN
        v := kup('KRK', 'RZE');
    END;

    PROCEDURE stacja_poza_trasa IS
        v NUMBER;
    BEGIN
        v := kup('RZE', 'GDA');
    END;

    PROCEDURE brak_kontaktu IS
        v_id NUMBER; v_nr VARCHAR2(20); v_m NUMBER; v_c NUMBER;
    BEGIN
        pkg_rezerwacja.kup_bilet(kurs, 'RZE', 'KRK', 'Anna', NULL, NULL,
            o_id_rezerwacji => v_id, o_nr_biletu => v_nr, o_id_miejsca => v_m, o_cena => v_c);
    END;

    PROCEDURE oplata_minimalna IS
    BEGIN
        -- Tarnow-Krakow pociagiem IC: 78 km * 0,38 zl = 29,64 zl.
        ut.expect(pkg_rezerwacja.wylicz_cene(kurs, 2, 3, 2)).to_equal(29.64);
        UPDATE taryfy SET oplata_minimalna = 50 WHERE kategoria = 'IC' AND klasa = 2;
        ut.expect(pkg_rezerwacja.wylicz_cene(kurs, 2, 3, 2)).to_equal(50);
    END;
END ut_rezerwacja;
/
