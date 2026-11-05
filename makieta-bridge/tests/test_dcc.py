import pytest

from makieta_bridge.dcc import Akcesorium, BlednaRamka, Funkcje, Predkosc, StopAwaryjny, dekoduj


@pytest.mark.parametrize(
    "ramka, oczekiwane",
    [
        ("03 3F BD 81", Predkosc(3, 60, True)),
        ("03 3F 3D 01", Predkosc(3, 60, False)),
        ("03 3F 80 BC", Predkosc(3, 0, True)),
        ("C4 B9 3F 00 42", Predkosc(1209, 0, False)),
        ("03 91 92", Funkcje(3, True, True)),
        ("83 FD 7E", Akcesorium(11, True)),
        ("83 FC 7F", Akcesorium(11, False)),
        ("BF 8F 30", Akcesorium(2044, True)),
        ("00 71 71", StopAwaryjny()),
    ],
)
def test_dekoduje_ramki_nmra(ramka, oczekiwane):
    assert dekoduj(ramka) == oczekiwane


@pytest.mark.parametrize("ramka", ["03 3F BD 80", "03", "", "ZZ 00 00", "03 40 43"])
def test_odrzuca_uszkodzone_ramki(ramka):
    with pytest.raises(BlednaRamka):
        dekoduj(ramka)
