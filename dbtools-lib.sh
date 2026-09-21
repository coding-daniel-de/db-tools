# Gemeinsame Funktionen für exportDB.sh und importDB.sh.
# Wird nur per source geladen (nicht direkt ausführen). Erwartet, dass SCRIPT_DIR gesetzt ist.

# Dump-Verzeichnis ermitteln und in DUMP_DIR ablegen: Default, optional überschrieben
# durch dbtools.conf (relativer Pfad gilt relativ zum Skript-Ordner)
resolve_dump_dir() {
    DUMP_DIR="${SCRIPT_DIR}/../sql-dumps"
    if [ -f "${SCRIPT_DIR}/dbtools.conf" ]; then
        source "${SCRIPT_DIR}/dbtools.conf"
    fi
    case "$DUMP_DIR" in
        /*) ;;
        *) DUMP_DIR="${SCRIPT_DIR}/${DUMP_DIR}" ;;
    esac
}

# Prüfen, ob gpg für verschlüsselte Dumps installiert ist
require_gpg() {
    if ! command -v gpg >/dev/null 2>&1; then
        echo "Fehler: gpg ist nicht installiert, wird für verschlüsselte Dumps aber benötigt!"
        return 1
    fi
}
