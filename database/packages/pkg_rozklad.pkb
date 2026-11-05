CREATE OR REPLACE PACKAGE BODY pkg_rozklad AS

    -- Etykieta: jak najszybciej dotrzec do stacji w danej rundzie.
    TYPE t_etykieta IS RECORD (
        przyjazd     DATE,
        id_kursu     NUMBER,
        lp_od        NUMBER,
        lp_do        NUMBER,
        id_stacji_z  NUMBER
    );
    TYPE t_etykiety IS TABLE OF t_etykieta INDEX BY PLS_INTEGER;   -- klucz: id_stacji
    TYPE t_rundy    IS TABLE OF t_etykiety INDEX BY PLS_INTEGER;   -- klucz: numer rundy
    TYPE t_czasy    IS TABLE OF DATE INDEX BY PLS_INTEGER;

    TYPE t_przejazd IS RECORD (
        id_kursu NUMBER, lp_od NUMBER, lp_do NUMBER, id_stacji_do NUMBER, przyjazd DATE
    );
    TYPE t_przejazdy IS TABLE OF t_przejazd;

    FUNCTION id_stacji(p_kod VARCHAR2) RETURN NUMBER IS
        v_id stacje.id_stacji%TYPE;
    BEGIN
        SELECT id_stacji INTO v_id FROM stacje WHERE kod_stacji = p_kod;
        RETURN v_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma stacji ' || p_kod);
    END id_stacji;

    -- Wariant algorytmu RAPTOR: runda k = k-1 przesiadek. Rekurencyjny CTE musialby
    -- rozwinac wszystkie sciezki, zanim je porowna, a etykiety odcinaja galaz od razu,
    -- gdy nie poprawia czasu dotarcia. Koszt rosnie ze stacjami, nie ze sciezkami.
    PROCEDURE rundy(
        p_id_od NUMBER, p_id_do NUMBER, p_start DATE, p_max_przesiadek PLS_INTEGER,
        o_rundy OUT NOCOPY t_rundy
    ) IS
        v_najlepszy t_czasy;
        v_gotowy    t_czasy;   -- stacje poprawione w poprzedniej rundzie
        v_nowe      t_czasy;
        v_przejazdy t_przejazdy;
        v_stacja    PLS_INTEGER;
        v_cel       DATE := NULL;
        v_runda     t_etykiety;
    BEGIN
        v_gotowy(p_id_od) := p_start;
        FOR k IN 1 .. p_max_przesiadek + 1 LOOP
            EXIT WHEN v_gotowy.COUNT = 0;
            v_runda.DELETE;
            v_nowe.DELETE;
            v_stacja := v_gotowy.FIRST;
            WHILE v_stacja IS NOT NULL LOOP
                SELECT w.id_kursu, w.lp, d.lp, d.id_stacji, d.przyjazd
                  BULK COLLECT INTO v_przejazdy
                  FROM kursy_postoje w
                  JOIN kursy_postoje d ON d.id_kursu = w.id_kursu AND d.lp > w.lp
                  JOIN kursy_rozkladowe kr ON kr.id_kursu = w.id_kursu
                 WHERE w.id_stacji = v_stacja
                   AND w.odjazd >= v_gotowy(v_stacja)
                   AND w.odjazd <  v_gotowy(v_stacja) + c_horyzont_h / 24
                   AND kr.status <> 'ODWOLANY';

                FOR i IN 1 .. v_przejazdy.COUNT LOOP
                    DECLARE
                        v_p t_przejazd := v_przejazdy(i);
                        v_k PLS_INTEGER := v_p.id_stacji_do;
                    BEGIN
                        IF (v_cel IS NULL OR v_p.przyjazd < v_cel)
                           AND (NOT v_najlepszy.EXISTS(v_k) OR v_p.przyjazd < v_najlepszy(v_k)) THEN
                            v_najlepszy(v_k) := v_p.przyjazd;
                            v_runda(v_k).przyjazd := v_p.przyjazd;
                            v_runda(v_k).id_kursu := v_p.id_kursu;
                            v_runda(v_k).lp_od := v_p.lp_od;
                            v_runda(v_k).lp_do := v_p.lp_do;
                            v_runda(v_k).id_stacji_z := v_stacja;
                            IF v_k = p_id_do THEN
                                v_cel := v_p.przyjazd;
                            ELSE
                                v_nowe(v_k) := v_p.przyjazd + c_min_przesiadka_min / 1440;
                            END IF;
                        END IF;
                    END;
                END LOOP;
                v_stacja := v_gotowy.NEXT(v_stacja);
            END LOOP;
            o_rundy(k) := v_runda;
            v_gotowy := v_nowe;
        END LOOP;
    END rundy;

    FUNCTION szukaj(
        p_id_od           IN NUMBER,
        p_id_do           IN NUMBER,
        p_od_kiedy        IN DATE,
        p_max_przesiadek  IN PLS_INTEGER,
        p_limit           IN PLS_INTEGER
    ) RETURN t_odcinki_polaczenia IS
        v_wynik    t_odcinki_polaczenia := t_odcinki_polaczenia();
        v_rundy    t_rundy;
        v_pusto    t_rundy;
        v_start    DATE := p_od_kiedy;
        v_pierwszy DATE;
        v_id_pol   PLS_INTEGER := 0;   -- generator identyfikatorow
        v_liczba   PLS_INTEGER := 0;   -- polaczenia aktualnie w wyniku

        -- Polaczenie X dominuje Y, gdy wyjezdza nie wczesniej, dociera nie pozniej
        -- i nie ma wiecej przesiadek.
        FUNCTION dominuje(
            p_od_x DATE, p_do_x DATE, p_prz_x NUMBER, p_od_y DATE, p_do_y DATE, p_prz_y NUMBER
        ) RETURN BOOLEAN IS
        BEGIN
            RETURN p_od_x >= p_od_y AND p_do_x <= p_do_y AND p_prz_x <= p_prz_y;
        END dominuje;

        FUNCTION zdominowane(p_od DATE, p_do DATE, p_prz NUMBER) RETURN BOOLEAN IS
        BEGIN
            FOR i IN 1 .. v_wynik.COUNT LOOP
                IF v_wynik(i).nr_odcinka = 1 AND dominuje(
                       v_wynik(i).odjazd, v_wynik(i).odjazd + v_wynik(i).czas_podrozy_min / 1440,
                       v_wynik(i).przesiadki, p_od, p_do + 1 / 86400, p_prz) THEN
                    RETURN TRUE;
                END IF;
            END LOOP;
            RETURN FALSE;
        END zdominowane;

        -- Szukamy chronologicznie, wiec pozniejszy odjazd moze zdetronizowac wczesniejszy.
        PROCEDURE usun_zdominowane_przez(p_od DATE, p_do DATE, p_prz NUMBER) IS
            v_pozostale t_odcinki_polaczenia := t_odcinki_polaczenia();
            v_usuwane   SYS.ODCINUMBERLIST := SYS.ODCINUMBERLIST();
        BEGIN
            FOR i IN 1 .. v_wynik.COUNT LOOP
                IF v_wynik(i).nr_odcinka = 1 AND dominuje(
                       p_od, p_do, p_prz, v_wynik(i).odjazd,
                       v_wynik(i).odjazd + v_wynik(i).czas_podrozy_min / 1440 + 1 / 86400,
                       v_wynik(i).przesiadki) THEN
                    v_usuwane.EXTEND;
                    v_usuwane(v_usuwane.COUNT) := v_wynik(i).id_polaczenia;
                END IF;
            END LOOP;
            IF v_usuwane.COUNT = 0 THEN
                RETURN;
            END IF;
            FOR i IN 1 .. v_wynik.COUNT LOOP
                DECLARE
                    v_zostaje BOOLEAN := TRUE;
                BEGIN
                    FOR j IN 1 .. v_usuwane.COUNT LOOP
                        IF v_usuwane(j) = v_wynik(i).id_polaczenia THEN
                            v_zostaje := FALSE;
                        END IF;
                    END LOOP;
                    IF v_zostaje THEN
                        v_pozostale.EXTEND;
                        v_pozostale(v_pozostale.COUNT) := v_wynik(i);
                    END IF;
                END;
            END LOOP;
            v_wynik := v_pozostale;
            v_liczba := v_liczba - v_usuwane.COUNT;
        END usun_zdominowane_przez;

        -- Odtwarza trase po wskaznikach etykiet, od celu wstecz.
        PROCEDURE dopisz(p_k PLS_INTEGER, p_nast_start IN OUT DATE) IS
            TYPE t_stos IS TABLE OF t_etykieta INDEX BY PLS_INTEGER;
            v_stos    t_stos;
            v_stacja  NUMBER := p_id_do;
            v_ile     PLS_INTEGER := 0;
            v_od      DATE;
            v_koniec  DATE;
        BEGIN
            FOR r IN REVERSE 1 .. p_k LOOP
                -- Etykieta poprzedniej przesiadki moze pochodzic z dowolnej wczesniejszej rundy.
                IF r = p_k OR v_rundy(r).EXISTS(v_stacja) THEN
                    v_ile := v_ile + 1;
                    v_stos(v_ile) := v_rundy(r)(v_stacja);
                    v_stacja := v_stos(v_ile).id_stacji_z;
                    EXIT WHEN v_stacja = p_id_od;
                END IF;
            END LOOP;
            IF v_stacja <> p_id_od THEN
                RETURN;
            END IF;

            SELECT odjazd INTO v_od FROM kursy_postoje
             WHERE id_kursu = v_stos(v_ile).id_kursu AND lp = v_stos(v_ile).lp_od;
            v_koniec := v_stos(1).przyjazd;

            IF p_nast_start IS NULL OR v_od < p_nast_start THEN
                p_nast_start := v_od;
            END IF;
            IF zdominowane(v_od, v_koniec, v_ile - 1) THEN
                RETURN;
            END IF;
            usun_zdominowane_przez(v_od, v_koniec, v_ile - 1);

            v_id_pol := v_id_pol + 1;
            v_liczba := v_liczba + 1;
            FOR i IN REVERSE 1 .. v_ile LOOP
                v_wynik.EXTEND;
                SELECT t_odcinek_polaczenia(
                           v_id_pol, v_ile - i + 1, kr.id_kursu, p.numer_pociagu, p.kategoria,
                           s_o.kod_stacji, s_o.nazwa, o.odjazd,
                           s_d.kod_stacji, s_d.nazwa, d.przyjazd,
                           v_ile - 1, ROUND((v_koniec - v_od) * 1440))
                  INTO v_wynik(v_wynik.COUNT)
                  FROM kursy_rozkladowe kr
                  JOIN pociagi p ON p.id_pociagu = kr.id_pociagu
                  JOIN kursy_postoje o ON o.id_kursu = kr.id_kursu AND o.lp = v_stos(i).lp_od
                  JOIN kursy_postoje d ON d.id_kursu = kr.id_kursu AND d.lp = v_stos(i).lp_do
                  JOIN stacje s_o ON s_o.id_stacji = o.id_stacji
                  JOIN stacje s_d ON s_d.id_stacji = d.id_stacji
                 WHERE kr.id_kursu = v_stos(i).id_kursu;
            END LOOP;
        END dopisz;
    BEGIN
        IF p_id_od = p_id_do THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Stacja poczatkowa i docelowa musza byc rozne');
        END IF;
        -- Kolejne przebiegi przesuwaja start tuz za najwczesniejszy znaleziony odjazd.
        FOR i IN 1 .. p_limit * 4 LOOP
            EXIT WHEN v_liczba >= p_limit OR v_start >= p_od_kiedy + c_horyzont_h / 24;
            v_rundy := v_pusto;
            rundy(p_id_od, p_id_do, v_start, p_max_przesiadek, v_rundy);
            v_pierwszy := NULL;
            FOR k IN 1 .. v_rundy.COUNT LOOP
                IF v_rundy(k).EXISTS(p_id_do) THEN
                    dopisz(k, v_pierwszy);
                END IF;
            END LOOP;
            EXIT WHEN v_pierwszy IS NULL;
            v_start := v_pierwszy + 1 / 1440;
        END LOOP;
        RETURN v_wynik;
    END szukaj;

    PROCEDURE znajdz_polaczenie(
        p_kod_od          IN  VARCHAR2,
        p_kod_do          IN  VARCHAR2,
        p_od_kiedy        IN  DATE,
        p_max_przesiadek  IN  PLS_INTEGER DEFAULT 2,
        p_limit           IN  PLS_INTEGER DEFAULT 5,
        o_wynik           OUT SYS_REFCURSOR
    ) IS
        v_odc t_odcinki_polaczenia;
    BEGIN
        IF p_max_przesiadek NOT BETWEEN 0 AND 4 OR p_limit NOT BETWEEN 1 AND 20 OR p_od_kiedy IS NULL THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane,
                'Dozwolone: czas wymagany, przesiadki 0-4, limit 1-20');
        END IF;
        v_odc := szukaj(id_stacji(p_kod_od), id_stacji(p_kod_do), p_od_kiedy, p_max_przesiadek, p_limit);
        -- id_polaczenia po filtrze dominacji ma luki; numeracja wynika z kolejnosci odjazdow.
        OPEN o_wynik FOR
            SELECT DENSE_RANK() OVER (ORDER BY odjazd_pol, przyjazd_pol, id_polaczenia) id_polaczenia,
                   nr_odcinka, id_kursu, numer_pociagu, kategoria, kod_od, stacja_od, odjazd,
                   kod_do, stacja_do, przyjazd, przesiadki, czas_podrozy_min
              FROM (SELECT t.*,
                           MIN(odjazd) OVER (PARTITION BY id_polaczenia) odjazd_pol,
                           MAX(przyjazd) OVER (PARTITION BY id_polaczenia) przyjazd_pol
                      FROM TABLE(v_odc) t)
             WHERE id_polaczenia IN (
                   SELECT id_polaczenia FROM (
                       SELECT DISTINCT id_polaczenia,
                              MIN(odjazd) OVER (PARTITION BY id_polaczenia) o
                         FROM TABLE(v_odc) ORDER BY o)
                    WHERE ROWNUM <= p_limit)
             ORDER BY 1, nr_odcinka;
    END znajdz_polaczenie;

    PROCEDURE generuj_kursy(p_od IN DATE, p_do IN DATE) IS
    BEGIN
        INSERT INTO kursy_rozkladowe (id_pociagu, data_kursu)
        SELECT p.id_pociagu, d.dzien
          FROM pociagi p
         CROSS JOIN (SELECT TRUNC(p_od) + LEVEL - 1 dzien FROM dual
                     CONNECT BY LEVEL <= TRUNC(p_do) - TRUNC(p_od) + 1) d
         WHERE EXISTS (SELECT 1 FROM postoje_wzorcowe w WHERE w.id_pociagu = p.id_pociagu)
           AND NOT EXISTS (SELECT 1 FROM kursy_rozkladowe k
                            WHERE k.id_pociagu = p.id_pociagu AND k.data_kursu = d.dzien);

        INSERT INTO kursy_postoje (id_kursu, lp, id_stacji, przyjazd, odjazd, km_od_startu)
        SELECT k.id_kursu, w.lp, w.id_stacji,
               k.data_kursu + w.minuta_przyjazdu / 1440,
               k.data_kursu + w.minuta_odjazdu / 1440,
               w.km_od_startu
          FROM kursy_rozkladowe k
          JOIN postoje_wzorcowe w ON w.id_pociagu = k.id_pociagu
         WHERE k.data_kursu BETWEEN TRUNC(p_od) AND TRUNC(p_do)
           AND NOT EXISTS (SELECT 1 FROM kursy_postoje kp
                            WHERE kp.id_kursu = k.id_kursu AND kp.lp = w.lp);
    END generuj_kursy;

    PROCEDURE zglos_opoznienie(
        p_id_kursu        IN  NUMBER,
        p_opoznienie_min  IN  NUMBER,
        p_powod           IN  VARCHAR2,
        o_liczba_powiadomien OUT NUMBER
    ) IS
        v_status kursy_rozkladowe.status%TYPE;
        v_numer  pociagi.numer_pociagu%TYPE;
    BEGIN
        IF p_opoznienie_min IS NULL OR p_opoznienie_min < 0 THEN
            pkg_bledy.zglos(pkg_bledy.c_niepoprawne_dane, 'Opoznienie nie moze byc ujemne');
        END IF;
        BEGIN
            SELECT k.status, p.numer_pociagu INTO v_status, v_numer
              FROM kursy_rozkladowe k JOIN pociagi p ON p.id_pociagu = k.id_pociagu
             WHERE k.id_kursu = p_id_kursu
               FOR UPDATE OF k.status;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                pkg_bledy.zglos(pkg_bledy.c_nie_znaleziono, 'Nie ma kursu ' || p_id_kursu);
        END;
        IF v_status = 'ODWOLANY' THEN
            pkg_bledy.zglos(pkg_bledy.c_kurs_niedostepny, 'Kurs jest odwolany');
        END IF;

        UPDATE kursy_rozkladowe
           SET status = CASE WHEN p_opoznienie_min > 0 THEN 'OPOZNIONY' ELSE 'PLANOWY' END,
               opoznienie_min = p_opoznienie_min,
               powod_opoznienia = p_powod
         WHERE id_kursu = p_id_kursu;

        -- Ta sama wartosc zgloszona ponownie nie tworzy duplikatow powiadomien.
        INSERT INTO powiadomienia (id_rezerwacji, opoznienie_min, kanal, odbiorca, tresc)
        SELECT r.id_rezerwacji, p_opoznienie_min, c.kanal, c.odbiorca,
               SUBSTR('Pociag ' || v_numer || ' ma ' || p_opoznienie_min || ' min opoznienia'
                      || NVL2(p_powod, ': ' || p_powod, '') || '. Bilet ' || r.nr_biletu, 1, 400)
          FROM rezerwacje r
         CROSS APPLY (
               SELECT 'EMAIL' kanal, r.email odbiorca FROM dual WHERE r.email IS NOT NULL
               UNION ALL
               SELECT 'SMS', r.telefon FROM dual WHERE r.telefon IS NOT NULL) c
         WHERE r.id_kursu = p_id_kursu
           AND r.status = 'OPLACONA'
           AND p_opoznienie_min > 0
           AND NOT EXISTS (SELECT 1 FROM powiadomienia w
                            WHERE w.id_rezerwacji = r.id_rezerwacji
                              AND w.opoznienie_min = p_opoznienie_min
                              AND w.kanal = c.kanal);
        o_liczba_powiadomien := SQL%ROWCOUNT;
    END zglos_opoznienie;
END pkg_rozklad;
/
