CREATE OR REPLACE PACKAGE BODY pkg_h0_controller AS

    TYPE t_bajty IS TABLE OF PLS_INTEGER;
    TYPE t_wagon IS RECORD (
        id_wagonu NUMBER, dlugosc NUMBER, masa NUMBER, miejsca NUMBER
    );
    TYPE t_wagony IS TABLE OF t_wagon;
    TYPE t_liczby IS TABLE OF NUMBER;

    -- ---------------------------------------------------------------- ramki DCC

    FUNCTION bxor(a PLS_INTEGER, b PLS_INTEGER) RETURN PLS_INTEGER IS
    BEGIN
        RETURN a + b - 2 * BITAND(a, b);
    END bxor;

    -- Ostatni bajt pakietu to XOR wszystkich poprzednich (error detection byte).
    FUNCTION zloz(p_bajty t_bajty) RETURN VARCHAR2 IS
        v_xor   PLS_INTEGER := 0;
        v_wynik VARCHAR2(40);
    BEGIN
        FOR i IN 1 .. p_bajty.COUNT LOOP
            v_xor := bxor(v_xor, p_bajty(i));
            v_wynik := v_wynik || TO_CHAR(p_bajty(i), 'FM0X') || ' ';
        END LOOP;
        RETURN v_wynik || TO_CHAR(v_xor, 'FM0X');
    END zloz;

    FUNCTION bajty_adresu(p_adres NUMBER) RETURN t_bajty IS
    BEGIN
        IF p_adres BETWEEN 1 AND 127 THEN
            RETURN t_bajty(p_adres);
        ELSIF p_adres BETWEEN 128 AND 10239 THEN
            RETURN t_bajty(192 + TRUNC(p_adres / 256), MOD(p_adres, 256));
        END IF;
        pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Adres DCC poza zakresem: ' || p_adres);
    END bajty_adresu;

    FUNCTION ramka_predkosci(p_adres IN NUMBER, p_krok IN NUMBER, p_kierunek IN VARCHAR2 DEFAULT 'P') RETURN VARCHAR2 IS
        v_bajty t_bajty := bajty_adresu(p_adres);
    BEGIN
        IF p_krok NOT BETWEEN 0 AND 126 OR p_kierunek NOT IN ('P', 'T') THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Krok 0-126, kierunek P lub T');
        END IF;
        v_bajty.EXTEND(2);
        v_bajty(v_bajty.COUNT - 1) := 63;    -- 0x3F: instrukcja 128 krokow
        -- Wartosc 0 = stop, 1 = stop awaryjny, wiec krok n koduje sie jako n + 1.
        v_bajty(v_bajty.COUNT) := CASE p_kierunek WHEN 'P' THEN 128 ELSE 0 END
                                  + CASE WHEN p_krok = 0 THEN 0 ELSE p_krok + 1 END;
        RETURN zloz(v_bajty);
    END ramka_predkosci;

    FUNCTION ramka_funkcji(p_adres IN NUMBER, p_f0 IN BOOLEAN, p_f1 IN BOOLEAN) RETURN VARCHAR2 IS
        v_bajty t_bajty := bajty_adresu(p_adres);
    BEGIN
        v_bajty.EXTEND;
        -- Grupa 1: 100D DDDD, bit 4 = F0, bit 0 = F1.
        v_bajty(v_bajty.COUNT) := 128 + CASE WHEN p_f0 THEN 16 ELSE 0 END + CASE WHEN p_f1 THEN 1 ELSE 0 END;
        RETURN zloz(v_bajty);
    END ramka_funkcji;

    FUNCTION ramka_rozjazdu(p_adres IN NUMBER, p_polozenie IN VARCHAR2) RETURN VARCHAR2 IS
        v_baza    PLS_INTEGER;
        v_dekoder PLS_INTEGER;
        v_para    PLS_INTEGER;
        v_gorne   PLS_INTEGER;
    BEGIN
        IF p_adres NOT BETWEEN 1 AND 2044 OR p_polozenie NOT IN ('PROSTO', 'ZWROTNA') THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Bledny adres akcesorium lub polozenie');
        END IF;
        -- Adres uzytkownika 1..2044 -> 9-bitowy adres dekodera i para wyjsc 0-3.
        v_baza    := p_adres - 1;
        v_dekoder := TRUNC(v_baza / 4) + 1;
        v_para    := MOD(v_baza, 4);
        -- Gorne 3 bity adresu sa w drugim bajcie w negacji bitowej.
        v_gorne   := 7 - TRUNC(v_dekoder / 64);
        RETURN zloz(t_bajty(
            128 + MOD(v_dekoder, 64),
            128 + v_gorne * 16 + 8 + v_para * 2 + CASE p_polozenie WHEN 'PROSTO' THEN 1 ELSE 0 END
        ));
    END ramka_rozjazdu;

    FUNCTION ramka_stopu_awaryjnego RETURN VARCHAR2 IS
    BEGIN
        -- Adres rozgloszeniowy 0 i pakiet 0 1 D C 0 0 0 S (C=1 ignoruj kierunek, S=1 natychmiast).
        RETURN zloz(t_bajty(0, 113));
    END ramka_stopu_awaryjnego;

    FUNCTION ramka_na_bity(p_hex IN VARCHAR2) RETURN VARCHAR2 IS
        v_wynik VARCHAR2(200) := RPAD('1', 14, '1');
        v_bajt  PLS_INTEGER;
        v_i     PLS_INTEGER := 1;
        v_bity  VARCHAR2(8);
    BEGIN
        LOOP
            EXIT WHEN v_i > LENGTH(p_hex);
            v_bajt := TO_NUMBER(SUBSTR(p_hex, v_i, 2), 'XX');
            v_bity := NULL;
            FOR b IN REVERSE 0 .. 7 LOOP
                v_bity := v_bity || CASE WHEN BITAND(v_bajt, POWER(2, b)) > 0 THEN '1' ELSE '0' END;
            END LOOP;
            v_wynik := v_wynik || '0' || v_bity;
            v_i := v_i + 3;
        END LOOP;
        RETURN v_wynik || '1';
    END ramka_na_bity;

    FUNCTION krok_dla_predkosci(p_kmh NUMBER, p_vmax NUMBER) RETURN PLS_INTEGER IS
    BEGIN
        IF p_kmh <= 0 THEN
            RETURN 0;
        END IF;
        RETURN LEAST(126, GREATEST(1, ROUND(p_kmh * 126 / p_vmax)));
    END krok_dla_predkosci;

    FUNCTION wygeneruj_ramke_dcc(
        p_lokomotywa_id IN NUMBER,
        p_predkosc      IN NUMBER,
        p_kierunek      IN VARCHAR2 DEFAULT 'P'
    ) RETURN VARCHAR2 IS
        v_adres h0_lokomotywy.adres_dcc_loco%TYPE;
        v_vmax  h0_lokomotywy.v_max_skalowana%TYPE;
    BEGIN
        IF p_predkosc IS NULL OR p_predkosc < 0 THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Predkosc nie moze byc ujemna');
        END IF;
        SELECT adres_dcc_loco, v_max_skalowana INTO v_adres, v_vmax
          FROM h0_lokomotywy WHERE id_lokomotywy = p_lokomotywa_id;
        RETURN ramka_predkosci(v_adres, krok_dla_predkosci(p_predkosc, v_vmax), p_kierunek);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma lokomotywy ' || p_lokomotywa_id);
    END wygeneruj_ramke_dcc;

    PROCEDURE do_kolejki(p_kurs NUMBER, p_typ VARCHAR2, p_adres NUMBER, p_ramka VARCHAR2, p_opis VARCHAR2) IS
    BEGIN
        INSERT INTO h0_kolejka_dcc (id_kursu, typ_polecenia, adres_dcc, ramka_hex, opis)
        VALUES (p_kurs, p_typ, p_adres, p_ramka, p_opis);
    END do_kolejki;

    -- ------------------------------------------------------------ bilans pradu

    FUNCTION bilans_pradu_ma(p_dodatkowy_kurs_id IN NUMBER DEFAULT NULL) RETURN NUMBER IS
        v_wynik NUMBER;
    BEGIN
        WITH aktywne AS (
            SELECT k.id_kursu, k.id_lokomotywy, k.scenariusz_pogodowy
              FROM h0_harmonogram_kursow k
             WHERE k.status_kursu IN ('PRZYGOTOWANY', 'W_TRASIE')
                OR k.id_kursu = p_dodatkowy_kurs_id
        ), trakcja AS (
            SELECT NVL(SUM(l.max_pobor_pradu_ma), 0) ma
              FROM aktywne a JOIN h0_lokomotywy l ON l.id_lokomotywy = a.id_lokomotywy
        ), wagony AS (
            SELECT NVL(SUM(w.pobor_oswietlenia_ma + pol.dodatek_pradu_wagon_ma), 0) ma
              FROM aktywne a
              JOIN h0_aktywne_sklady s ON s.id_kursu = a.id_kursu
              JOIN h0_wagony w ON w.id_wagonu = s.id_wagonu
              JOIN h0_polityki_pogodowe pol ON pol.scenariusz_pogodowy = a.scenariusz_pogodowy
             WHERE w.kategoria = 'PASAZERSKI'
        ), grzanie AS (
            SELECT NVL(SUM(pobor_grzalki_ma), 0) ma FROM h0_rozjazdy WHERE status_grzania = 'ON'
        )
        SELECT t.ma + w.ma + g.ma INTO v_wynik FROM trakcja t, wagony w, grzanie g;
        RETURN v_wynik;
    END bilans_pradu_ma;

    -- ------------------------------------------------------------------- trasa

    -- Najkrotsza sciezka w grafie torow z pominieciem blokow po awarii.
    PROCEDURE wyznacz_przebieg(p_kurs NUMBER, p_start NUMBER, p_meta NUMBER) IS
        v_sciezka VARCHAR2(4000);
        v_pop     NUMBER;
        v_nast    NUMBER;
        v_lp      PLS_INTEGER := 1;
        v_poz     PLS_INTEGER := 2;
        v_kon     PLS_INTEGER;
    BEGIN
        DELETE FROM h0_przebiegi WHERE id_kursu = p_kurs;

        BEGIN
            WITH trasa (id_bloku, suma_mm, sciezka) AS (
                SELECT id_bloku, dlugosc_mm, '/' || id_bloku || '/'
                  FROM h0_bloki_torowe WHERE id_bloku = p_start
                UNION ALL
                SELECT p.id_bloku_do, t.suma_mm + b.dlugosc_mm, t.sciezka || p.id_bloku_do || '/'
                  FROM trasa t
                  JOIN h0_polaczenia_blokow p ON p.id_bloku_z = t.id_bloku
                  JOIN h0_bloki_torowe b ON b.id_bloku = p.id_bloku_do
                 WHERE t.id_bloku <> p_meta
                   AND b.status_blokady <> 'ZABLOKOWANY_AWARYJNIE'
                   AND INSTR(t.sciezka, '/' || p.id_bloku_do || '/') = 0
            )
            SELECT sciezka INTO v_sciezka
              FROM (SELECT sciezka FROM trasa WHERE id_bloku = p_meta ORDER BY suma_mm)
             WHERE ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_brak_przebiegu, 'Brak drogi dla kursu ' || p_kurs);
        END;

        LOOP
            v_kon := INSTR(v_sciezka, '/', v_poz);
            EXIT WHEN v_kon = 0;
            v_nast := TO_NUMBER(SUBSTR(v_sciezka, v_poz, v_kon - v_poz));
            IF v_pop IS NULL THEN
                INSERT INTO h0_przebiegi (id_kursu, kolejnosc, id_bloku)
                VALUES (p_kurs, v_lp, v_nast);
            ELSE
                INSERT INTO h0_przebiegi (id_kursu, kolejnosc, id_bloku, id_rozjazdu, wymagane_polozenie)
                SELECT p_kurs, v_lp, v_nast, p.id_rozjazdu, p.wymagane_polozenie
                  FROM h0_polaczenia_blokow p
                 WHERE p.id_bloku_z = v_pop AND p.id_bloku_do = v_nast;
            END IF;
            v_pop := v_nast;
            v_lp  := v_lp + 1;
            v_poz := v_kon + 1;
        END LOOP;
    END wyznacz_przebieg;

    -- ------------------------------------------------------------- dobor skladu

    -- Zachlannie po pojemnosci na milimetr. Wagony zawsze sa sprawdzane pojedynczo:
    -- ten, ktory sie nie miesci, nie konczy doboru, bo krotszy moze jeszcze wejsc.
    PROCEDURE dobierz_wagony(
        p_wagony t_wagony, p_limit_mm NUMBER, p_limit_g NUMBER, p_cel_miejsc NUMBER,
        o_wybor OUT t_liczby, o_miejsca OUT NUMBER
    ) IS
        v_mm NUMBER := p_limit_mm;
        v_g  NUMBER := p_limit_g;
    BEGIN
        o_wybor := t_liczby();
        o_miejsca := 0;
        FOR i IN 1 .. p_wagony.COUNT LOOP
            EXIT WHEN o_miejsca >= p_cel_miejsc AND o_wybor.COUNT > 0;
            IF p_wagony(i).dlugosc <= v_mm AND p_wagony(i).masa <= v_g THEN
                o_wybor.EXTEND;
                o_wybor(o_wybor.COUNT) := p_wagony(i).id_wagonu;
                v_mm := v_mm - p_wagony(i).dlugosc;
                v_g  := v_g  - p_wagony(i).masa;
                o_miejsca := o_miejsca + p_wagony(i).miejsca;
            END IF;
        END LOOP;
    END dobierz_wagony;

    PROCEDURE przygotuj_sklad_makiety(p_kurs_id IN NUMBER) IS
        v_kurs     h0_harmonogram_kursow%ROWTYPE;
        v_pol      h0_polityki_pogodowe%ROWTYPE;
        v_tor_mm   NUMBER;
        v_cel      NUMBER;
        v_wagony   t_wagony;
        v_wybor    t_liczby;
        v_miejsca  NUMBER;
        v_naj_loco NUMBER;
        v_naj_v    NUMBER;
        v_naj_wybor t_liczby;
        v_naj_miejsca NUMBER := -1;
        v_limit_ma NUMBER;
        v_pobor    NUMBER;
    BEGIN
        BEGIN
            SELECT * INTO v_kurs FROM h0_harmonogram_kursow WHERE id_kursu = p_kurs_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma kursu ' || p_kurs_id);
        END;
        IF v_kurs.status_kursu <> 'PLANOWANY' THEN
            pkg_bledy.zglos(pkg_bledy.c_stan_kursu,
                'Kurs ' || p_kurs_id || ' ma status ' || v_kurs.status_kursu);
        END IF;

        -- Blokada centrali szereguje przydzialy: dwa kursy nie przekrocza razem bilansu.
        v_limit_ma := 0;
        FOR c IN (SELECT limit_pradu_ma FROM h0_centrale FOR UPDATE) LOOP
            v_limit_ma := v_limit_ma + c.limit_pradu_ma;
        END LOOP;

        SELECT * INTO v_pol FROM h0_polityki_pogodowe
         WHERE scenariusz_pogodowy = v_kurs.scenariusz_pogodowy;

        SELECT MIN(dlugosc_mm) - c_zapas_toru_mm INTO v_tor_mm
          FROM h0_bloki_torowe WHERE id_bloku IN (v_kurs.id_bloku_start, v_kurs.id_bloku_meta);

        v_cel := CEIL(v_kurs.popyt_bazowy_miejsc * v_kurs.prognoza_frekwencji_procent / 100);

        wyznacz_przebieg(p_kurs_id, v_kurs.id_bloku_start, v_kurs.id_bloku_meta);

        -- Wolne wagony pasazerskie, najpojemniejsze na milimetr toru.
        SELECT w.id_wagonu, w.dlugosc_ze_sprzegiem_mm, w.masa_g, w.liczba_miejsc
          BULK COLLECT INTO v_wagony
          FROM h0_wagony w
         WHERE w.kategoria = 'PASAZERSKI'
           AND NOT EXISTS (
                 SELECT 1 FROM h0_aktywne_sklady s
                   JOIN h0_harmonogram_kursow k ON k.id_kursu = s.id_kursu
                  WHERE s.id_wagonu = w.id_wagonu
                    AND k.status_kursu IN ('PRZYGOTOWANY', 'W_TRASIE'))
         ORDER BY w.liczba_miejsc / w.dlugosc_ze_sprzegiem_mm DESC, w.id_wagonu
           FOR UPDATE OF w.id_wagonu;

        -- Od najoszczedniejszej: pierwsza spelniajaca popyt lokomotywa konczy poszukiwania.
        FOR l IN (
            SELECT lo.id_lokomotywy, lo.dlugosc_ze_sprzegiem_mm dl, lo.max_uciag_g, lo.v_max_skalowana
              FROM h0_lokomotywy lo
             WHERE lo.dlugosc_ze_sprzegiem_mm < v_tor_mm
               AND NOT EXISTS (
                     SELECT 1 FROM h0_harmonogram_kursow k
                      WHERE k.id_lokomotywy = lo.id_lokomotywy
                        AND k.status_kursu IN ('PRZYGOTOWANY', 'W_TRASIE'))
             ORDER BY lo.max_pobor_pradu_ma, lo.id_lokomotywy
        ) LOOP
            dobierz_wagony(v_wagony, v_tor_mm - l.dl, l.max_uciag_g * v_pol.mnoznik_uciagu,
                           v_cel, v_wybor, v_miejsca);
            IF v_miejsca > v_naj_miejsca AND v_wybor.COUNT > 0 THEN
                v_naj_loco := l.id_lokomotywy;
                v_naj_v := l.v_max_skalowana;
                v_naj_wybor := v_wybor;
                v_naj_miejsca := v_miejsca;
            END IF;
            EXIT WHEN v_naj_miejsca >= v_cel;
        END LOOP;

        IF v_naj_loco IS NULL THEN
            SELECT COUNT(*) INTO v_miejsca FROM h0_lokomotywy;
            IF v_miejsca = 0 THEN
                pkg_bledy.zglos(pkg_bledy.c_brak_lokomotywy, 'Brak lokomotyw w ewidencji');
            END IF;
            pkg_bledy.zglos(pkg_bledy.c_sklad_za_dlugi,
                'Zaden sklad nie miesci sie na torze (' || v_tor_mm || ' mm) lub brak wolnego taboru');
        END IF;

        UPDATE h0_harmonogram_kursow
           SET id_lokomotywy = v_naj_loco,
               status_kursu = 'PRZYGOTOWANY',
               miejsca_w_skladzie = v_naj_miejsca,
               predkosc_docelowa_kmh = TRUNC(v_naj_v * v_pol.mnoznik_predkosci)
         WHERE id_kursu = p_kurs_id;

        FOR i IN 1 .. v_naj_wybor.COUNT LOOP
            INSERT INTO h0_aktywne_sklady (id_kursu, id_wagonu, pozycja_w_skladzie)
            VALUES (p_kurs_id, v_naj_wybor(i), i);
        END LOOP;

        IF v_pol.grzanie_rozjazdow = 'T' THEN
            UPDATE h0_rozjazdy SET status_grzania = 'ON'
             WHERE id_rozjazdu IN (SELECT id_rozjazdu FROM h0_przebiegi WHERE id_kursu = p_kurs_id);
        END IF;

        v_pobor := bilans_pradu_ma;
        IF v_pobor > v_limit_ma THEN
            -- Wyjatek bez lokalnego wycofania: wolajacy robi ROLLBACK calej transakcji.
            pkg_bledy.zglos(pkg_bledy.c_przeciazenie_pradu,
                'Bilans ' || v_pobor || ' mA przekracza wydajnosc centrali ' || v_limit_ma || ' mA');
        END IF;
    END przygotuj_sklad_makiety;

    -- --------------------------------------------------------------- uruchomienie

    PROCEDURE uruchom_kurs(p_kurs_id IN NUMBER) IS
        v_kurs    h0_harmonogram_kursow%ROWTYPE;
        v_loco    h0_lokomotywy%ROWTYPE;
        v_krok    NUMBER;
        v_blok    t_liczby;
        v_status  SYS.ODCIVARCHAR2LIST;
        v_oswietl PLS_INTEGER;
        v_kmh     NUMBER;
    BEGIN
        BEGIN
            SELECT * INTO v_kurs FROM h0_harmonogram_kursow WHERE id_kursu = p_kurs_id FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma kursu ' || p_kurs_id);
        END;
        IF v_kurs.status_kursu <> 'PRZYGOTOWANY' THEN
            pkg_bledy.zglos(pkg_bledy.c_stan_kursu,
                'Kurs ' || p_kurs_id || ' ma status ' || v_kurs.status_kursu);
        END IF;

        -- Stan toru mogl sie zmienic od przygotowania skladu.
        wyznacz_przebieg(p_kurs_id, v_kurs.id_bloku_start, v_kurs.id_bloku_meta);

        -- Staly porzadek blokad (po id) wyklucza zakleszczenie krzyzujacych sie przebiegow.
        SELECT b.id_bloku, b.status_blokady BULK COLLECT INTO v_blok, v_status
          FROM h0_bloki_torowe b
         WHERE b.id_bloku IN (SELECT id_bloku FROM h0_przebiegi WHERE id_kursu = p_kurs_id)
         ORDER BY b.id_bloku
           FOR UPDATE;
        FOR i IN 1 .. v_blok.COUNT LOOP
            IF v_status(i) <> 'WOLNY' THEN
                pkg_bledy.zglos(pkg_bledy.c_przebieg_zajety,
                    'Blok ' || v_blok(i) || ' ma status ' || v_status(i));
            END IF;
        END LOOP;

        UPDATE h0_bloki_torowe
           SET status_blokady = 'PRZEBIEG', id_kursu_przebiegu = p_kurs_id
         WHERE id_bloku IN (SELECT id_bloku FROM h0_przebiegi WHERE id_kursu = p_kurs_id);

        FOR r IN (
            SELECT r.id_rozjazdu, r.kod_rozjazdu, r.adres_dcc_akces, r.polozenie_aktualne, p.wymagane_polozenie
              FROM h0_przebiegi p JOIN h0_rozjazdy r ON r.id_rozjazdu = p.id_rozjazdu
             WHERE p.id_kursu = p_kurs_id
             ORDER BY p.kolejnosc
        ) LOOP
            IF r.polozenie_aktualne <> r.wymagane_polozenie THEN
                UPDATE h0_rozjazdy SET polozenie_aktualne = r.wymagane_polozenie
                 WHERE id_rozjazdu = r.id_rozjazdu;
                do_kolejki(p_kurs_id, 'ROZJAZD', r.adres_dcc_akces,
                    ramka_rozjazdu(r.adres_dcc_akces, r.wymagane_polozenie),
                    'Rozjazd ' || r.kod_rozjazdu || ' -> ' || r.wymagane_polozenie);
            END IF;
        END LOOP;

        SELECT * INTO v_loco FROM h0_lokomotywy WHERE id_lokomotywy = v_kurs.id_lokomotywy;

        SELECT COUNT(*) INTO v_oswietl
          FROM h0_aktywne_sklady s JOIN h0_wagony w ON w.id_wagonu = s.id_wagonu
         WHERE s.id_kursu = p_kurs_id AND w.wymaga_oswietlenia = 'T';
        do_kolejki(p_kurs_id, 'FUNKCJA', v_loco.adres_dcc_loco,
            ramka_funkcji(v_loco.adres_dcc_loco, TRUE, v_oswietl > 0),
            'Adres lokomotywy: ' || v_loco.adres_dcc_loco || ' -> Wlacz swiatla czolowe (F0)'
            || CASE WHEN v_oswietl > 0 THEN ' -> Wlacz oswietlenie wagonow (F1)' END);

        -- Limit trasy to najwolniejszy blok przebiegu.
        SELECT MIN(b.max_predkosc_dcc) INTO v_krok
          FROM h0_przebiegi p JOIN h0_bloki_torowe b ON b.id_bloku = p.id_bloku
         WHERE p.id_kursu = p_kurs_id;
        v_krok := LEAST(v_krok, krok_dla_predkosci(v_kurs.predkosc_docelowa_kmh, v_loco.v_max_skalowana));
        v_kmh  := ROUND(v_krok * v_loco.v_max_skalowana / 126);

        do_kolejki(p_kurs_id, 'PREDKOSC', v_loco.adres_dcc_loco,
            ramka_predkosci(v_loco.adres_dcc_loco, v_krok),
            'Adres lokomotywy: ' || v_loco.adres_dcc_loco || ' -> Ustaw predkosc: ' || v_kmh
            || ' km/h (skalowane do 1:87)');

        UPDATE h0_harmonogram_kursow SET status_kursu = 'W_TRASIE' WHERE id_kursu = p_kurs_id;
    END uruchom_kurs;

    -- ------------------------------------------------------------- sprzezenie S88

    PROCEDURE stop_awaryjny(p_blok NUMBER, p_kod VARCHAR2) IS
        v_ile NUMBER;
    BEGIN
        UPDATE h0_bloki_torowe SET status_blokady = 'ZABLOKOWANY_AWARYJNIE' WHERE id_bloku = p_blok;
        -- Niewyslane polecenia ruchu sa nieaktualne; stop nie moze czekac za nimi w kolejce.
        UPDATE h0_kolejka_dcc SET status = 'ANULOWANE'
         WHERE CASE WHEN status = 'NOWE' THEN id_zadania END IS NOT NULL;
        do_kolejki(NULL, 'STOP_AWAR', NULL, ramka_stopu_awaryjnego,
            'STOP AWARYJNY: nieoczekiwane zajecie bloku ' || p_kod);

        FOR k IN (
            SELECT kr.id_kursu
              FROM h0_harmonogram_kursow h
              JOIN kursy_rozkladowe kr ON kr.id_kursu_h0 = h.id_kursu
             WHERE h.status_kursu = 'W_TRASIE'
        ) LOOP
            pkg_rozklad.zglos_opoznienie(k.id_kursu, 15, 'Awaria na szlaku, blok ' || p_kod, v_ile);
        END LOOP;
    END stop_awaryjny;

    PROCEDURE zakoncz_kurs(p_kurs NUMBER) IS
        v_loco h0_lokomotywy%ROWTYPE;
    BEGIN
        SELECT l.* INTO v_loco
          FROM h0_lokomotywy l
          JOIN h0_harmonogram_kursow k ON k.id_lokomotywy = l.id_lokomotywy
         WHERE k.id_kursu = p_kurs;
        do_kolejki(p_kurs, 'PREDKOSC', v_loco.adres_dcc_loco,
            ramka_predkosci(v_loco.adres_dcc_loco, 0),
            'Adres lokomotywy: ' || v_loco.adres_dcc_loco || ' -> Stop na torze docelowym');
        UPDATE h0_harmonogram_kursow SET status_kursu = 'ZAKONCZONY' WHERE id_kursu = p_kurs;
        -- Grzalka zostaje wlaczona, dopoki korzysta z niej inny aktywny kurs.
        UPDATE h0_rozjazdy r SET status_grzania = 'OFF'
         WHERE status_grzania = 'ON'
           AND id_rozjazdu IN (SELECT id_rozjazdu FROM h0_przebiegi WHERE id_kursu = p_kurs)
           AND NOT EXISTS (
                 SELECT 1 FROM h0_przebiegi p
                   JOIN h0_harmonogram_kursow k ON k.id_kursu = p.id_kursu
                  WHERE p.id_rozjazdu = r.id_rozjazdu
                    AND k.status_kursu IN ('PRZYGOTOWANY', 'W_TRASIE'));
    END zakoncz_kurs;

    PROCEDURE zglos_s88(p_adres_s88 IN NUMBER, p_zajety IN VARCHAR2) IS
        v_blok h0_bloki_torowe%ROWTYPE;
        v_meta NUMBER;
    BEGIN
        IF p_zajety NOT IN ('T', 'N') THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'p_zajety musi wynosic T lub N');
        END IF;
        BEGIN
            SELECT * INTO v_blok FROM h0_bloki_torowe WHERE adres_s88 = p_adres_s88 FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nieznany czujnik S88: ' || p_adres_s88);
        END;

        IF p_zajety = 'T' THEN
            IF v_blok.status_blokady = 'PRZEBIEG' THEN
                UPDATE h0_bloki_torowe SET status_blokady = 'ZAJETY' WHERE id_bloku = v_blok.id_bloku;
                SELECT id_bloku_meta INTO v_meta FROM h0_harmonogram_kursow
                 WHERE id_kursu = v_blok.id_kursu_przebiegu;
                IF v_meta = v_blok.id_bloku THEN
                    zakoncz_kurs(v_blok.id_kursu_przebiegu);
                END IF;
            ELSIF v_blok.status_blokady = 'WOLNY' THEN
                stop_awaryjny(v_blok.id_bloku, v_blok.kod_bloku);
            END IF;
        ELSIF v_blok.status_blokady = 'ZAJETY' THEN
            UPDATE h0_bloki_torowe SET status_blokady = 'WOLNY', id_kursu_przebiegu = NULL
             WHERE id_bloku = v_blok.id_bloku;
        END IF;
    END zglos_s88;

    PROCEDURE odblokuj_blok(p_kod_bloku IN VARCHAR2) IS
    BEGIN
        UPDATE h0_bloki_torowe SET status_blokady = 'WOLNY', id_kursu_przebiegu = NULL
         WHERE kod_bloku = p_kod_bloku AND status_blokady = 'ZABLOKOWANY_AWARYJNIE';
        IF SQL%ROWCOUNT = 0 THEN
            pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Blok ' || p_kod_bloku || ' nie jest zablokowany');
        END IF;
    END odblokuj_blok;
END pkg_h0_controller;
/
