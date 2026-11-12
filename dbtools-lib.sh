# Gemeinsame Funktionen für exportDB.sh und importDB.sh.
# Wird nur per source geladen (nicht direkt ausführen). Erwartet, dass SCRIPT_DIR gesetzt ist.

# --- Config-Dateien: User-Ordner, conf/, Root ---

# Suchorte für Configs in Rangfolge (höchste zuerst), je einer pro Zeile. Ein weiterer Ordner wäre
# eine einzelne Zeile hier. Der User-Ordner überschreibt das Globale (Installation), conf/ geht vor
# dem Root (Übergang, bestehende Configs müssen nicht verschoben werden).
conf_dirs() {
    printf '%s\n' "${HOME}/db-tools-conf" "${SCRIPT_DIR}/conf" "${SCRIPT_DIR}"
}

# Config-Datei $1 (z. B. db_dev.conf) suchen: erste Fundstelle in der Reihenfolge von conf_dirs
# gewinnt (ganze Datei, kein Mischen). Gibt den Pfad aus, Rückgabe 1 wenn es sie nirgends gibt.
find_conf() {
    local dir
    while IFS= read -r dir; do
        if [ -f "${dir}/$1" ]; then
            printf '%s\n' "${dir}/$1"
            return 0
        fi
    done < <(conf_dirs)
    return 1
}

# Alle Fundstellen von $1, je eine pro Zeile in Rangfolge (die erste gewinnt). Rückgabe 1 ohne Treffer.
find_conf_all() {
    local dir found=1
    while IFS= read -r dir; do
        if [ -f "${dir}/$1" ]; then
            printf '%s\n' "${dir}/$1"
            found=0
        fi
    done < <(conf_dirs)
    return $found
}

# Suchorte für Meldungen: "'a', 'b' und 'c'"
conf_search_text() {
    local -a dirs=()
    local dir out="" i
    while IFS= read -r dir; do dirs+=("'${dir}'"); done < <(conf_dirs)
    for i in "${!dirs[@]}"; do
        if [ "$i" -eq 0 ]; then out="${dirs[$i]}"
        elif [ "$i" -eq $((${#dirs[@]} - 1)) ]; then out+=" und ${dirs[$i]}"
        else out+=", ${dirs[$i]}"
        fi
    done
    printf '%s' "$out"
}

# dbtools.conf schichten: alle Fundstellen nacheinander laden, die niedrigste Rangfolge zuerst, damit
# höhere (User-Ordner vor conf/ vor Root) einzelne Werte überschreiben und der Rest Default bleibt.
# CHECK_CONF_PERMS (Rechte-Warnung für db_*.conf) hat den Standard 1.
load_dbtools_conf() {
    CHECK_CONF_PERMS=1
    local f i
    local -a files=()
    mapfile -t files < <(find_conf_all dbtools.conf)
    for ((i = ${#files[@]} - 1; i >= 0; i--)); do
        source "${files[$i]}"
    done
}

# Verzeichnisse für Dumps (DUMP_DIR), DDEV-Dumps (DDEV_DUMP_DIR), Backups (BACKUP_DIR, Fallback
# DUMP_DIR) und Patch-Dateien (PATCH_DIR)
# ermitteln: Default (DUMP_DIR: $HOME/sql-dumps, unabhängig vom Ablageort der Skripte), optional überschrieben durch dbtools.conf (geschichtet, siehe load_dbtools_conf; relative Pfade gelten relativ
# zum Skript-Ordner). BACKUP_ENVS (Liste der Umgebungen für backupAll.sh) wird nur durchgereicht.
# DDEV_DUMP_DIR fällt auf DUMP_DIR zurück, wenn es nicht gesetzt ist.
resolve_dirs() {
    DUMP_DIR="${HOME}/sql-dumps"
    PATCH_DIR="${HOME}/sql-patches"
    DDEV_DUMP_DIR=""
    BACKUP_DIR=""
    BACKUP_ENVS=""
    load_dbtools_conf
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

# Remote-Config remote_<name>.conf (conf/ oder Skript-Ordner) laden. Setzt SSH_HOST, REMOTE_DUMP_DIR und
# REMOTE_PATCH_DIR (Standard: sql-dumps und sql-patches, relativ zum Home auf dem Server).
load_remote_conf() {
    local NAME="$1" CONF
    if ! [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Fehler: Ungültiger Servername '${NAME}'!"
        return 1
    fi
    if ! CONF=$(find_conf "remote_${NAME}.conf"); then
        echo "Fehler: 'remote_${NAME}.conf' nicht gefunden (gesucht in $(conf_search_text))! Vorlage: conf/remote_template.conf"
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

# Optionen von db-send/db-fetch auswerten (an beliebiger Stelle): --patch, --configs, --env <name>, --env=<name>.
# Setzt PATCH, SHOW_CONFIGS und ENV_FILTER, die Positionsparameter landen im Array TRANSFER_ARGS.
parse_transfer_args() {
    PATCH=0
    SHOW_CONFIGS=0
    ENV_FILTER=""
    TRANSFER_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --patch)
                PATCH=1
                ;;
            --configs)
                SHOW_CONFIGS=1
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
    local CONF
    if ! [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || ! CONF=$(find_conf "db_${1}.conf"); then
        echo "Fehler: Umgebung '${1}' unbekannt, 'db_${1}.conf' nicht gefunden (gesucht in $(conf_search_text))!"
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

# Rechte-Warnung: hat eine db_*.conf (enthält Passwörter) Rechte für Gruppe oder andere, kommt eine
# Warnung auf stderr, der Lauf geht weiter. Eine Warnung pro Datei und Lauf. Abschaltbar mit
# CHECK_CONF_PERMS=0 in der dbtools.conf.
CONF_PERM_WARNED=""
warn_conf_perms() {
    local mode
    case "$CONF_PERM_WARNED" in *"|$1|"*) return 0 ;; esac
    [ "$(load_dbtools_conf >/dev/null 2>&1; echo "$CHECK_CONF_PERMS")" = "0" ] && return 0
    mode=$(stat -c %a -- "$1" 2>/dev/null) || return 0
    if [ $((8#$mode & 8#077)) -ne 0 ]; then
        CONF_PERM_WARNED+="|$1|"
        echo "Warnung: '${1}' hat die Rechte ${mode}, Gruppe oder andere können die Zugangsdaten lesen. Empfehlung: chmod 600 '${1}' (Warnung abschaltbar mit CHECK_CONF_PERMS=0 in der dbtools.conf)." >&2
    fi
    return 0
}

# db_<name>.conf $1 laden. Optionale Werte werden vorher zurückgesetzt, damit nichts aus einer
# anderen Umgebung stehen bleibt. Mit SSH_TUNNEL wird der Tunnel geöffnet und DB_HOST/DB_PORT auf
# 127.0.0.1:TUNNEL_PORT gesetzt (DB_HOST der Config gilt dann nicht). Setzt DB_PORT_ARGS für mysql/mysqldump
# (-P nur, wenn DB_PORT gesetzt ist, auch ohne Tunnel möglich).
load_db_conf() {
    unset SSH_TUNNEL TUNNEL_PORT TUNNEL_REMOTE DB_PORT
    warn_conf_perms "$1"
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

# --- Übersicht der Configs (--configs, db-configs, Tab-Vervollständigung) ---

# Wert von $2 aus der Config $1 lesen, ohne sie auszuführen (nur Zeilen der Form NAME=wert)
conf_value() {
    grep -E "^${2}=" "$1" | head -n 1 | cut -d '=' -f2- | tr -d '"'"'"
}

# Namen der Configs der Art $1 (db oder remote) ausgeben, eindeutig und sortiert. Die Vorlage
# (<art>_template.conf) zählt nicht.
conf_names() {
    local kind="$1" dir f name
    while IFS= read -r dir; do
        for f in "${dir}/${kind}_"*.conf; do
            [ -f "$f" ] || continue
            name="${f##*/}"; name="${name#"${kind}_"}"; name="${name%.conf}"
            [ "$name" = "template" ] && continue
            printf '%s\n' "$name"
        done
    done < <(conf_dirs) | sort -u
}

# Tabelle der Configs ausgeben: print_configs <db|remote|all>. Passwörter werden nie angezeigt.
# Spalten: Name, Art, Ziel, Datei und ggf. ein Hinweis (doppelt/veraltet, unvollständig). Die Datei
# ist der tatsächlich verwendete Pfad (Rangfolge wie conf_dirs), überdeckte Dateien werden markiert. Ohne Treffer kommt ein Hinweis auf die Vorlage.
print_configs() {
    local KINDS KIND NAME FILE ART TARGET NOTE MISSING V OTHER WORD
    local -a ROWS=()
    case "$1" in
        all) KINDS=(db remote) ;;
        *) KINDS=("$1") ;;
    esac
    for KIND in "${KINDS[@]}"; do
        while IFS= read -r NAME; do
            [ -n "$NAME" ] || continue
            FILE=$(find_conf "${KIND}_${NAME}.conf")
            NOTE=""
            # weitere Fundstellen sind von der ersten überdeckt; im Root heißt das "veraltet" (Übergang)
            while IFS= read -r OTHER; do
                [ "$OTHER" = "$FILE" ] && continue
                if [ "$OTHER" = "${SCRIPT_DIR}/${KIND}_${NAME}.conf" ]; then WORD="veraltet"; else WORD="überdeckt"; fi
                NOTE+="${NOTE:+; }doppelt/${WORD}: ${OTHER} (gewinnt: ${FILE})"
            done < <(find_conf_all "${KIND}_${NAME}.conf")
            [ -n "$NOTE" ] && NOTE="Hinweis: ${NOTE}"
            MISSING=""
            if [ "$KIND" = "db" ]; then
                ART="Datenbank-Umgebung"
                for V in DB_HOST DB_USER DB_NAME PREFIX; do
                    [ -n "$(conf_value "$FILE" "$V")" ] || MISSING+=" ${V}"
                done
                if [ -n "$MISSING" ]; then
                    TARGET="-"
                else
                    TARGET="$(conf_value "$FILE" DB_HOST)/$(conf_value "$FILE" DB_NAME), Präfix $(conf_value "$FILE" PREFIX)"
                    [ -n "$(conf_value "$FILE" SSH_TUNNEL)" ] && TARGET+=", Tunnel $(conf_value "$FILE" SSH_TUNNEL)"
                fi
            else
                ART="Server"
                [ -n "$(conf_value "$FILE" SSH_HOST)" ] || MISSING=" SSH_HOST"
                if [ -n "$MISSING" ]; then
                    TARGET="-"
                else
                    TARGET="SSH: $(conf_value "$FILE" SSH_HOST)"
                fi
            fi
            if [ -n "$MISSING" ]; then
                NOTE="Hinweis: unvollständig, es fehlt:${MISSING}${NOTE:+; ${NOTE#Hinweis: }}"
            fi
            ROWS+=("${NAME}"$'\t'"${ART}"$'\t'"${TARGET}"$'\t'"${FILE}"$'\t'"${NOTE}")
        done < <(conf_names "$KIND")
    done
    if [ "${#ROWS[@]}" -eq 0 ]; then
        case "$1" in
            db) echo "Keine Datenbank-Umgebungen gefunden. Vorlage: conf/db_template.conf (kopieren nach conf/db_<name>.conf oder ~/db-tools-conf/)." ;;
            remote) echo "Keine Server gefunden. Vorlage: conf/remote_template.conf (kopieren nach conf/remote_<name>.conf)." ;;
            *) echo "Keine Configs gefunden. Vorlagen: conf/db_template.conf, conf/remote_template.conf." ;;
        esac
        return 0
    fi
    # Spaltenbreiten bestimmen; "Art" nur in der Gesamtübersicht
    local -a HEAD=(Name Art Ziel Datei)
    local -a W=(0 0 0 0)
    local ROW I
    local -a F
    for I in 0 1 2 3; do W[$I]=${#HEAD[$I]}; done
    for ROW in "${ROWS[@]}"; do
        IFS=$'\t' read -r -a F <<< "$ROW"
        for I in 0 1 2 3; do
            [ "${#F[$I]}" -gt "${W[$I]}" ] && W[$I]=${#F[$I]}
        done
    done
    # printf rechnet bei Umlauten mit Bytes, deshalb wird von Hand aufgefüllt
    pad() { printf '%s%*s' "$1" $(($2 - ${#1})) ''; }
    if [ "$1" = "all" ]; then
        echo "$(pad "${HEAD[0]}" "${W[0]}")  $(pad "${HEAD[1]}" "${W[1]}")  $(pad "${HEAD[2]}" "${W[2]}")  ${HEAD[3]}"
    else
        echo "$(pad "${HEAD[0]}" "${W[0]}")  $(pad "${HEAD[2]}" "${W[2]}")  ${HEAD[3]}"
    fi
    for ROW in "${ROWS[@]}"; do
        # read verschluckt leere Felder am Ende, deshalb das Hinweisfeld getrennt abtrennen
        NOTE="${ROW#*$'\t'*$'\t'*$'\t'*$'\t'}"
        IFS=$'\t' read -r -a F <<< "$ROW"
        if [ "$1" = "all" ]; then
            echo "$(pad "${F[0]}" "${W[0]}")  $(pad "${F[1]}" "${W[1]}")  $(pad "${F[2]}" "${W[2]}")  ${F[3]}"
        else
            echo "$(pad "${F[0]}" "${W[0]}")  $(pad "${F[2]}" "${W[2]}")  ${F[3]}"
        fi
        if [ -n "$NOTE" ]; then printf '  %s\n' "$NOTE"; fi
    done
    return 0
}
