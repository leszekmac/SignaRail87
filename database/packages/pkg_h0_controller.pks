-- Sterowanie makieta H0: dobor skladu, zamykanie przebiegow, ramki DCC, sprzezenie S88.
-- Ramki zgodne z NMRA S-9.2 / S-9.2.1. Pakiet nie wykonuje COMMIT.
CREATE OR REPLACE PACKAGE pkg_h0_controller AS
    c_zapas_toru_mm CONSTANT PLS_INTEGER := 30;  -- margines przed izolacja sygnalu

    -- Dobiera lokomotywe i wagony z uwzglednieniem pogody, frekwencji, dlugosci toru,
    -- uciagu i wydajnosci centrali. Przy zimie wlacza grzalki rozjazdow na trasie.
    PROCEDURE przygotuj_sklad_makiety(p_kurs_id IN NUMBER);

    -- Zamyka przebieg, przestawia rozjazdy i kolejkuje polecenia dla centrali.
    PROCEDURE uruchom_kurs(p_kurs_id IN NUMBER);

    -- Meldunek czujnika zajetosci. Zajecie toru bez przebiegu = stop awaryjny.
    PROCEDURE zglos_s88(p_adres_s88 IN NUMBER, p_zajety IN VARCHAR2);

    PROCEDURE odblokuj_blok(p_kod_bloku IN VARCHAR2);

    -- Pobor pradu: wszystkie kursy aktywne plus opcjonalny kurs planowany.
    FUNCTION bilans_pradu_ma(p_dodatkowy_kurs_id IN NUMBER DEFAULT NULL) RETURN NUMBER;

    -- Zwraca bajty ramki predkosci 128-krokowej, np. '03 3F BD 81'.
    -- p_predkosc w km/h w skali 1:87; p_kierunek 'P' przod, 'T' tyl.
    FUNCTION wygeneruj_ramke_dcc(
        p_lokomotywa_id IN NUMBER,
        p_predkosc      IN NUMBER,
        p_kierunek      IN VARCHAR2 DEFAULT 'P'
    ) RETURN VARCHAR2;

    FUNCTION ramka_predkosci(p_adres IN NUMBER, p_krok IN NUMBER, p_kierunek IN VARCHAR2 DEFAULT 'P') RETURN VARCHAR2;
    FUNCTION ramka_funkcji(p_adres IN NUMBER, p_f0 IN BOOLEAN, p_f1 IN BOOLEAN) RETURN VARCHAR2;
    FUNCTION ramka_rozjazdu(p_adres IN NUMBER, p_polozenie IN VARCHAR2) RETURN VARCHAR2;
    FUNCTION ramka_stopu_awaryjnego RETURN VARCHAR2;

    -- Postac na szynach: preambula, bity startu, bajty, bit konca.
    FUNCTION ramka_na_bity(p_hex IN VARCHAR2) RETURN VARCHAR2;
END pkg_h0_controller;
/
