-- Sprzedaz miejsc z gwarancja braku overbookingu.
-- Pakiet nie wykonuje COMMIT: granica transakcji nalezy do wywolujacego.
CREATE OR REPLACE PACKAGE pkg_rezerwacja AS
    c_limit_czekania_s CONSTANT PLS_INTEGER := 3;

    -- p_id_miejsca NULL = automatyczny wybor wolnego miejsca w klasie p_klasa.
    -- Ponowne wywolanie z tym samym p_klucz_idempotencji zwraca istniejacy bilet.
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
    );

    PROCEDURE anuluj_bilet(p_nr_biletu IN VARCHAR2);

    FUNCTION wylicz_cene(
        p_id_kursu IN NUMBER, p_lp_od IN NUMBER, p_lp_do IN NUMBER, p_klasa IN NUMBER
    ) RETURN NUMBER;
END pkg_rezerwacja;
/
