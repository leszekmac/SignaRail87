-- Instalacja schematu SignaRail 87. Uruchom jako uzytkownik aplikacyjny:
--   sqlplus signarail/<haslo>@//localhost/FREEPDB1 @install.sql
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SET DEFINE OFF
SET FEEDBACK OFF
SET ECHO OFF

PROMPT [1/4] Tabele
@@schema/01_h0_infrastruktura.sql
@@schema/02_pasazerski.sql
@@schema/03_integracja.sql

PROMPT [2/4] Typy i specyfikacje pakietow
@@packages/typy.sql
@@packages/pkg_bledy.pks
@@packages/pkg_rozklad.pks
@@packages/pkg_rezerwacja.pks
@@packages/pkg_powiadomienia.pks
@@packages/pkg_h0_controller.pks

PROMPT [3/4] Ciala pakietow
@@packages/pkg_bledy.pkb
@@packages/pkg_rozklad.pkb
@@packages/pkg_rezerwacja.pkb
@@packages/pkg_powiadomienia.pkb
@@packages/pkg_h0_controller.pkb

PROMPT [4/4] Kontrola kompilacji
SET SERVEROUTPUT ON
DECLARE
    v_ile PLS_INTEGER := 0;
BEGIN
    FOR e IN (SELECT name, type, line, position, text FROM user_errors ORDER BY name, type, sequence) LOOP
        v_ile := v_ile + 1;
        DBMS_OUTPUT.PUT_LINE(e.type || ' ' || e.name || ':' || e.line || ':' || e.position || ' ' || e.text);
    END LOOP;
    IF v_ile > 0 THEN
        RAISE_APPLICATION_ERROR(-20999, 'Bledy kompilacji: ' || v_ile);
    END IF;
    DBMS_OUTPUT.PUT_LINE('Schemat zainstalowany bez bledow.');
END;
/
EXIT
