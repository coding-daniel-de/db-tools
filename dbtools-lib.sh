# Gemeinsame Funktionen für exportDB.sh und importDB.sh.
# Wird nur per source geladen (nicht direkt ausführen). Erwartet, dass SCRIPT_DIR gesetzt ist.

# Verzeichnisse für Dumps (DUMP_DIR), DDEV-Dumps (DDEV_DUMP_DIR), Backups (BACKUP_DIR, Fallback
# DUMP_DIR) und Patch-Dateien (PATCH_DIR)
# ermitteln: Default (DUMP_DIR: $HOME/sql-dumps, unabhängig vom Ablageort der Skripte), optional überschrieben durch dbtools.conf (relative Pfade gelten relativ
# zum Skript-Ordner). BACKUP_ENVS (Liste der Umgebungen für backupAll.sh) wird nur durchgereicht.
# DDEV_DUMP_DIR fällt auf DUMP_DIR zurück, wenn es nicht gesetzt ist.
resolve_dirs() {
    DUMP_DIR="${HOME}/sql-dumps"
    PATCH_DIR="${HOME}/sql-patches"
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

# --- Gemeinsame Funktionen für sendDB.sh und fetchDB.sh (Dateien zwischen lokal und Server) ---

# Remote-Config remote_<name>.conf aus dem Skript-Ordner laden. Setzt SSH_HOST, REMOTE_DUMP_DIR und
# REMOTE_PATCH_DIR (Standard: sql-dumps und sql-patches, relativ zum Home auf dem Server).
load_remote_conf() {
    local NAME="$1" CONF
    if ! [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Fehler: Ungültiger Servername '${NAME}'!"
        return 1
    fi
    CONF="${SCRIPT_DIR}/remote_${NAME}.conf"
    if [ ! -f "$CONF" ]; then
        echo "Fehler: '${CONF}' nicht gefunden! Vorlage: remote_template.conf"
        return 1
    fi
    SSH_HOST=""
    REMOTE_DUMP_DIR="sql-dumps"
    REMOTE_PATCH_DIR="sql-patches"
    source "$CONF"
    if [ -z "$SSH_HOST" ]; then
        echo "Fehler: In '${CONF}' fehlt SSH_HOST!"
        return 1
    fi
}

# Optionen von db-send/db-fetch auswerten (an beliebiger Stelle): --patch, --env <name>, --env=<name>.
# Setzt PATCH und ENV_FILTER, die Positionsparameter landen im Array TRANSFER_ARGS.
parse_transfer_args() {
    PATCH=0
    ENV_FILTER=""
    TRANSFER_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --patch)
                PATCH=1
                ;;
            --env)
                if [ -z "$2" ]; then
                    echo "Fehler: --env braucht eine Umgebung!"
                    return 1
                fi
                ENV_FILTER="$2"
                shift
                ;;
            --env=*)
                ENV_FILTER="${1#--env=}"
                ;;
            --*)
                echo "Fehler: Unbekannte Option '${1}'!"
                return 1
                ;;
            *)
                TRANSFER_ARGS+=("$1")
                ;;
        esac
        shift
    done
}

# PREFIX der Umgebung $1 aus db_<name>.conf lesen und in ENV_PREFIX ablegen
read_env_prefix() {
    local CONF="${SCRIPT_DIR}/db_${1}.conf"
    if ! [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || [ ! -f "$CONF" ]; then
        echo "Fehler: Umgebung '${1}' unbekannt, '${CONF}' nicht gefunden!"
        return 1
    fi
    ENV_PREFIX=$(grep -E '^PREFIX=' "$CONF" | head -n 1 | cut -d '=' -f2- | tr -d '"')
    if [ -z "$ENV_PREFIX" ]; then
        echo "Fehler: In '${CONF}' wurde kein PREFIX gefunden!"
        return 1
    fi
}

# Passt der Dateiname $2 zur Art $1? "dump": .sql.gz und .sql.gz.gpg, "patch": .sql und .sql.gz
# (verschlüsselte Patches nimmt der Import nicht).
transfer_name_ok() {
    case "$1:$2" in
        dump:*.sql.gz|dump:*.sql.gz.gpg|patch:*.sql|patch:*.sql.gz) return 0 ;;
        *) return 1 ;;
    esac
}

# Dateinamen nur aus unkritischen Zeichen, weil sie in scp/ssh-Pfade eingehen
transfer_name_safe() {
    [[ "$1" =~ ^[A-Za-z0-9._+-]+$ ]]
}

# Auswahlliste aus dem Array ITEMS (Dateinamen, neueste zuerst) anzeigen, Nummer abfragen
# (Enter = 1 = neueste) und PICKED setzen. $1 ist die Überschrift.
pick_item() {
    local I SELECTION
    echo "$1"
    for I in "${!ITEMS[@]}"; do
        echo "  $((I + 1))) ${ITEMS[$I]}"
    done
    read -r -p "Nummer wählen [1 = neueste]: " SELECTION
    [ -z "$SELECTION" ] && SELECTION=1
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#ITEMS[@]}" ]; then
        echo "Fehler: Ungültige Auswahl '${SELECTION}'!"
        return 1
    fi
    PICKED="${ITEMS[$((SELECTION - 1))]}"
}

# --- SSH-Tunnel zur Datenbank (optional, pro Umgebung in db_<name>.conf) ---

# Tunnel schließen (wird per EXIT-Trap aufgerufen, auch bei Abbruch)
close_tunnel() {
    if [ -n "$TUNNEL_SOCK" ]; then
        ssh -S "$TUNNEL_SOCK" -O exit "$SSH_TUNNEL" >/dev/null 2>&1
        rm -f -- "$TUNNEL_SOCK"
        TUNNEL_SOCK=""
    fi
}

# Tunnel öffnen: lokaler Port TUNNEL_PORT -> TUNNEL_REMOTE (Host:Port der DB vom Server aus gesehen)
# über den SSH-Alias SSH_TUNNEL. Danach verbindet sich das Tool mit 127.0.0.1:TUNNEL_PORT.
# Passphrase-Abfrage von ssh passiert hier, der Tunnel läuft dann im Hintergrund bis zum Skript-Ende.
open_tunnel() {
    TUNNEL_SOCK=$(mktemp -u "${TMPDIR:-/tmp}/dbtools-tunnel.XXXXXX")
    echo "Öffne SSH-Tunnel über '${SSH_TUNNEL}' (127.0.0.1:${TUNNEL_PORT} -> ${TUNNEL_REMOTE})..."
    if ! ssh -f -N -M -S "$TUNNEL_SOCK" -o ExitOnForwardFailure=yes \
            -L "127.0.0.1:${TUNNEL_PORT}:${TUNNEL_REMOTE}" "$SSH_TUNNEL"; then
        echo "Fehler: SSH-Tunnel über '${SSH_TUNNEL}' konnte nicht geöffnet werden (Port ${TUNNEL_PORT} belegt oder Verbindung nicht möglich)!"
        TUNNEL_SOCK=""
        return 1
    fi
    trap close_tunnel EXIT
}

# db_<name>.conf $1 laden. Optionale Werte werden vorher zurückgesetzt, damit nichts aus einer
# anderen Umgebung stehen bleibt. Mit SSH_TUNNEL wird der Tunnel geöffnet und DB_HOST/DB_PORT auf
# 127.0.0.1:TUNNEL_PORT gesetzt (DB_HOST der Config gilt dann nicht). Setzt DB_PORT_ARGS für mysql/mysqldump
# (-P nur, wenn DB_PORT gesetzt ist, auch ohne Tunnel möglich).
load_db_conf() {
    unset SSH_TUNNEL TUNNEL_PORT TUNNEL_REMOTE DB_PORT
    source "$1"
    DB_PORT_ARGS=()
    if [ -n "$SSH_TUNNEL" ]; then
        [ -z "$TUNNEL_PORT" ] && TUNNEL_PORT=3307
        [ -z "$TUNNEL_REMOTE" ] && TUNNEL_REMOTE="127.0.0.1:3306"
        open_tunnel || return 1
        DB_HOST="127.0.0.1"
        DB_PORT="$TUNNEL_PORT"
    fi
    [ -n "$DB_PORT" ] && DB_PORT_ARGS=(-P "$DB_PORT")
    return 0
}
