-- Uruchamia wszystkie testy utPLSQL biezacego schematu (patrz scripts/test-db.sh).
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET LINESIZE 200
SET DEFINE OFF
@@ut_h0_dcc.sql
@@ut_h0_ruch.sql
@@ut_rezerwacja.sql
@@ut_rozklad.sql
@@ut_powiadomienia.sql

EXEC ut.run(a_color_console => FALSE);

EXIT
