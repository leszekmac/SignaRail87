-- Rozklad jazdy: generowanie kursow, wyszukiwanie polaczen, obsluga opoznien.
CREATE OR REPLACE PACKAGE pkg_rozklad AS
    c_min_przesiadka_min CONSTANT PLS_INTEGER := 8;
    c_horyzont_h         CONSTANT PLS_INTEGER := 12;

    -- Kursor zwraca po wierszu na odcinek, pogrupowane przez id_polaczenia.
    -- Polaczenia zdominowane (pozniej na miejscu i wczesniej wyjazd, bez mniejszej
    -- liczby przesiadek) sa odrzucane.
    PROCEDURE znajdz_polaczenie(
        p_kod_od          IN  VARCHAR2,
        p_kod_do          IN  VARCHAR2,
        p_od_kiedy        IN  DATE,
        p_max_przesiadek  IN  PLS_INTEGER DEFAULT 2,
        p_limit           IN  PLS_INTEGER DEFAULT 5,
        o_wynik           OUT SYS_REFCURSOR
    );

    FUNCTION szukaj(
        p_id_od           IN NUMBER,
        p_id_do           IN NUMBER,
        p_od_kiedy        IN DATE,
        p_max_przesiadek  IN PLS_INTEGER,
        p_limit           IN PLS_INTEGER
    ) RETURN t_odcinki_polaczenia;

    -- Materializuje kursy i postoje z wzorcow; powtorne wywolanie niczego nie dubluje.
    PROCEDURE generuj_kursy(p_od IN DATE, p_do IN DATE);

    -- Zapisuje opoznienie i w tej samej transakcji tworzy powiadomienia pasazerow.
    PROCEDURE zglos_opoznienie(
        p_id_kursu        IN  NUMBER,
        p_opoznienie_min  IN  NUMBER,
        p_powod           IN  VARCHAR2,
        o_liczba_powiadomien OUT NUMBER
    );
END pkg_rozklad;
/
