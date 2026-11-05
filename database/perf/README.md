# Analiza wydajności

Pomiary na generowanych danych, wykonane skryptem `scripts/perf.sh`. Surowy wynik, z pełnymi planami, jest w [`wyniki.txt`](wyniki.txt).

| Tabela | Wierszy |
|---|---:|
| `kursy_rozkladowe` | 182 500 |
| `kursy_postoje` | 2 190 000 |
| `rezerwacje` | 1 824 990 |
| `rezerwacje_odcinki` | 5 201 280 |

Środowisko: Oracle AI Database 26ai Free w Dockerze na dysku NVMe, 500 pociągów, 120 stacji, 365 dni.

Liczby pochodzą z `DBMS_XPLAN.DISPLAY_CURSOR` z `ALLSTATS LAST`, czyli z faktycznego wykonania, a nie z estymat `EXPLAIN PLAN`. Przed każdym zapytaniem bufor był opróżniany. Główną miarą są **bufory**: odczyty logiczne nie zależą od sprzętu, a czasy poniżej 10 ms są niemiarodajne.

## Odjazdy ze stacji w 12-godzinnym oknie

To zapytanie wykonuje się dla każdej stacji w każdej rundzie wyszukiwania, więc decyduje o czasie odpowiedzi.

```sql
SELECT COUNT(*), MIN(odjazd) FROM kursy_postoje
 WHERE id_stacji = :st AND odjazd >= :t0 AND odjazd < :t0 + 0.5;
```

| Wariant | Plan | Bufory | Czas | Wierszy |
|---|---|---:|---:|---:|
| Tabela płaska, bez indeksu | `TABLE ACCESS FULL` | 10 853 | 40 ms | 31 |
| Partycje miesięczne | `PARTITION RANGE ITERATOR` + `FULL` | 949 | 10 ms | 31 |
| Partycje i indeks lokalny | `PARTITION RANGE ITERATOR` + `INDEX RANGE SCAN` | **3** | ≤ 10 ms | 31 |

Partycjonowanie zmniejsza odczyty 11-krotnie przez samo odcięcie pozostałych miesięcy, a indeks `(id_stacji, odjazd)` około 3600-krotnie względem stanu wyjściowego. Równość na pierwszej kolumnie i zakres na drugiej to właściwa kolejność: odwrotna musiałaby przejść wszystkie stacje w oknie czasu. Indeks jest kompresowany (`COMPRESS 1`), bo `id_stacji` powtarza się masowo.

Partycje mają też zaletę operacyjną: archiwizacja to `DROP PARTITION`, a nie masowy `DELETE`.

## Pasażerowie kursu do powiadomienia

```sql
SELECT COUNT(*), SUM(cena) FROM rezerwacje WHERE id_kursu = :kurs AND status = 'OPLACONA';
```

| Wariant | Plan | Bufory | Czas | Wierszy |
|---|---|---:|---:|---:|
| Bez indeksu | `TABLE ACCESS FULL` | 51 491 | 130 ms | 30 |
| Indeks `(id_kursu, status)` | `INDEX RANGE SCAN` + `BY INDEX ROWID BATCHED` | **63** | ≤ 10 ms | 30 |

Różnica jest około 800-krotna. Przy masowych opóźnieniach zapytanie wykonuje się dla każdego kursu, więc pełny skan obciążałby bufor i dysk.

## Wyszukiwanie: algorytm rundowy a rekurencyjny CTE

Ta sama relacja i to samo okno czasu, z 12-godzinnym horyzontem i minimalną przesiadką 8 minut.

| Maks. przesiadek | `PKG_ROZKLAD.szukaj` | Rekurencyjny CTE | Ścieżek do celu w CTE |
|---:|---:|---:|---:|
| 0 | ≤ 10 ms | ≤ 10 ms | 0 |
| 1 | 110 ms | 3,9 s | 18 |
| 2 | 240 ms | **352 s** | 28 128 |
| 3 | 250 ms | nie mierzono | – |

Trzech przesiadek dla CTE nie mierzono: już dwie trwały prawie 6 minut.

Warianty nie robią dokładnie tego samego: algorytm rundowy zwraca do 5 najlepszych połączeń, a CTE wylicza wszystkie dopuszczalne ścieżki, które dopiero potem trzeba ocenić. Na tym właśnie polega różnica. Etykiety odcinają gałąź, gdy tylko nie poprawia ona czasu dotarcia do stacji, więc koszt rośnie z liczbą stacji, a nie ścieżek. Czas algorytmu rundowego prawie nie rośnie między 2 a 3 przesiadkami, a czas CTE między 1 a 2 przesiadkami rośnie około 90-krotnie.

## Powtórzenie

```bash
docker compose up -d --wait oracle
scripts/perf.sh
```

Skrypt tworzy osobny schemat `signarail_perf` i potrzebuje około pół godziny, z czego 6 minut to pomiar CTE. Czasy zależą od sprzętu, ale liczba buforów powinna być bardzo zbliżona.
