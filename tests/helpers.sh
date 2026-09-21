# Gemeinsame Testhilfen, wird von den test_*.sh per source geladen.
# Die Tests brauchen keine echte Datenbank: mysql, mysqldump und ddev werden durch Stubs
# aus tests/stubs ersetzt, gearbeitet wird in einem Wegwerf-Ordner.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$TESTS_DIR")"
STUBS="$TESTS_DIR/stubs"
PASSFAIL=0

# Wegwerf-Umgebung anlegen: $T/tools (Kopie der Skripte samt Test-Configs),
# $T/elsewhere (fremder Arbeitsordner), $T/sql-dumps (Standard-Dump-Ordner)
setup() {
    T=$(mktemp -d "${TMPDIR:-/tmp}/dbtools-test.XXXXXX")
    mkdir -p "$T/tools" "$T/elsewhere"
    cp "$REPO/exportDB.sh" "$REPO/importDB.sh" "$REPO/dbtools-lib.sh" "$T/tools/"
    printf 'DB_HOST="h"\nDB_USER="u"\nDB_PASS="p"\nDB_NAME="n"\nPREFIX="proj-test"\n' > "$T/tools/db_test.conf"
    printf 'DB_HOST="h"\nDB_USER="u"\nDB_PASS="p"\nDB_NAME="n2"\nPREFIX="proj-other"\n' > "$T/tools/db_other.conf"
    export PATH="$STUBS:$PATH"
    export STUB_MYSQL_OUT="$T/mysql-in.sql"
    export STUB_DDEV_OUT="$T/ddev-in.sql" STUB_DDEV_ARGS="$T/ddev-args"
    unset STUB_DUMP_FAIL STUB_DUMP_SLEEP STUB_MYSQL_FAIL STUB_DDEV_FAIL
}

# ok "Beschreibung" "Bedingung": Bedingung per eval auswerten und Ergebnis ausgeben
ok() {
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        PASSFAIL=1
    fi
}
