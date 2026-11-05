#!/usr/bin/env bash
# Instaluje utPLSQL w kontenerze Oracle. Wymaga hasla SYS (ORACLE_PASSWORD).
# Uzycie: scripts/install-utplsql.sh [nazwa_kontenera]
set -euo pipefail

CONTAINER="${1:-signarail-oracle}"
ORACLE_PASSWORD="${ORACLE_PASSWORD:-signarail_sys}"
VERSION="v.3.2.3"
URL="https://github.com/utPLSQL/utPLSQL/releases/download/${VERSION}/utPLSQL.tar.gz"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL "$URL" -o "$work/utPLSQL.tar.gz"
tar -xzf "$work/utPLSQL.tar.gz" -C "$work"

docker exec -u root "$CONTAINER" rm -rf /tmp/utPLSQL
docker cp "$work/utPLSQL" "$CONTAINER:/tmp/utPLSQL"
docker exec -u root "$CONTAINER" chmod -R a+rwX /tmp/utPLSQL
docker exec -w /tmp/utPLSQL/source "$CONTAINER" bash -c \
    "sqlplus -s 'sys/${ORACLE_PASSWORD}@//localhost/FREEPDB1 as sysdba' @install_headless.sql ut3 ut3_pwd USERS"
