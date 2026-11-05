#!/usr/bin/env bash
# Tworzy osobny schemat, generuje dane i zapisuje surowy wynik analizy planow.
# Uzycie: ORACLE_PASSWORD=... scripts/perf.sh [nazwa_kontenera]
set -euo pipefail

CONTAINER="${1:-signarail-oracle}"
ORACLE_PASSWORD="${ORACLE_PASSWORD:-signarail_sys}"
root="$(cd "$(dirname "$0")/.." && pwd)"
conn="signarail_perf/signarail_perf@//localhost/FREEPDB1"

docker exec -i "$CONTAINER" sqlplus -s "sys/${ORACLE_PASSWORD}@//localhost/FREEPDB1 as sysdba" <<SQL
WHENEVER SQLERROR CONTINUE
DROP USER signarail_perf CASCADE;
WHENEVER SQLERROR EXIT FAILURE
CREATE USER signarail_perf IDENTIFIED BY signarail_perf QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, ALTER SYSTEM TO signarail_perf;
GRANT SELECT ON v_\$session TO signarail_perf;
GRANT SELECT ON v_\$sql TO signarail_perf;
GRANT SELECT ON v_\$sql_plan TO signarail_perf;
GRANT SELECT ON v_\$sql_plan_statistics_all TO signarail_perf;
EXIT
SQL

docker exec -u root "$CONTAINER" rm -rf /tmp/signarail-db
docker cp "$root/database" "$CONTAINER:/tmp/signarail-db"
docker exec -u root "$CONTAINER" chmod -R a+rwX /tmp/signarail-db

docker exec -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 -w /tmp/signarail-db "$CONTAINER" sqlplus -s "$conn" @install.sql
docker exec -w /tmp/signarail-db/perf "$CONTAINER" sqlplus -s "$conn" @01_generator.sql
docker exec -w /tmp/signarail-db/perf "$CONTAINER" sqlplus -s "$conn" @02_analiza.sql \
    | tee "$root/database/perf/wyniki.txt"
