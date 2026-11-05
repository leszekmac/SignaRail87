#!/bin/bash
# Pierwszy start kontenera Oracle: instalacja schematu i danych demonstracyjnych.
set -e
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
conn="${APP_USER}/${APP_USER_PASSWORD}@//localhost/FREEPDB1"

cd /signarail-database
sqlplus -s "$conn" @install.sql
cd seed
sqlplus -s "$conn" @seed_demo.sql
