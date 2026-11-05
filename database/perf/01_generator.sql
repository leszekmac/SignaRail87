-- Generator danych obciazeniowych: rok rozkladu dla 500 pociagow i ponad milion biletow.
-- Uruchamiany w osobnym schemacie przez scripts/perf.sh.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET TIMING ON

DECLARE
    c_stacji  CONSTANT PLS_INTEGER := 120;
    c_pociagow CONSTANT PLS_INTEGER := 500;
    c_dni     CONSTANT PLS_INTEGER := 365;
    c_start   CONSTANT DATE := TRUNC(SYSDATE, 'YYYY');
    v_od      DATE;
BEGIN
    INSERT INTO stacje (kod_stacji, nazwa)
    SELECT 'S' || LPAD(LEVEL, 3, '0'), 'Stacja ' || LEVEL FROM dual CONNECT BY LEVEL <= c_stacji;

    INSERT INTO pociagi (numer_pociagu, kategoria)
    SELECT 'P' || LPAD(LEVEL, 4, '0'), 'IC' FROM dual CONNECT BY LEVEL <= c_pociagow;

    INSERT INTO taryfy VALUES ('IC', 2, 0.38, 19);

    -- Trasy: 12 postojow, kolejne stacje co staly krok, odjazd rozlozony po calej dobie.
    INSERT INTO postoje_wzorcowe (id_pociagu, lp, id_stacji, minuta_przyjazdu, minuta_odjazdu, km_od_startu)
    WITH st AS (SELECT id_stacji, ROW_NUMBER() OVER (ORDER BY id_stacji) - 1 nr FROM stacje),
         pc AS (SELECT id_pociagu, ROW_NUMBER() OVER (ORDER BY id_pociagu) - 1 nr FROM pociagi),
         lp AS (SELECT LEVEL lp FROM dual CONNECT BY LEVEL <= 12)
    SELECT pc.id_pociagu, lp.lp, st.id_stacji,
           240 + MOD(pc.nr * 37, 960) + (lp.lp - 1) * 30,
           240 + MOD(pc.nr * 37, 960) + (lp.lp - 1) * 30 + 2,
           (lp.lp - 1) * 45
      FROM pc CROSS JOIN lp
      JOIN st ON st.nr = MOD(pc.nr * 7 + (lp.lp - 1) * (1 + MOD(pc.nr, 5)), c_stacji);

    INSERT INTO h0_wagony (nr_inwentarzowy, typ_wagonu, kategoria, dlugosc_ze_sprzegiem_mm, masa_g, liczba_miejsc)
    SELECT 'P' || LEVEL, 'Bmnopux', 'PASAZERSKI', 303, 240, 60 FROM dual CONNECT BY LEVEL <= c_pociagow;

    INSERT INTO miejsca (id_wagonu, nr_miejsca, klasa)
    SELECT w.id_wagonu, n.nr, 2
      FROM h0_wagony w CROSS JOIN (SELECT LEVEL nr FROM dual CONNECT BY LEVEL <= 60) n;

    INSERT INTO pociagi_wagony (id_pociagu, nr_wagonu, id_wagonu)
    SELECT p.id_pociagu, 1, w.id_wagonu
      FROM (SELECT id_pociagu, ROW_NUMBER() OVER (ORDER BY id_pociagu) n FROM pociagi) p
      JOIN (SELECT id_wagonu, ROW_NUMBER() OVER (ORDER BY id_wagonu) n FROM h0_wagony) w ON w.n = p.n;
    COMMIT;

    -- Tygodniowymi paczkami: krotsze transakcje i ograniczone uzycie UNDO.
    v_od := c_start;
    WHILE v_od < c_start + c_dni LOOP
        pkg_rozklad.generuj_kursy(v_od, LEAST(v_od + 6, c_start + c_dni - 1));
        COMMIT;
        v_od := v_od + 7;
    END LOOP;

    -- Bilety: co trzeci kurs, na cale pierwsze 3 odcinki trasy kazdego miejsca co drugiego.
    INSERT /*+ APPEND */ INTO rezerwacje (
        nr_biletu, id_kursu, id_miejsca, id_stacji_od, id_stacji_do, lp_od, lp_do,
        pasazer, email, cena, status)
    SELECT 'B' || k.id_kursu || '-' || m.id_miejsca, k.id_kursu, m.id_miejsca, o.id_stacji, d.id_stacji, 1, 4,
           'Pasazer ' || m.nr_miejsca, 'p' || m.id_miejsca || '@example.com', 51.3,
           CASE WHEN MOD(m.id_miejsca + k.id_kursu, 40) = 0 THEN 'ANULOWANA' ELSE 'OPLACONA' END
      FROM kursy_rozkladowe k
      JOIN pociagi_wagony pw ON pw.id_pociagu = k.id_pociagu
      JOIN miejsca m ON m.id_wagonu = pw.id_wagonu AND MOD(m.nr_miejsca, 2) = 0
      JOIN kursy_postoje o ON o.id_kursu = k.id_kursu AND o.lp = 1
      JOIN kursy_postoje d ON d.id_kursu = k.id_kursu AND d.lp = 4
     WHERE MOD(k.id_kursu, 3) = 0;
    COMMIT;

    INSERT /*+ APPEND */ INTO rezerwacje_odcinki (id_kursu, id_miejsca, lp_odcinka, id_rezerwacji)
    SELECT r.id_kursu, r.id_miejsca, n.lp, r.id_rezerwacji
      FROM rezerwacje r CROSS JOIN (SELECT LEVEL lp FROM dual CONNECT BY LEVEL <= 3) n
     WHERE r.status = 'OPLACONA';
    COMMIT;
END;
/

BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(USER, cascade => TRUE, degree => 2);
END;
/

SELECT 'kursy_rozkladowe' tabela, COUNT(*) wierszy FROM kursy_rozkladowe
UNION ALL SELECT 'kursy_postoje', COUNT(*) FROM kursy_postoje
UNION ALL SELECT 'rezerwacje', COUNT(*) FROM rezerwacje
UNION ALL SELECT 'rezerwacje_odcinki', COUNT(*) FROM rezerwacje_odcinki;
EXIT
