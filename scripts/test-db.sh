#!/usr/bin/env bash
# Laduje pakiety testowe i uruchamia utPLSQL. Konczy sie bledem przy kazdej porazce.
# Uzycie: scripts/test-db.sh [nazwa_kontenera]
set -euo pipefail

CONTAINER="${1:-signarail-oracle}"
DB_USER="${DB_USER:-signarail}"
DB_PASSWORD="${DB_PASSWORD:-signarail}"
root="$(cd "$(dirname "$0")/.." && pwd)"

docker exec -u root "$CONTAINER" rm -rf /tmp/signarail-tests
docker cp "$root/database/tests" "$CONTAINER:/tmp/signarail-tests"
docker exec -u root "$CONTAINER" chmod -R a+rwX /tmp/signarail-tests

out="$(docker exec -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 -w /tmp/signarail-tests "$CONTAINER" \
    sqlplus -s "${DB_USER}/${DB_PASSWORD}@//localhost/FREEPDB1" @run_tests.sql)" || { echo "$out"; exit 1; }
echo "$out"
# Linia podsumowania: "N tests, 0 failed, 0 errored, 0 disabled, 0 warning(s)"
echo "$out" | grep -Eq '^[1-9][0-9]* tests, 0 failed, 0 errored'
