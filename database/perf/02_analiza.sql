-- Analiza planow: te same zapytania na tych samych danych, przed i po optymalizacji.
-- Liczby pochodza z DBMS_XPLAN.DISPLAY_CURSOR (ALLSTATS LAST), czyli z wykonania,
-- a nie z estymat EXPLAIN PLAN.
SET LINESIZE 170 PAGESIZE 0 FEEDBACK OFF TIMING OFF TRIMSPOOL ON
-- SERVEROUTPUT wlaczony tylko dla czesci F: inaczej SQL*Plus po kazdym zapytaniu wola
-- DBMS_OUTPUT i DISPLAY_CURSOR pokazuje to wywolanie zamiast badanego zapytania.
SET SERVEROUTPUT OFF
ALTER SESSION SET statistics_level = ALL;
ALTER SESSION SET nls_date_format = 'YYYY-MM-DD HH24:MI';

VARIABLE st NUMBER
VARIABLE t0 VARCHAR2(20)
VARIABLE kurs NUMBER
BEGIN
    SELECT MIN(id_stacji) + 40 INTO :st FROM stacje;
    :t0 := TO_CHAR(TRUNC(SYSDATE, 'YYYY') + 180 + 8 / 24, 'YYYY-MM-DD HH24:MI');
    SELECT MIN(r.id_kursu) INTO :kurs FROM rezerwacje r
     WHERE r.id_kursu > (SELECT MIN(id_kursu) + 90000 FROM kursy_rozkladowe);
END;
/

-- Tabela kontrolna bez partycji i bez indeksu: stan "przed".
CREATE TABLE perf_postoje_plaska AS SELECT * FROM kursy_postoje;
BEGIN DBMS_STATS.GATHER_TABLE_STATS(USER, 'PERF_POSTOJE_PLASKA'); END;
/

PROMPT ============================================================
PROMPT A. Odjazdy ze stacji w oknie 12h - tabela plaska, bez indeksu
PROMPT ============================================================
ALTER SYSTEM FLUSH BUFFER_CACHE;
SELECT /*+ gather_plan_statistics */ COUNT(*), MIN(odjazd)
  FROM perf_postoje_plaska
 WHERE id_stacji = :st
   AND odjazd >= TO_DATE(:t0, 'YYYY-MM-DD HH24:MI')
   AND odjazd <  TO_DATE(:t0, 'YYYY-MM-DD HH24:MI') + 0.5;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST -NOTE'));

PROMPT ============================================================
PROMPT B. To samo - partycje miesieczne, indeks niewidoczny
PROMPT ============================================================
ALTER INDEX ix_kp_stacja_odjazd INVISIBLE;
ALTER SYSTEM FLUSH BUFFER_CACHE;
SELECT /*+ gather_plan_statistics */ COUNT(*), MIN(odjazd)
  FROM kursy_postoje
 WHERE id_stacji = :st
   AND odjazd >= TO_DATE(:t0, 'YYYY-MM-DD HH24:MI')
   AND odjazd <  TO_DATE(:t0, 'YYYY-MM-DD HH24:MI') + 0.5;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST -NOTE'));

PROMPT ============================================================
PROMPT C. To samo - partycje i lokalny indeks (id_stacji, odjazd)
PROMPT ============================================================
ALTER INDEX ix_kp_stacja_odjazd VISIBLE;
ALTER SYSTEM FLUSH BUFFER_CACHE;
SELECT /*+ gather_plan_statistics */ COUNT(*), MIN(odjazd)
  FROM kursy_postoje
 WHERE id_stacji = :st
   AND odjazd >= TO_DATE(:t0, 'YYYY-MM-DD HH24:MI')
   AND odjazd <  TO_DATE(:t0, 'YYYY-MM-DD HH24:MI') + 0.5;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST -NOTE'));

PROMPT ============================================================
PROMPT D. Pasazerowie kursu do powiadomienia - bez indeksu
PROMPT ============================================================
ALTER INDEX ix_rez_kurs_status INVISIBLE;
ALTER SYSTEM FLUSH BUFFER_CACHE;
SELECT /*+ gather_plan_statistics */ COUNT(*), SUM(cena)
  FROM rezerwacje WHERE id_kursu = :kurs AND status = 'OPLACONA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST -NOTE'));

PROMPT ============================================================
PROMPT E. To samo - indeks (id_kursu, status)
PROMPT ============================================================
ALTER INDEX ix_rez_kurs_status VISIBLE;
ALTER SYSTEM FLUSH BUFFER_CACHE;
SELECT /*+ gather_plan_statistics */ COUNT(*), SUM(cena)
  FROM rezerwacje WHERE id_kursu = :kurs AND status = 'OPLACONA';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST -NOTE'));

SET SERVEROUTPUT ON SIZE UNLIMITED
PROMPT ============================================================
PROMPT F. Czas wyszukiwania: algorytm rundowy (PKG_ROZKLAD) vs rekurencyjny CTE
PROMPT ============================================================
DECLARE
    v_t0    DATE := TO_DATE(:t0, 'YYYY-MM-DD HH24:MI');
    v_od    NUMBER;
    v_do    NUMBER;
    v_wynik t_odcinki_polaczenia;
    v_start PLS_INTEGER;
    v_suma  PLS_INTEGER;
    v_ile   NUMBER;
BEGIN
    SELECT MIN(id_stacji) + 3, MIN(id_stacji) + 77 INTO v_od, v_do FROM stacje;
    FOR p IN 0 .. 3 LOOP
        v_start := DBMS_UTILITY.GET_TIME;
        v_wynik := pkg_rozklad.szukaj(v_od, v_do, v_t0, p, 5);
        v_suma := DBMS_UTILITY.GET_TIME - v_start;
        DBMS_OUTPUT.PUT_LINE('RUNDY maks. przesiadek=' || p || ': ' || v_suma * 10 || ' ms, odcinkow wyniku=' || v_wynik.COUNT);
    END LOOP;

    -- CTE rozwija kazda sciezke; horyzont i limit przesiadek jak wyzej.
    FOR p IN 0 .. 2 LOOP
        v_start := DBMS_UTILITY.GET_TIME;
        WITH podroz (id_stacji, przyjazd, przesiadki) AS (
            SELECT d.id_stacji, d.przyjazd, 0
              FROM kursy_postoje w
              JOIN kursy_postoje d ON d.id_kursu = w.id_kursu AND d.lp > w.lp
             WHERE w.id_stacji = v_od AND w.odjazd >= v_t0 AND w.odjazd < v_t0 + 0.5
            UNION ALL
            SELECT d.id_stacji, d.przyjazd, s.przesiadki + 1
              FROM podroz s
              JOIN kursy_postoje w ON w.id_stacji = s.id_stacji
               AND w.odjazd >= s.przyjazd + 8 / 1440 AND w.odjazd < s.przyjazd + 0.5
              JOIN kursy_postoje d ON d.id_kursu = w.id_kursu AND d.lp > w.lp
             WHERE s.przesiadki < p AND s.id_stacji <> v_do
        )
        SELECT COUNT(*) INTO v_ile FROM podroz WHERE id_stacji = v_do;
        v_suma := DBMS_UTILITY.GET_TIME - v_start;
        DBMS_OUTPUT.PUT_LINE('CTE   maks. przesiadek=' || p || ': ' || v_suma * 10 || ' ms, sciezek do celu=' || v_ile);
    END LOOP;
END;
/
DROP TABLE perf_postoje_plaska PURGE;
EXIT
