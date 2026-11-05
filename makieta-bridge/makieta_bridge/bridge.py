"""Petla mostu: odbior polecen z kolejki Oracle, wysylka i meldunki S88."""
import logging

import oracledb

from .dcc import BlednaRamka, dekoduj

log = logging.getLogger("makieta-bridge")

# Wyrazenie w WHERE musi byc identyczne jak w indeksie ix_dcc_do_wysylki.
SQL_POBIERZ = """
    SELECT id_zadania, ramka_hex, opis
      FROM h0_kolejka_dcc
     WHERE CASE WHEN status = 'NOWE' THEN id_zadania END IS NOT NULL
     ORDER BY id_zadania
       FOR UPDATE SKIP LOCKED
"""

SQL_ZATWIERDZ = """
    UPDATE h0_kolejka_dcc
       SET status = :status, proby = proby + 1,
           wyslano = CASE WHEN :status = 'WYSLANE' THEN SYSTIMESTAMP END
     WHERE id_zadania = :id
"""

SQL_NASTEPNY_KROK = """
    SELECT k.id_kursu, p.kolejnosc, b.adres_s88, b.status_blokady
      FROM h0_harmonogram_kursow k
      JOIN h0_przebiegi p ON p.id_kursu = k.id_kursu
      JOIN h0_bloki_torowe b ON b.id_bloku = p.id_bloku
     WHERE k.status_kursu = 'W_TRASIE'
     ORDER BY k.id_kursu, p.kolejnosc
"""

SQL_TORY_PO_KURSIE = """
    SELECT b.adres_s88
      FROM h0_bloki_torowe b
      JOIN h0_harmonogram_kursow k ON k.id_kursu = b.id_kursu_przebiegu
     WHERE b.status_blokady = 'ZAJETY' AND k.status_kursu = 'ZAKONCZONY'
"""


def wyslij_oczekujace(polaczenie: oracledb.Connection, rozmiar_partii: int = 50) -> int:
    """Wysyla jedna partie. Status i wysylka commituja sie razem z zamknieciem partii."""
    wyslane = 0
    with polaczenie.cursor() as kursor:
        kursor.execute(SQL_POBIERZ)
        for id_zadania, ramka, opis in kursor.fetchmany(rozmiar_partii):
            try:
                dekoduj(ramka)
            except BlednaRamka as e:
                log.error("[DCC ODRZUCONA] #%s %s: %s", id_zadania, ramka, e)
                status = "BLAD"
            else:
                log.info("[DCC SEND] %s [%s]", opis, ramka)
                status = "WYSLANE"
                wyslane += 1
            with polaczenie.cursor() as aktualizacja:
                aktualizacja.execute(SQL_ZATWIERDZ, status=status, id=id_zadania)
    polaczenie.commit()
    return wyslane


def symuluj_krok(polaczenie: oracledb.Connection) -> int:
    """Przesuwa kazdy jadacy pociag o jeden blok, meldujac to jak czujniki S88."""
    with polaczenie.cursor() as kursor:
        meldunki = _meldunki_jazdy(kursor.execute(SQL_NASTEPNY_KROK).fetchall())
        meldunki += [(s88, "N") for (s88,) in kursor.execute(SQL_TORY_PO_KURSIE).fetchall()]
        for adres, zajety in meldunki:
            log.info("[S88] czujnik %s: %s", adres, "zajety" if zajety == "T" else "wolny")
            kursor.callproc("pkg_h0_controller.zglos_s88", [adres, zajety])
    polaczenie.commit()
    return len(meldunki)


def _meldunki_jazdy(wiersze: list[tuple]) -> list[tuple[int, str]]:
    meldunki = []
    trasy: dict[int, list[tuple]] = {}
    for id_kursu, _, s88, status in wiersze:
        trasy.setdefault(id_kursu, []).append((s88, status))

    for trasa in trasy.values():
        nastepny = next((i for i, (_, status) in enumerate(trasa) if status == "PRZEBIEG"), None)
        if nastepny is None:
            continue
        meldunki.append((trasa[nastepny][0], "T"))
        # Blok zwalnia sie, gdy caly sklad wjechal na kolejny; w symulacji to jeden krok pozniej.
        meldunki += [(s88, "N") for s88, status in trasa[:nastepny] if status == "ZAJETY"]
    return meldunki
