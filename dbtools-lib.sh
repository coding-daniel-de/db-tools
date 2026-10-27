# Gemeinsame Funktionen für exportDB.sh und importDB.sh.
# Wird nur per source geladen (nicht direkt ausführen). Erwartet, dass SCRIPT_DIR gesetzt ist.

# Verzeichnisse für Dumps (DUMP_DIR), DDEV-Dumps (DDEV_DUMP_DIR), Backups (BACKUP_DIR, Fallback
# DUMP_DIR) und Patch-Dateien (PATCH_DIR)
# ermitteln: Default, optional überschrieben durch dbtools.conf (relative Pfade gelten relativ
# zum Skript-Ordner). BACKUP_ENVS (Liste der Umgebungen für backupAll.sh) wird nur durchgereicht.
# DDEV_DUMP_DIR fällt auf DUMP_DIR zurück, wenn es nicht gesetzt ist.
resolve_dirs() {
    DUMP_DIR="${SCRIPT_DIR}/../sql-dumps"
    PATCH_DIR="${SCRIPT_DIR}/../sql-patches"
    DDEV_DUMP_DIR=""
    BACKUP_DIR=""
    BACKUP_ENVS=""
    if [ -f "${SCRIPT_DIR}/dbtools.conf" ]; then
        source "${SCRIPT_DIR}/dbtools.conf"
    fi
    [ -z "$DDEV_DUMP_DIR" ] && DDEV_DUMP_DIR="$DUMP_DIR"
    [ -z "$BACKUP_DIR" ] && BACKUP_DIR="$DUMP_DIR"
    case "$DDEV_DUMP_DIR" in
        /*) ;;
        *) DDEV_DUMP_DIR="${SCRIPT_DIR}/${DDEV_DUMP_DIR}" ;;
    esac
    case "$DUMP_DIR" in
        /*) ;;
        *) DUMP_DIR="${SCRIPT_DIR}/${DUMP_DIR}" ;;
    esac
    case "$BACKUP_DIR" in
        /*) ;;
        *) BACKUP_DIR="${SCRIPT_DIR}/${BACKUP_DIR}" ;;
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

# Ja/Nein-Frage $1 stellen, Rückgabe 0 bei y/Y. Im Terminal genügt ein Tastendruck ohne Enter,
# bei umgeleiteter Eingabe (Pipe, Tests) wird eine ganze Zeile gelesen, sonst bliebe deren
# Zeilenumbruch für die nächste Abfrage (z. B. das Passwort) liegen.
ask_yes_no() {
    local answer
    if [ -t 0 ]; then
        read -r -n 1 -p "$1" answer
        [ -n "$answer" ] && echo
    else
        read -r -p "$1" answer
    fi
    [[ "$answer" =~ ^[yY]$ ]]
}
