-- Odbior skrzynki powiadomien. Dostawa at-least-once: pracownik po awarii
-- moze wyslac wiadomosc ponownie, ale nigdy jej nie zgubi.
CREATE OR REPLACE PACKAGE pkg_powiadomienia AS
    c_dzierzawa_s CONSTANT PLS_INTEGER := 60;
    c_max_prob    CONSTANT PLS_INTEGER := 5;

    -- Rezerwuje partie wierszy. Rownolegli konsumenci nie dostana tych samych.
    PROCEDURE pobierz_partie(p_limit IN PLS_INTEGER, o_wynik OUT SYS_REFCURSOR);
    PROCEDURE potwierdz(p_id IN NUMBER);
    -- Wykladnicze odstepy miedzy probami; po c_max_prob wiersz trafia do MARTWE.
    PROCEDURE odrzuc(p_id IN NUMBER, p_blad IN VARCHAR2);
END pkg_powiadomienia;
/
