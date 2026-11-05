import argparse
import logging
import os
import time

import oracledb

from .bridge import symuluj_krok, wyslij_oczekujace


def main() -> None:
    parser = argparse.ArgumentParser(description="Most SignaRail 87 <-> centrala DCC (symulacja)")
    parser.add_argument("--dsn", default=os.environ.get("SIGNARAIL_DB_DSN", "localhost:1521/FREEPDB1"))
    parser.add_argument("--user", default=os.environ.get("SIGNARAIL_DB_USER", "signarail"))
    parser.add_argument("--password", default=os.environ.get("SIGNARAIL_DB_PASSWORD", "signarail"))
    parser.add_argument("--interval", type=float, default=1.0, help="sekundy miedzy obiegami")
    parser.add_argument("--no-simulate", action="store_true", help="tylko wysylka, bez ruchu pociagow")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    log = logging.getLogger("makieta-bridge")

    while True:
        try:
            with oracledb.connect(user=args.user, password=args.password, dsn=args.dsn) as polaczenie:
                log.info("Polaczono z %s", args.dsn)
                while True:
                    wyslij_oczekujace(polaczenie)
                    if not args.no_simulate:
                        symuluj_krok(polaczenie)
                    time.sleep(args.interval)
        except oracledb.Error as e:
            log.warning("Utrata polaczenia z baza (%s), ponowienie za 5 s", e)
            time.sleep(5)


if __name__ == "__main__":
    main()
