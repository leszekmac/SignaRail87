-- Wspolny katalog bledow biznesowych. API mapuje te kody na odpowiedzi HTTP.
CREATE OR REPLACE PACKAGE pkg_bledy AS
    c_niepoprawne_dane   CONSTANT PLS_INTEGER := -20001;
    c_nie_znaleziono     CONSTANT PLS_INTEGER := -20002;
    c_kurs_niedostepny   CONSTANT PLS_INTEGER := -20010;
    c_miejsce_zajete     CONSTANT PLS_INTEGER := -20011;
    c_brak_miejsc        CONSTANT PLS_INTEGER := -20012;
    c_miejsce_blokowane  CONSTANT PLS_INTEGER := -20013;
    c_miejsce_poza_kursem CONSTANT PLS_INTEGER := -20014;
    c_stan_kursu         CONSTANT PLS_INTEGER := -20020;
    c_brak_lokomotywy    CONSTANT PLS_INTEGER := -20021;
    c_sklad_za_dlugi     CONSTANT PLS_INTEGER := -20022;
    c_przeciazenie_pradu CONSTANT PLS_INTEGER := -20023;
    c_brak_przebiegu     CONSTANT PLS_INTEGER := -20024;
    c_przebieg_zajety    CONSTANT PLS_INTEGER := -20025;

    PROCEDURE zglos(p_kod IN PLS_INTEGER, p_komunikat IN VARCHAR2);

    -- Transakcja autonomiczna: wpis przetrwa ROLLBACK wywolujacego.
    PROCEDURE zapisz(p_zrodlo IN VARCHAR2, p_kontekst IN VARCHAR2 DEFAULT NULL);
END pkg_bledy;
/
