CREATE OR REPLACE PACKAGE BODY pkg_rezerwacja AS

    e_timeout_blokady EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_timeout_blokady, -30006);

    TYPE t_odcinek IS RECORD (
        id_stacji_od NUMBER, id_stacji_do NUMBER, lp_od NUMBER, lp_do NUMBER, id_pociagu NUMBER
    );

    FUNCTION konflikt(p_id_kursu NUMBER, p_id_miejsca NUMBER, p_lp_od NUMBER, p_lp_do NUMBER)
    RETURN BOOLEAN IS
        v_ile PLS_INTEGER;
    BEGIN
        SELECT COUNT(*) INTO v_ile
          FROM rezerwacje_odcinki
         WHERE id_kursu = p_id_kursu
           AND id_miejsca = p_id_miejsca
           AND lp_odcinka >= p_lp_od
           AND lp_odcinka < p_lp_do;
        RETURN v_ile > 0;
    END konflikt;

    FUNCTION sprawdz_kurs(p_id_kursu NUMBER, p_od VARCHAR2, p_do VARCHAR2) RETURN t_odcinek IS
        v_wynik  t_odcinek;
        v_status kursy_rozkladowe.status%TYPE;
        v_odjazd DATE;
    BEGIN
        BEGIN
            SELECT status, id_pociagu INTO v_status, v_wynik.id_pociagu
              FROM kursy_rozkladowe WHERE id_kursu = p_id_kursu;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma kursu ' || p_id_kursu);
        END;
        IF v_status = 'ODWOLANY' THEN
            pkg_bledy.zglos(pkg_bledy.c_kurs_niedostepny, 'Kurs ' || p_id_kursu || ' zostal odwolany');
        END IF;

        BEGIN
            SELECT s_od.id_stacji, s_do.id_stacji, p_od_r.lp, p_do_r.lp, p_od_r.odjazd
              INTO v_wynik.id_stacji_od, v_wynik.id_stacji_do, v_wynik.lp_od, v_wynik.lp_do, v_odjazd
              FROM stacje s_od
              JOIN kursy_postoje p_od_r ON p_od_r.id_stacji = s_od.id_stacji AND p_od_r.id_kursu = p_id_kursu
              JOIN stacje s_do ON s_do.kod_stacji = p_do
              JOIN kursy_postoje p_do_r ON p_do_r.id_stacji = s_do.id_stacji AND p_do_r.id_kursu = p_id_kursu
             WHERE s_od.kod_stacji = p_od;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane,
                    'Kurs ' || p_id_kursu || ' nie zatrzymuje sie na ' || p_od || ' lub ' || p_do);
        END;

        IF v_wynik.lp_od >= v_wynik.lp_do THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Stacja docelowa musi byc po stacji poczatkowej');
        END IF;
        IF v_odjazd <= SYSDATE THEN
            pkg_bledy.zglos(pkg_bledy.c_kurs_niedostepny, 'Pociag odjechal juz ze stacji ' || p_od);
        END IF;
        RETURN v_wynik;
    END sprawdz_kurs;

    -- Wskazane miejsce: czekamy krotko na blokade, potem nowe zapytanie o konflikt.
    FUNCTION zablokuj_wskazane(
        p_id_kursu NUMBER, p_id_pociagu NUMBER, p_id_miejsca NUMBER, p_lp_od NUMBER, p_lp_do NUMBER
    ) RETURN NUMBER IS
        v_klasa   NUMBER;
    BEGIN
        BEGIN
            SELECT m.klasa INTO v_klasa
              FROM miejsca m
              JOIN pociagi_wagony pw ON pw.id_wagonu = m.id_wagonu
             WHERE m.id_miejsca = p_id_miejsca AND pw.id_pociagu = p_id_pociagu
               FOR UPDATE OF m.id_miejsca WAIT 3; -- rowne c_limit_czekania_s; WAIT wymaga literalu
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_miejsce_poza_kursem,
                    'Miejsce ' || p_id_miejsca || ' nie nalezy do skladu tego kursu');
        END;
        -- Dopiero TA instrukcja widzi rezerwacje zatwierdzona przez sesje, na ktora
        -- czekalismy: w READ COMMITTED kazde zapytanie ma wlasny obraz danych.
        IF konflikt(p_id_kursu, p_id_miejsca, p_lp_od, p_lp_do) THEN
            pkg_bledy.zglos(pkg_bledy.c_miejsce_zajete,
                'Miejsce ' || p_id_miejsca || ' jest zajete na tym odcinku');
        END IF;
        RETURN v_klasa;
    END zablokuj_wskazane;

    -- Wybor automatyczny: SKIP LOCKED pozwala rownoleglym klientom brac rozne miejsca
    -- zamiast ustawiac sie w kolejce do tego samego wiersza. ROWNUM/FETCH FIRST nie
    -- moga tu ograniczac wyniku, bo limit dziala przed pomijaniem blokad.
    FUNCTION zablokuj_dowolne(
        p_id_kursu NUMBER, p_id_pociagu NUMBER, p_klasa NUMBER, p_lp_od NUMBER, p_lp_do NUMBER
    ) RETURN NUMBER IS
        CURSOR c_wolne IS
            SELECT m.id_miejsca
              FROM miejsca m
              JOIN pociagi_wagony pw ON pw.id_wagonu = m.id_wagonu
             WHERE pw.id_pociagu = p_id_pociagu
               AND m.klasa = p_klasa
               AND NOT EXISTS (
                     SELECT 1 FROM rezerwacje_odcinki ro
                      WHERE ro.id_kursu = p_id_kursu
                        AND ro.id_miejsca = m.id_miejsca
                        AND ro.lp_odcinka >= p_lp_od
                        AND ro.lp_odcinka < p_lp_do)
             ORDER BY pw.nr_wagonu, m.nr_miejsca
               FOR UPDATE OF m.id_miejsca SKIP LOCKED;
        v_id NUMBER;
    BEGIN
        OPEN c_wolne;
        LOOP
            FETCH c_wolne INTO v_id;
            EXIT WHEN c_wolne%NOTFOUND;
            -- NOT EXISTS kursora liczy sie z obrazu sprzed blokady, a rezerwacja obcej
            -- sesji nie zmienia wiersza MIEJSCA. Trzeba sprawdzic ponownie.
            EXIT WHEN NOT konflikt(p_id_kursu, v_id, p_lp_od, p_lp_do);
            v_id := NULL;
        END LOOP;
        CLOSE c_wolne;
        RETURN v_id;
    EXCEPTION
        WHEN OTHERS THEN
            IF c_wolne%ISOPEN THEN CLOSE c_wolne; END IF;
            RAISE;
    END zablokuj_dowolne;

    FUNCTION wylicz_cene(
        p_id_kursu IN NUMBER, p_lp_od IN NUMBER, p_lp_do IN NUMBER, p_klasa IN NUMBER
    ) RETURN NUMBER IS
        v_cena NUMBER;
    BEGIN
        SELECT ROUND(GREATEST(t.oplata_minimalna, t.stawka_km * (d.km_od_startu - o.km_od_startu)), 2)
          INTO v_cena
          FROM kursy_rozkladowe k
          JOIN pociagi p ON p.id_pociagu = k.id_pociagu
          JOIN taryfy t ON t.kategoria = p.kategoria AND t.klasa = p_klasa
          JOIN kursy_postoje o ON o.id_kursu = k.id_kursu AND o.lp = p_lp_od
          JOIN kursy_postoje d ON d.id_kursu = k.id_kursu AND d.lp = p_lp_do
         WHERE k.id_kursu = p_id_kursu;
        RETURN v_cena;
    END wylicz_cene;

    FUNCTION znajdz_po_kluczu(
        p_klucz VARCHAR2, o_id OUT NUMBER, o_nr OUT VARCHAR2, o_miejsce OUT NUMBER, o_cena OUT NUMBER
    ) RETURN BOOLEAN IS
    BEGIN
        SELECT id_rezerwacji, nr_biletu, id_miejsca, cena INTO o_id, o_nr, o_miejsce, o_cena
          FROM rezerwacje WHERE klucz_idempotencji = p_klucz;
        RETURN TRUE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
    END znajdz_po_kluczu;

    PROCEDURE kup_bilet(
        p_id_kursu           IN  NUMBER,
        p_kod_stacji_od      IN  VARCHAR2,
        p_kod_stacji_do      IN  VARCHAR2,
        p_pasazer            IN  VARCHAR2,
        p_email              IN  VARCHAR2,
        p_telefon            IN  VARCHAR2,
        p_id_miejsca         IN  NUMBER   DEFAULT NULL,
        p_klasa              IN  NUMBER   DEFAULT 2,
        p_klucz_idempotencji IN  VARCHAR2 DEFAULT NULL,
        o_id_rezerwacji      OUT NUMBER,
        o_nr_biletu          OUT VARCHAR2,
        o_id_miejsca         OUT NUMBER,
        o_cena               OUT NUMBER
    ) IS
        v_odc   t_odcinek;
        v_klasa NUMBER := p_klasa;
    BEGIN
        IF TRIM(p_pasazer) IS NULL OR (p_email IS NULL AND p_telefon IS NULL) THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Wymagane: pasazer oraz e-mail lub telefon');
        END IF;
        IF p_klasa NOT IN (1, 2) THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Klasa musi wynosic 1 lub 2');
        END IF;

        IF p_klucz_idempotencji IS NOT NULL
           AND znajdz_po_kluczu(p_klucz_idempotencji, o_id_rezerwacji, o_nr_biletu, o_id_miejsca, o_cena) THEN
            RETURN;
        END IF;

        v_odc := sprawdz_kurs(p_id_kursu, p_kod_stacji_od, p_kod_stacji_do);

        IF p_id_miejsca IS NOT NULL THEN
            v_klasa := zablokuj_wskazane(p_id_kursu, v_odc.id_pociagu, p_id_miejsca, v_odc.lp_od, v_odc.lp_do);
            o_id_miejsca := p_id_miejsca;
        ELSE
            o_id_miejsca := zablokuj_dowolne(p_id_kursu, v_odc.id_pociagu, p_klasa, v_odc.lp_od, v_odc.lp_do);
            IF o_id_miejsca IS NULL THEN
                pkg_bledy.zglos(pkg_bledy.c_brak_miejsc,
                    'Brak wolnych miejsc w klasie ' || p_klasa || ' na tym odcinku');
            END IF;
        END IF;

        o_cena := wylicz_cene(p_id_kursu, v_odc.lp_od, v_odc.lp_do, v_klasa);
        o_nr_biletu := 'SR-' || TO_CHAR(SYSDATE, 'YYMMDD') || '-'
                       || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0, 1e10))), 10, '0');

        INSERT INTO rezerwacje (
            nr_biletu, id_kursu, id_miejsca, id_stacji_od, id_stacji_do, lp_od, lp_do,
            pasazer, email, telefon, cena, klucz_idempotencji
        ) VALUES (
            o_nr_biletu, p_id_kursu, o_id_miejsca, v_odc.id_stacji_od, v_odc.id_stacji_do,
            v_odc.lp_od, v_odc.lp_do, TRIM(p_pasazer), p_email, p_telefon, o_cena, p_klucz_idempotencji
        ) RETURNING id_rezerwacji INTO o_id_rezerwacji;

        INSERT INTO rezerwacje_odcinki (id_kursu, id_miejsca, lp_odcinka, id_rezerwacji)
        SELECT p_id_kursu, o_id_miejsca, v_odc.lp_od + LEVEL - 1, o_id_rezerwacji
          FROM dual
        CONNECT BY LEVEL <= v_odc.lp_do - v_odc.lp_od;

    EXCEPTION
        WHEN e_timeout_blokady THEN
            pkg_bledy.zglos(pkg_bledy.c_miejsce_blokowane,
                'Miejsce jest wlasnie sprzedawane innemu klientowi, sprobuj ponownie');
        WHEN DUP_VAL_ON_INDEX THEN
            -- Wyscig o klucz idempotencji rozstrzyga indeks unikalny. Blokada czeka tu na
            -- zakonczenie pierwszej transakcji, wiec ponowny odczyt widzi jej wynik.
            IF p_klucz_idempotencji IS NOT NULL
               AND znajdz_po_kluczu(p_klucz_idempotencji, o_id_rezerwacji, o_nr_biletu, o_id_miejsca, o_cena) THEN
                RETURN;
            END IF;
            pkg_bledy.zapisz('PKG_REZERWACJA.KUP_BILET', 'kurs=' || p_id_kursu || ' miejsce=' || o_id_miejsca);
            pkg_bledy.zglos(pkg_bledy.c_miejsce_zajete, 'Miejsce zostalo sprzedane w tym samym momencie');
        WHEN OTHERS THEN
            -- Powtorka zadania moze przegrac blokade z wlasnym, wczesniejszym zadaniem.
            IF SQLCODE = pkg_bledy.c_miejsce_zajete AND p_klucz_idempotencji IS NOT NULL
               AND znajdz_po_kluczu(p_klucz_idempotencji, o_id_rezerwacji, o_nr_biletu, o_id_miejsca, o_cena) THEN
                RETURN;
            END IF;
            IF SQLCODE NOT BETWEEN -20999 AND -20000 THEN
                pkg_bledy.zapisz('PKG_REZERWACJA.KUP_BILET', 'kurs=' || p_id_kursu);
            END IF;
            RAISE;
    END kup_bilet;

    PROCEDURE anuluj_bilet(p_nr_biletu IN VARCHAR2) IS
        v_id     rezerwacje.id_rezerwacji%TYPE;
        v_status rezerwacje.status%TYPE;
    BEGIN
        BEGIN
            SELECT id_rezerwacji, status INTO v_id, v_status
              FROM rezerwacje WHERE nr_biletu = p_nr_biletu
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma biletu ' || p_nr_biletu);
        END;
        IF v_status = 'ANULOWANA' THEN
            RETURN; -- operacja idempotentna
        END IF;
        UPDATE rezerwacje SET status = 'ANULOWANA', anulowano = SYSTIMESTAMP WHERE id_rezerwacji = v_id;
        DELETE FROM rezerwacje_odcinki WHERE id_rezerwacji = v_id;
    END anuluj_bilet;
END pkg_rezerwacja;
/
