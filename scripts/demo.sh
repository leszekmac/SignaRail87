#!/usr/bin/env bash
# Przejscie przez system na uruchomionym docker compose: wyszukanie, sprzedaz,
# proba overbookingu, opoznienie z powiadomieniami, kurs na makiecie.
set -euo pipefail

API="${API:-http://localhost:8080}"
DAY="$(date -d '+2 days' +%F)"

show() { printf '\n=== %s\n' "$1"; }
json() { python3 -m json.tool --no-ensure-ascii; }

show "Polaczenie Rzeszow -> Gdansk ($DAY)"
connections="$(curl -fsS "$API/api/connections?from=RZE&to=GDA&departure=${DAY}T05:00:00")"
echo "$connections" | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    print("{} -> {}, przesiadki: {}, {} min".format(c["departure"], c["arrival"], c["transfers"], c["durationMinutes"]))
    for l in c["legs"]:
        print("   {:8} {} {} -> {} {}".format(l["trainNumber"], l["fromName"], l["departure"][11:16], l["toName"], l["arrival"][11:16]))'
course="$(echo "$connections" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["legs"][0]["courseId"])')"

show "Zakup biletu na kurs $course"
ticket="$(curl -fsS -X POST "$API/api/book-ticket" -H 'Content-Type: application/json' \
    -H "Idempotency-Key: demo-$RANDOM$RANDOM" \
    -d "{\"courseId\":$course,\"from\":\"RZE\",\"to\":\"KRK\",\"passenger\":\"Anna Nowak\",\"email\":\"anna@example.com\",\"phone\":\"+48500100200\"}")"
echo "$ticket" | json
seat="$(echo "$ticket" | python3 -c 'import json,sys; print(json.load(sys.stdin)["seatId"])')"

show "Proba sprzedazy tego samego miejsca na nakladajacym sie odcinku"
curl -sS -X POST "$API/api/book-ticket" -H 'Content-Type: application/json' \
    -d "{\"courseId\":$course,\"from\":\"TRN\",\"to\":\"KTW\",\"passenger\":\"Jan Kowalski\",\"email\":\"jan@example.com\",\"seatId\":$seat}" | json

show "Zgloszenie opoznienia"
curl -fsS -X POST "$API/api/delays" -H 'Content-Type: application/json' \
    -d "{\"courseId\":$course,\"minutes\":25,\"reason\":\"Oblodzona siec trakcyjna\"}" | json
sleep 2
curl -fsS "$API/api/notifications/stats" | json

show "Makieta: przygotowanie i uruchomienie kursu 1"
curl -fsS -X POST "$API/api/layout/courses/1/prepare" -o /dev/null
curl -fsS "$API/api/layout/courses" | json
curl -fsS -X POST "$API/api/layout/courses/1/start" -o /dev/null
sleep 6
curl -fsS "$API/api/layout/commands?limit=10" | json
curl -fsS "$API/api/layout/blocks" | json
echo
echo "Log mostu: docker compose logs makieta-bridge"
