# Gemeinsame Funktionen für exportDB.sh und importDB.sh.
# Wird nur per source geladen (nicht direkt ausführen). Erwartet, dass SCRIPT_DIR gesetzt ist.

# Verzeichnisse für Dumps (DUMP_DIR) und Patch-Dateien (PATCH_DIR) ermitteln: Default,
# optional überschrieben durch dbtools.conf (relative Pfade gelten relativ zum Skript-Ordner)
resolve_dirs() {
    DUMP_DIR="${SCRIPT_DIR}/../sql-dumps"
    PATCH_DIR="${SCRIPT_DIR}/../sql-patches"
    if [ -f "${SCRIPT_DIR}/dbtools.conf" ]; then
        source "${SCRIPT_DIR}/dbtools.conf"
    fi
    case "$DUMP_DIR" in
        /*) ;;
        *) DUMP_DIR="${SCRIPT_DIR}/${DUMP_DIR}" ;;
    esac
    case "$PATCH_DIR" in
        /*) ;;
        *) PATCH_DIR="${SCRIPT_DIR}/${PATCH_DIR}" ;;
    esac
}

# Prüfen, ob gpg für verschlüsselte Dumps installiert ist
require_gpg() {
    if ! command -v gpg >/dev/null 2>&1; then
        echo "Fehler: gpg ist nicht installiert, wird für verschlüsselte Dumps aber benötigt!"
        return 1
    fi
}
