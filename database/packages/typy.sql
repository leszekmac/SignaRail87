-- Typy SQL: wynik wyszukiwania musi byc dostepny dla TABLE() w kursorze.
CREATE OR REPLACE TYPE t_odcinek_polaczenia AS OBJECT (
    id_polaczenia  NUMBER,
    nr_odcinka     NUMBER,
    id_kursu       NUMBER,
    numer_pociagu  VARCHAR2(10),
    kategoria      VARCHAR2(5),
    kod_od         VARCHAR2(8),
    stacja_od      VARCHAR2(60),
    odjazd         DATE,
    kod_do         VARCHAR2(8),
    stacja_do      VARCHAR2(60),
    przyjazd       DATE,
    przesiadki     NUMBER,
    czas_podrozy_min NUMBER
);
/
CREATE OR REPLACE TYPE t_odcinki_polaczenia AS TABLE OF t_odcinek_polaczenia;
/
