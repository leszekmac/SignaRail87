"""Pelny obieg na prawdziwej bazie. Wymaga SIGNARAIL_DB_DSN.

Kazdy test tworzy wlasny kurs na wolnych torach i sprzata po sobie przywracajac stan makiety.
"""
import logging
import os

import pytest

oracledb = pytest.importorskip("oracledb")

from makieta_bridge.bridge import symuluj_krok, wyslij_oczekujace  # noqa: E402
from makieta_bridge.dcc import Predkosc, dekoduj  # noqa: E402

DSN = os.environ.get("SIGNARAIL_DB_DSN")
pytestmark = pytest.mark.skipif(not DSN, reason="brak SIGNARAIL_DB_DSN")


@pytest.fixture
def polaczenie():
    with oracledb.connect(
        user=os.environ.get("SIGNARAIL_DB_USER", "signarail"),
        password=os.environ.get("SIGNARAIL_DB_PASSWORD", "signarail"),
        dsn=DSN,
    ) as c:
        yield c


@pytest.fixture
def kurs(polaczenie):
    with polaczenie.cursor() as k:
        nowy_id = k.var(oracledb.NUMBER)
        k.execute(
            """INSERT INTO h0_harmonogram_kursow
                   (identyfikator_rejsu, id_bloku_start, id_bloku_meta, godzina_odjazdu, prognoza_frekwencji_procent)
               VALUES ('BRIDGE_TEST', 2, 7, SYSTIMESTAMP, 40)
               RETURNING id_kursu INTO :id""",
            id=nowy_id,
        )
        id_kursu = int(nowy_id.getvalue()[0])
        k.callproc("pkg_h0_controller.przygotuj_sklad_makiety", [id_kursu])
        k.callproc("pkg_h0_controller.uruchom_kurs", [id_kursu])
    polaczenie.commit()
    yield id_kursu
    with polaczenie.cursor() as k:
        k.execute("UPDATE h0_bloki_torowe SET status_blokady = 'WOLNY', id_kursu_przebiegu = NULL WHERE id_kursu_przebiegu = :1", [id_kursu])
        k.execute("DELETE FROM h0_kolejka_dcc WHERE id_kursu = :1", [id_kursu])
        k.execute("DELETE FROM h0_przebiegi WHERE id_kursu = :1", [id_kursu])
        k.execute("DELETE FROM h0_aktywne_sklady WHERE id_kursu = :1", [id_kursu])
        k.execute("DELETE FROM h0_harmonogram_kursow WHERE id_kursu = :1", [id_kursu])
    polaczenie.commit()


def test_wysyla_polecenia_i_oznacza_je_w_bazie(polaczenie, kurs, caplog):
    caplog.set_level(logging.INFO, logger="makieta-bridge")

    assert wyslij_oczekujace(polaczenie) >= 2

    with polaczenie.cursor() as k:
        k.execute("SELECT COUNT(*) FROM h0_kolejka_dcc WHERE id_kursu = :1 AND status = 'NOWE'", [kurs])
        assert k.fetchone()[0] == 0
    assert "[DCC SEND] Adres lokomotywy:" in caplog.text
    assert "skalowane do 1:87" in caplog.text


def test_ramki_z_plsql_dekoduja_sie_niezaleznie(polaczenie, kurs):
    with polaczenie.cursor() as k:
        k.execute(
            """SELECT q.ramka_hex, l.adres_dcc_loco FROM h0_kolejka_dcc q
                 JOIN h0_harmonogram_kursow h ON h.id_kursu = q.id_kursu
                 JOIN h0_lokomotywy l ON l.id_lokomotywy = h.id_lokomotywy
                WHERE q.id_kursu = :1 AND q.typ_polecenia = 'PREDKOSC'""",
            [kurs],
        )
        ramka, adres = k.fetchone()
    polecenie = dekoduj(ramka)
    assert isinstance(polecenie, Predkosc)
    assert polecenie.adres == adres
    assert polecenie.krok == 60  # limit torow stacyjnych


def test_uszkodzona_ramka_nie_idzie_na_tory(polaczenie, kurs):
    wyslij_oczekujace(polaczenie)
    with polaczenie.cursor() as k:
        k.execute(
            """INSERT INTO h0_kolejka_dcc (id_kursu, typ_polecenia, ramka_hex, opis)
               VALUES (:1, 'PREDKOSC', '03 3F BD 00', 'uszkodzona')""",
            [kurs],
        )
        polaczenie.commit()
        assert wyslij_oczekujace(polaczenie) == 0
        k.execute("SELECT status FROM h0_kolejka_dcc WHERE id_kursu = :1 AND opis = 'uszkodzona'", [kurs])
        assert k.fetchone()[0] == "BLAD"


def test_symulacja_dowozi_pociag_do_celu_i_zwalnia_tory(polaczenie, kurs):
    for _ in range(8):
        symuluj_krok(polaczenie)
    with polaczenie.cursor() as k:
        k.execute("SELECT status_kursu FROM h0_harmonogram_kursow WHERE id_kursu = :1", [kurs])
        assert k.fetchone()[0] == "ZAKONCZONY"
        k.execute("SELECT COUNT(*) FROM h0_bloki_torowe WHERE id_kursu_przebiegu = :1", [kurs])
        assert k.fetchone()[0] == 0
