"""Niezalezny dekoder pakietow NMRA DCC.

Ramki powstaja w PL/SQL. Dekodowanie ich tutaj, w drugim jezyku i bez wspolnego kodu,
sprawia, ze blad kodera wychodzi na jaw przed wyslaniem pakietu na tory.
"""
from dataclasses import dataclass


class BlednaRamka(ValueError):
    """Ramka uszkodzona lub spoza obslugiwanego podzbioru NMRA."""


@dataclass(frozen=True)
class Predkosc:
    adres: int
    krok: int
    naprzod: bool


@dataclass(frozen=True)
class Funkcje:
    adres: int
    f0: bool
    f1: bool


@dataclass(frozen=True)
class Akcesorium:
    adres: int
    prosto: bool


@dataclass(frozen=True)
class StopAwaryjny:
    pass


Polecenie = Predkosc | Funkcje | Akcesorium | StopAwaryjny


def dekoduj(ramka_hex: str) -> Polecenie:
    try:
        bajty = [int(b, 16) for b in ramka_hex.split()]
    except ValueError as e:
        raise BlednaRamka(f"Niepoprawny zapis ramki: {ramka_hex!r}") from e
    if len(bajty) < 3 or any(not 0 <= b <= 255 for b in bajty):
        raise BlednaRamka(f"Niepoprawna dlugosc ramki: {ramka_hex!r}")

    xor = 0
    for b in bajty[:-1]:
        xor ^= b
    if xor != bajty[-1]:
        raise BlednaRamka(f"Bledna suma kontrolna: {ramka_hex!r}")

    tresc = bajty[:-1]
    if tresc[0] == 0x00:
        return _broadcast(tresc)
    if 0x80 <= tresc[0] <= 0xBF:
        return _akcesorium(tresc)
    if tresc[0] <= 0x7F:
        return _instrukcja(tresc[0], tresc[1:])
    if 0xC0 <= tresc[0] <= 0xE7 and len(tresc) >= 3:
        return _instrukcja(((tresc[0] & 0x3F) << 8) | tresc[1], tresc[2:])
    raise BlednaRamka(f"Nieobslugiwany adres: {ramka_hex!r}")


def _broadcast(tresc: list[int]) -> StopAwaryjny:
    if len(tresc) == 2 and tresc[1] & 0b1100_1110 == 0b0100_0000 and tresc[1] & 1:
        return StopAwaryjny()
    raise BlednaRamka("Nieobslugiwany pakiet rozgloszeniowy")


def _akcesorium(tresc: list[int]) -> Akcesorium:
    if len(tresc) != 2 or not tresc[1] & 0x80:
        raise BlednaRamka("Niepoprawny pakiet akcesorium")
    gorne = (~tresc[1] >> 4) & 0x07
    dekoder = (gorne << 6) | (tresc[0] & 0x3F)
    para = (tresc[1] >> 1) & 0x03
    return Akcesorium(adres=(dekoder - 1) * 4 + para + 1, prosto=bool(tresc[1] & 1))


def _instrukcja(adres: int, instr: list[int]) -> Predkosc | Funkcje:
    if len(instr) == 2 and instr[0] == 0x3F:
        wartosc = instr[1] & 0x7F
        if wartosc == 1:
            raise BlednaRamka("Stop awaryjny pojedynczej lokomotywy nie jest uzywany")
        return Predkosc(adres, max(wartosc - 1, 0), bool(instr[1] & 0x80))
    if len(instr) == 1 and instr[0] & 0xE0 == 0x80:
        return Funkcje(adres, bool(instr[0] & 0x10), bool(instr[0] & 0x01))
    raise BlednaRamka("Nieobslugiwana instrukcja")
