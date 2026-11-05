CREATE OR REPLACE PACKAGE ut_rozklad AS
    --%suite(Wyszukiwanie polaczen i opoznienia)
    --%rollback(auto)

    --%test(Polaczenie bezposrednie)
    PROCEDURE bezposrednie;
    --%test(Trasa z dwiema przesiadkami)
    PROCEDURE dwie_przesiadki;
    --%test(Limit przesiadek odcina trase)
    PROCEDURE limit_przesiadek;
    --%test(Za krotka przesiadka nie jest proponowana)
    PROCEDURE min_czas_przesiadki;
    --%test(Kurs odwolany nie bierze udzialu w wyszukiwaniu)
    PROCEDURE kurs_odwolany;
    --%test(Polaczenie zdominowane jest odrzucane)
    PROCEDURE dominacja;
    --%test(Kilka pociagow tej samej relacji w kolejnosci odjazdow)
    PROCEDURE kolejne_polaczenia;
    --%test(Brak polaczenia to pusty wynik, nie blad)
    PROCEDURE brak_polaczenia;
    --%test(Nieznana stacja)
    --%throws(-20002)
    PROCEDURE nieznana_stacja;
    --%test(Te same stacje)
    --%throws(-20001)
    PROCEDURE te_same_stacje;
    --%test(Generowanie kursow jest powtarzalne)
    PROCEDURE generator_idempotentny;
    --%test(Opoznienie tworzy powiadomienia na kazdym kanale pasazera)
    PROCEDURE opoznienie_powiadomienia;
    --%test(Ponowne zgloszenie tej samej wartosci nie dubluje wiadomosci)
    PROCEDURE opoznienie_bez_duplikatow;
    --%test(Bilety anulowane nie sa powiadamiane)
    PROCEDURE opoznienie_bez_anulowanych;
    --%test(Wyzerowanie opoznienia przywraca status planowy)
    PROCEDURE opoznienie_zero;
END ut_rozklad;
/
CREATE OR REPLACE PACKAGE BODY ut_rozklad AS
    FUNCTION szukaj(p_od VARCHAR2, p_do VARCHAR2, p_godz NUMBER DEFAULT 0, p_przes NUMBER DEFAULT 2)
    RETURN t_odcinki_polaczenia IS
        v_c SYS_REFCURSOR;
        v_w t_odcinki_polaczenia := t_odcinki_polaczenia();
        v_r t_odcinek_polaczenia := t_odcinek_polaczenia(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    BEGIN
        pkg_rozklad.znajdz_polaczenie(p_od, p_do, TRUNC(SYSDATE) + 2 + p_godz / 24, p_przes, 5, v_c);
        LOOP
            FETCH v_c INTO v_r.id_polaczenia, v_r.nr_odcinka, v_r.id_kursu, v_r.numer_pociagu, v_r.kategoria,
                v_r.kod_od, v_r.stacja_od, v_r.odjazd, v_r.kod_do, v_r.stacja_do, v_r.przyjazd,
                v_r.przesiadki, v_r.czas_podrozy_min;
            EXIT WHEN v_c%NOTFOUND;
            v_w.EXTEND;
            v_w(v_w.COUNT) := v_r;
        END LOOP;
        CLOSE v_c;
        RETURN v_w;
    END;

    FUNCTION trasa(p_w t_odcinki_polaczenia, p_id NUMBER DEFAULT 1) RETURN VARCHAR2 IS
        v VARCHAR2(200);
    BEGIN
        FOR i IN 1 .. p_w.COUNT LOOP
            IF p_w(i).id_polaczenia = p_id THEN
                v := v || p_w(i).numer_pociagu || ':' || p_w(i).kod_od || '-' || p_w(i).kod_do || ' ';
            END IF;
        END LOOP;
        RETURN TRIM(v);
    END;

    FUNCTION kurs_pociagu(p_nr VARCHAR2) RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT k.id_kursu INTO v FROM kursy_rozkladowe k JOIN pociagi p ON p.id_pociagu = k.id_pociagu
         WHERE p.numer_pociagu = p_nr AND k.data_kursu = TRUNC(SYSDATE) + 2;
        RETURN v;
    END;

    FUNCTION sprzedaj(p_email VARCHAR2, p_tel VARCHAR2) RETURN VARCHAR2 IS
        v_id NUMBER; v_nr VARCHAR2(20); v_m NUMBER; v_c NUMBER;
    BEGIN
        pkg_rezerwacja.kup_bilet(kurs_pociagu('IC3510'), 'RZE', 'KRK', 'Pasazer', p_email, p_tel,
            o_id_rezerwacji => v_id, o_nr_biletu => v_nr, o_id_miejsca => v_m, o_cena => v_c);
        RETURN v_nr;
    END;

    PROCEDURE bezposrednie IS
        v t_odcinki_polaczenia := szukaj('RZE', 'KRK', 5);
    BEGIN
        ut.expect(trasa(v)).to_equal('IC3510:RZE-KRK');
        ut.expect(v(1).przesiadki).to_equal(0);
        ut.expect(v(1).czas_podrozy_min).to_equal(105);
    END;

    PROCEDURE dwie_przesiadki IS
        v t_odcinki_polaczenia := szukaj('RZE', 'GDA', 5);
    BEGIN
        ut.expect(trasa(v)).to_equal('IC3510:RZE-KRK TLK1610:KRK-WAW EIP4100:WAW-GDA');
        ut.expect(v(1).przesiadki).to_equal(2);
    END;

    PROCEDURE limit_przesiadek IS
    BEGIN
        ut.expect(szukaj('RZE', 'GDA', 5, 1).COUNT).to_equal(0);
    END;

    PROCEDURE min_czas_przesiadki IS
        v_tlk NUMBER := kurs_pociagu('TLK1610');
    BEGIN
        -- Przyjazd IC3510 do Krakowa 07:45, TLK odjezdza 08:15 (zapas 30 min).
        ut.expect(szukaj('RZE', 'WAW', 5).COUNT).to_equal(2);
        -- 5 minut na przesiadke to mniej niz wymagane minimum.
        UPDATE kursy_postoje
           SET przyjazd = TRUNC(SYSDATE) + 2 + 7.75 / 24 + 5 / 1440,
               odjazd   = TRUNC(SYSDATE) + 2 + 7.75 / 24 + 5 / 1440
         WHERE id_kursu = v_tlk AND lp = 1;
        ut.expect(szukaj('RZE', 'WAW', 5).COUNT).to_equal(0);
    END;

    PROCEDURE kurs_odwolany IS
        v t_odcinki_polaczenia;
        v_kurs NUMBER := kurs_pociagu('IC3510');
    BEGIN
        UPDATE kursy_rozkladowe SET status = 'ODWOLANY' WHERE id_kursu = v_kurs;
        v := szukaj('RZE', 'KRK', 5);
        ut.expect(trasa(v)).to_equal('IC3512:RZE-KRK');
    END;

    PROCEDURE dominacja IS
        v t_odcinki_polaczenia := szukaj('TRN', 'WAW', 5);
    BEGIN
        -- Regionalny 05:30 + TLK trafia na ten sam TLK co IC 06:54, wiec przegrywa.
        ut.expect(trasa(v)).to_equal('IC3510:TRN-KRK TLK1610:KRK-WAW');
        ut.expect(trasa(v, 2)).to_be_null;
    END;

    PROCEDURE kolejne_polaczenia IS
        v t_odcinki_polaczenia := szukaj('RZE', 'KTW', 5);
    BEGIN
        ut.expect(trasa(v, 1)).to_equal('IC3510:RZE-KTW');
        ut.expect(trasa(v, 2)).to_equal('IC3512:RZE-KTW');
    END;

    PROCEDURE brak_polaczenia IS
    BEGIN
        ut.expect(szukaj('GDA', 'RZE', 5).COUNT).to_equal(0);
    END;

    PROCEDURE nieznana_stacja IS
        v t_odcinki_polaczenia;
    BEGIN
        v := szukaj('XXX', 'RZE');
    END;

    PROCEDURE te_same_stacje IS
        v t_odcinki_polaczenia;
    BEGIN
        v := szukaj('RZE', 'RZE');
    END;

    PROCEDURE generator_idempotentny IS
        v_przed NUMBER; v_po NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_przed FROM kursy_postoje;
        pkg_rozklad.generuj_kursy(TRUNC(SYSDATE), TRUNC(SYSDATE) + 5);
        SELECT COUNT(*) INTO v_po FROM kursy_postoje;
        ut.expect(v_po).to_equal(v_przed);
    END;

    PROCEDURE opoznienie_powiadomienia IS
        v_nr VARCHAR2(20); v_ile NUMBER; v_kanaly NUMBER;
    BEGIN
        v_nr := sprzedaj('a@example.com', '+48500100200');
        v_nr := sprzedaj('b@example.com', NULL);
        pkg_rozklad.zglos_opoznienie(kurs_pociagu('IC3510'), 25, 'Awaria rozjazdu', v_ile);
        SELECT COUNT(DISTINCT kanal) INTO v_kanaly FROM powiadomienia;
        ut.expect(v_ile).to_equal(3);
        ut.expect(v_kanaly).to_equal(2);
    END;

    PROCEDURE opoznienie_bez_duplikatow IS
        v_nr VARCHAR2(20); v1 NUMBER; v2 NUMBER;
    BEGIN
        v_nr := sprzedaj('a@example.com', NULL);
        pkg_rozklad.zglos_opoznienie(kurs_pociagu('IC3510'), 25, NULL, v1);
        pkg_rozklad.zglos_opoznienie(kurs_pociagu('IC3510'), 25, NULL, v2);
        ut.expect(v1).to_equal(1);
        ut.expect(v2).to_equal(0);
    END;

    PROCEDURE opoznienie_bez_anulowanych IS
        v_nr VARCHAR2(20); v NUMBER;
    BEGIN
        v_nr := sprzedaj('a@example.com', NULL);
        pkg_rezerwacja.anuluj_bilet(v_nr);
        pkg_rozklad.zglos_opoznienie(kurs_pociagu('IC3510'), 25, NULL, v);
        ut.expect(v).to_equal(0);
    END;

    PROCEDURE opoznienie_zero IS
        v NUMBER; v_status VARCHAR2(10); v_kurs NUMBER := kurs_pociagu('IC3510');
    BEGIN
        pkg_rozklad.zglos_opoznienie(v_kurs, 25, NULL, v);
        pkg_rozklad.zglos_opoznienie(v_kurs, 0, NULL, v);
        SELECT status INTO v_status FROM kursy_rozkladowe WHERE id_kursu = v_kurs;
        ut.expect(v_status).to_equal('PLANOWY');
    END;
END ut_rozklad;
/
