CREATE OR REPLACE PACKAGE ut_h0_ruch AS
    --%suite(Dobor skladu i sterowanie ruchem na makiecie)
    --%rollback(auto)

    --%test(Sklad pokrywa popyt i miesci sie na torze)
    PROCEDURE sklad_standard;
    --%test(Zima: mniejsza predkosc i grzalki rozjazdow na trasie)
    PROCEDURE sklad_zima;
    --%test(Zima obniza uciag, wiec ta sama lokomotywa pociagnie mniej)
    PROCEDURE zima_obniza_uciag;
    --%test(Za krotki tor: brak mozliwego skladu)
    --%throws(-20022)
    PROCEDURE tor_za_krotki;
    --%test(Przekroczenie wydajnosci centrali)
    --%throws(-20023)
    PROCEDURE przeciazenie_centrali;
    --%test(Kursu nie mozna przygotowac dwukrotnie)
    --%throws(-20020)
    PROCEDURE podwojne_przygotowanie;
    --%test(Dwa aktywne kursy nie dziela wagonow ani lokomotywy)
    PROCEDURE brak_wspoldzielenia_taboru;
    --%test(Uruchomienie zamyka przebieg i kolejkuje polecenia we wlasciwej kolejnosci)
    PROCEDURE uruchomienie_kursu;
    --%test(Limit predkosci trasy pochodzi z najwolniejszego bloku)
    PROCEDURE limit_najwolniejszego_bloku;
    --%test(Przebieg przez zajety blok jest odrzucany)
    --%throws(-20025)
    PROCEDURE przebieg_zajety;
    --%test(Awaria szlaku kieruje kurs na objazd)
    PROCEDURE objazd_po_awarii;
    --%test(Brak jakiejkolwiek drogi)
    --%throws(-20024)
    PROCEDURE brak_drogi;
    --%test(S88: przejazd zajmuje i zwalnia bloki, koniec na bloku docelowym)
    PROCEDURE przejazd_s88;
    --%test(S88: zajecie wolnego bloku wywoluje stop awaryjny i anuluje kolejke)
    PROCEDURE nieoczekiwane_zajecie;
    --%test(Awaria makiety opoznia powiazany kurs rozkladowy)
    PROCEDURE awaria_opoznia_kurs_rozkladowy;
    --%test(Audyt zapisuje przelozenie rozjazdu)
    PROCEDURE audyt_rozjazdu;
    --%test(Dziennika powypadkowego nie mozna modyfikowac)
    --%throws(-20990)
    PROCEDURE audyt_niezmienny;
    --%test(Bilans pradu liczy trakcje, oswietlenie, ogrzewanie i grzalki)
    PROCEDURE bilans_pradu;
END ut_h0_ruch;
/
CREATE OR REPLACE PACKAGE BODY ut_h0_ruch AS
    FUNCTION nowy_kurs(
        p_start NUMBER, p_meta NUMBER, p_frekw NUMBER DEFAULT 50, p_pogoda VARCHAR2 DEFAULT 'STANDARD'
    ) RETURN NUMBER IS
        v_id NUMBER;
    BEGIN
        INSERT INTO h0_harmonogram_kursow (identyfikator_rejsu, id_bloku_start, id_bloku_meta, godzina_odjazdu,
                                           prognoza_frekwencji_procent, scenariusz_pogodowy)
        VALUES ('TEST', p_start, p_meta, SYSTIMESTAMP, p_frekw, p_pogoda)
        RETURNING id_kursu INTO v_id;
        RETURN v_id;
    END;

    FUNCTION status_bloku(p_kod VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(30);
    BEGIN
        SELECT status_blokady INTO v FROM h0_bloki_torowe WHERE kod_bloku = p_kod;
        RETURN v;
    END;

    FUNCTION status_kursu(p_id NUMBER) RETURN VARCHAR2 IS
        v VARCHAR2(30);
    BEGIN
        SELECT status_kursu INTO v FROM h0_harmonogram_kursow WHERE id_kursu = p_id;
        RETURN v;
    END;

    PROCEDURE sklad_standard IS
        v_mm NUMBER; v_miejsca NUMBER; v_plan NUMBER; v_loco NUMBER;
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        SELECT k.miejsca_w_skladzie, k.id_lokomotywy INTO v_plan, v_loco
          FROM h0_harmonogram_kursow k WHERE k.id_kursu = 1;
        SELECT SUM(w.dlugosc_ze_sprzegiem_mm), SUM(w.liczba_miejsc) INTO v_mm, v_miejsca
          FROM h0_aktywne_sklady s JOIN h0_wagony w ON w.id_wagonu = s.id_wagonu WHERE s.id_kursu = 1;
        SELECT v_mm + dlugosc_ze_sprzegiem_mm INTO v_mm FROM h0_lokomotywy WHERE id_lokomotywy = v_loco;

        ut.expect(status_kursu(1)).to_equal('PRZYGOTOWANY');
        ut.expect(v_miejsca).to_equal(v_plan);
        ut.expect(v_miejsca).to_be_greater_or_equal(144);       -- 60% z 240
        ut.expect(v_mm).to_be_less_or_equal(1400 - 30);         -- krotszy tor koncowy minus zapas
    END;

    PROCEDURE sklad_zima IS
        v_v NUMBER; v_vmax NUMBER; v_grzeje NUMBER;
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(2);
        SELECT k.predkosc_docelowa_kmh, l.v_max_skalowana INTO v_v, v_vmax
          FROM h0_harmonogram_kursow k JOIN h0_lokomotywy l ON l.id_lokomotywy = k.id_lokomotywy
         WHERE k.id_kursu = 2;
        SELECT COUNT(*) INTO v_grzeje FROM h0_rozjazdy WHERE status_grzania = 'ON';
        ut.expect(v_v).to_equal(TRUNC(v_vmax * 0.7));
        ut.expect(v_grzeje).to_equal(2);                         -- R3 i R4 na trasie, reszta wylaczona
    END;

    PROCEDURE zima_obniza_uciag IS
        v_lato NUMBER; v_zima NUMBER; v_id NUMBER;
    BEGIN
        -- Tylko najslabsza lokomotywa: w zimie jej uciag spada z 700 g do 560 g.
        UPDATE h0_harmonogram_kursow SET id_lokomotywy = NULL WHERE id_kursu IN (1, 2);
        DELETE FROM h0_lokomotywy WHERE id_lokomotywy IN (2, 3);
        v_id := nowy_kurs(1, 6, 100);
        pkg_h0_controller.przygotuj_sklad_makiety(v_id);
        SELECT SUM(w.masa_g) INTO v_lato FROM h0_aktywne_sklady s JOIN h0_wagony w ON w.id_wagonu = s.id_wagonu
         WHERE s.id_kursu = v_id;
        UPDATE h0_harmonogram_kursow SET status_kursu = 'ZAKONCZONY' WHERE id_kursu = v_id;
        v_id := nowy_kurs(1, 6, 100, 'ZIMA');
        pkg_h0_controller.przygotuj_sklad_makiety(v_id);
        SELECT SUM(w.masa_g) INTO v_zima FROM h0_aktywne_sklady s JOIN h0_wagony w ON w.id_wagonu = s.id_wagonu
         WHERE s.id_kursu = v_id;
        ut.expect(v_lato).to_be_greater_than(560);
        ut.expect(v_zima).to_be_less_or_equal(560);
    END;

    PROCEDURE tor_za_krotki IS
    BEGIN
        UPDATE h0_bloki_torowe SET dlugosc_mm = 300 WHERE id_bloku = 6;
        pkg_h0_controller.przygotuj_sklad_makiety(1);
    END;

    PROCEDURE przeciazenie_centrali IS
    BEGIN
        UPDATE h0_centrale SET limit_pradu_ma = 300;
        pkg_h0_controller.przygotuj_sklad_makiety(1);
    END;

    PROCEDURE podwojne_przygotowanie IS
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.przygotuj_sklad_makiety(1);
    END;

    PROCEDURE brak_wspoldzielenia_taboru IS
        v_dupl NUMBER; v_loco NUMBER;
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.przygotuj_sklad_makiety(2);
        SELECT COUNT(*) INTO v_dupl FROM (
            SELECT id_wagonu FROM h0_aktywne_sklady GROUP BY id_wagonu HAVING COUNT(*) > 1);
        SELECT COUNT(DISTINCT id_lokomotywy) INTO v_loco FROM h0_harmonogram_kursow WHERE id_kursu IN (1, 2);
        ut.expect(v_dupl).to_equal(0);
        ut.expect(v_loco).to_equal(2);
    END;

    PROCEDURE uruchomienie_kursu IS
        v_typy VARCHAR2(200);
    BEGIN
        UPDATE h0_rozjazdy SET polozenie_aktualne = 'ZWROTNA' WHERE kod_rozjazdu = 'R2';
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.uruchom_kurs(1);

        ut.expect(status_kursu(1)).to_equal('W_TRASIE');
        ut.expect(status_bloku('ST_A_T1')).to_equal('PRZEBIEG');
        ut.expect(status_bloku('SZLAK_1')).to_equal('PRZEBIEG');
        ut.expect(status_bloku('ST_B_T1')).to_equal('PRZEBIEG');
        ut.expect(status_bloku('OBJAZD')).to_equal('WOLNY');

        SELECT LISTAGG(typ_polecenia, ',') WITHIN GROUP (ORDER BY id_zadania) INTO v_typy
          FROM h0_kolejka_dcc WHERE id_kursu = 1;
        -- Rozjazd musi byc przelozony przed ruszeniem lokomotywy.
        ut.expect(v_typy).to_equal('ROZJAZD,FUNKCJA,PREDKOSC');
    END;

    PROCEDURE limit_najwolniejszego_bloku IS
        v_ramka VARCHAR2(40); v_adres NUMBER;
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.uruchom_kurs(1);
        SELECT ramka_hex, adres_dcc INTO v_ramka, v_adres FROM h0_kolejka_dcc
         WHERE id_kursu = 1 AND typ_polecenia = 'PREDKOSC';
        ut.expect(v_ramka).to_equal(pkg_h0_controller.ramka_predkosci(v_adres, 60)); -- tory stacyjne: krok 60
    END;

    PROCEDURE przebieg_zajety IS
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        UPDATE h0_bloki_torowe SET status_blokady = 'ZAJETY' WHERE kod_bloku = 'ST_B_T1';
        pkg_h0_controller.uruchom_kurs(1);
    END;

    PROCEDURE objazd_po_awarii IS
        v_ile NUMBER;
    BEGIN
        UPDATE h0_bloki_torowe SET status_blokady = 'ZABLOKOWANY_AWARYJNIE' WHERE kod_bloku = 'SZLAK_1';
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.uruchom_kurs(1);
        ut.expect(status_bloku('OBJAZD')).to_equal('PRZEBIEG');
        SELECT COUNT(*) INTO v_ile FROM h0_rozjazdy WHERE kod_rozjazdu = 'R1' AND polozenie_aktualne = 'ZWROTNA';
        ut.expect(v_ile).to_equal(1);
    END;

    PROCEDURE brak_drogi IS
    BEGIN
        UPDATE h0_bloki_torowe SET status_blokady = 'ZABLOKOWANY_AWARYJNIE' WHERE kod_bloku IN ('SZLAK_1', 'OBJAZD');
        pkg_h0_controller.przygotuj_sklad_makiety(1);
    END;

    PROCEDURE przejazd_s88 IS
        v_ostatnia VARCHAR2(200);
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.uruchom_kurs(1);
        pkg_h0_controller.zglos_s88(1, 'T');
        pkg_h0_controller.zglos_s88(3, 'T');
        pkg_h0_controller.zglos_s88(1, 'N');
        ut.expect(status_bloku('ST_A_T1')).to_equal('WOLNY');
        ut.expect(status_bloku('SZLAK_1')).to_equal('ZAJETY');
        ut.expect(status_kursu(1)).to_equal('W_TRASIE');
        pkg_h0_controller.zglos_s88(6, 'T');
        ut.expect(status_kursu(1)).to_equal('ZAKONCZONY');

        SELECT opis INTO v_ostatnia FROM h0_kolejka_dcc
         WHERE id_zadania = (SELECT MAX(id_zadania) FROM h0_kolejka_dcc WHERE id_kursu = 1);
        ut.expect(v_ostatnia).to_be_like('%Stop%');
    END;

    PROCEDURE nieoczekiwane_zajecie IS
        v_stop NUMBER; v_nowe NUMBER;
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.uruchom_kurs(1);
        pkg_h0_controller.zglos_s88(4, 'T');                    -- SZLAK_2 nie nalezy do przebiegu
        ut.expect(status_bloku('SZLAK_2')).to_equal('ZABLOKOWANY_AWARYJNIE');
        SELECT COUNT(*) INTO v_stop FROM h0_kolejka_dcc WHERE typ_polecenia = 'STOP_AWAR' AND ramka_hex = '00 71 71';
        SELECT COUNT(*) INTO v_nowe FROM h0_kolejka_dcc WHERE status = 'NOWE' AND typ_polecenia <> 'STOP_AWAR';
        ut.expect(v_stop).to_equal(1);
        ut.expect(v_nowe).to_equal(0);
    END;

    PROCEDURE awaria_opoznia_kurs_rozkladowy IS
        v_status VARCHAR2(10); v_min NUMBER;
    BEGIN
        pkg_h0_controller.przygotuj_sklad_makiety(1);
        pkg_h0_controller.uruchom_kurs(1);
        pkg_h0_controller.zglos_s88(4, 'T');
        SELECT status, opoznienie_min INTO v_status, v_min FROM kursy_rozkladowe WHERE id_kursu_h0 = 1;
        ut.expect(v_status).to_equal('OPOZNIONY');
        ut.expect(v_min).to_equal(15);
    END;

    PROCEDURE audyt_rozjazdu IS
        v_ile NUMBER;
    BEGIN
        UPDATE h0_rozjazdy SET polozenie_aktualne = 'ZWROTNA' WHERE kod_rozjazdu = 'R3';
        SELECT COUNT(*) INTO v_ile FROM h0_audyt_infrastruktury
         WHERE kod_obiektu = 'R3' AND wartosc_przed = 'PROSTO' AND wartosc_po = 'ZWROTNA';
        ut.expect(v_ile).to_equal(1);
    END;

    PROCEDURE audyt_niezmienny IS
    BEGIN
        UPDATE h0_rozjazdy SET polozenie_aktualne = 'ZWROTNA' WHERE kod_rozjazdu = 'R3';
        DELETE FROM h0_audyt_infrastruktury;
    END;

    PROCEDURE bilans_pradu IS
        v_przed NUMBER; v_po NUMBER; v_oczekiwany NUMBER;
    BEGIN
        v_przed := pkg_h0_controller.bilans_pradu_ma;
        pkg_h0_controller.przygotuj_sklad_makiety(2);           -- ZIMA
        v_po := pkg_h0_controller.bilans_pradu_ma;
        SELECT l.max_pobor_pradu_ma
               + (SELECT SUM(w.pobor_oswietlenia_ma + 40)
                    FROM h0_aktywne_sklady s JOIN h0_wagony w ON w.id_wagonu = s.id_wagonu
                   WHERE s.id_kursu = 2)
               + 2 * 120
          INTO v_oczekiwany
          FROM h0_harmonogram_kursow k JOIN h0_lokomotywy l ON l.id_lokomotywy = k.id_lokomotywy
         WHERE k.id_kursu = 2;
        ut.expect(v_po - v_przed).to_equal(v_oczekiwany);
    END;
END ut_h0_ruch;
/
