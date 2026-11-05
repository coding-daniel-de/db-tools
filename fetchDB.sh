#!/bin/bash

# Ordner dieses Skripts ermitteln, damit der Aufruf aus jedem Ordner (und per Symlink) funktioniert
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

# Optionen (--patch, --env) an beliebiger Stelle herausnehmen, danach gelten nur noch die Positionsparameter
parse_transfer_args "$@" || exit 1
set -- "${TRANSFER_ARGS[@]}"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Fehler: Bitte gib den Server an!"
    echo "Nutzung: $0 <server> [dateiname] [--env <umgebung>] [--patch]"
    echo "Beispiel: $0 projekt-live                     (Dump aus der Liste auf dem Server wählen und holen)"
    echo "Beispiel: $0 projekt-live dump.sql.gz         (diese Datei holen)"
    echo "Beispiel: $0 projekt-live --env live          (Liste auf den PREFIX der Umgebung live eingrenzen)"
    echo "Beispiel: $0 projekt-live --patch             (Patch-Datei aus der Liste auf dem Server holen)"
    echo "Der Server ist der Name einer remote_<server>.conf (Vorlage: remote_template.conf)."
    exit 1
fi

SERVER="$1"
FILE_ARG="$2"

resolve_dirs
load_remote_conf "$SERVER" || exit 1

if [ "$PATCH" -eq 1 ]; then
    KIND="patch"; LOCAL_DIR="$PATCH_DIR"; REMOTE_DIR="$REMOTE_PATCH_DIR"; WHAT="Patch-Dateien"
else
    KIND="dump"; LOCAL_DIR="$DUMP_DIR"; REMOTE_DIR="$REMOTE_DUMP_DIR"; WHAT="Dumps"
fi

if [ -n "$ENV_FILTER" ]; then
    if [ "$PATCH" -eq 1 ]; then
        echo "Fehler: --env gilt nur für Dumps, Patch-Dateien haben keinen PREFIX!"
        exit 1
    fi
    if [ -n "$FILE_ARG" ]; then
        echo "Fehler: --env filtert nur die Liste und passt nicht zu einem angegebenen Dateinamen!"
        exit 1
    fi
    read_env_prefix "$ENV_FILTER" || exit 1
fi

# Datei bestimmen: angegebener Name im Server-Ordner oder aus der Liste gewählt
if [ -n "$FILE_ARG" ]; then
    if [[ "$FILE_ARG" == */* ]]; then
        echo "Fehler: Bitte nur den Dateinamen angeben, der Ordner auf dem Server kommt aus remote_${SERVER}.conf!"
        exit 1
    fi
    NAME="$FILE_ARG"
else
    LISTING=$(ssh -n "$SSH_HOST" "find $(printf '%q' "$REMOTE_DIR") -maxdepth 1 -type f -printf '%T@\t%f\n'")
    RC=$?
    if [ "$RC" -ne 0 ]; then
        echo "Fehler: Dateiliste von '${SSH_HOST}:${REMOTE_DIR}' nicht lesbar (Verbindung oder Ordner fehlt, Exit ${RC})!"
        exit 1
    fi
    ITEMS=()
    while IFS= read -r ITEM; do
        transfer_name_ok "$KIND" "$ITEM" || continue
        [ -n "$ENV_FILTER" ] && [[ "$ITEM" != "${ENV_PREFIX}-"* ]] && continue
        ITEMS+=("$ITEM")
    done < <(printf '%s\n' "$LISTING" | sort -rn | cut -f2-)
    if [ ${#ITEMS[@]} -eq 0 ]; then
        echo "Fehler: Keine ${WHAT} in '${SSH_HOST}:${REMOTE_DIR}' gefunden!"
        exit 1
    fi
    pick_item "Verfügbare ${WHAT} in '${SSH_HOST}:${REMOTE_DIR}' (neueste zuerst):" || exit 1
    NAME="$PICKED"
fi

if ! transfer_name_ok "$KIND" "$NAME"; then
    if [ "$KIND" = "patch" ]; then
        echo "Fehler: '${NAME}' ist keine Patch-Datei (.sql oder .sql.gz, nicht verschlüsselt)!"
    else
        echo "Fehler: '${NAME}' ist kein Dump (.sql.gz oder .sql.gz.gpg), für Patch-Dateien --patch angeben!"
    fi
    exit 1
fi
if ! transfer_name_safe "$NAME"; then
    echo "Fehler: Dateiname '${NAME}' enthält Zeichen außerhalb von A-Z a-z 0-9 . _ + -!"
    exit 1
fi

REMOTE_PATH="${REMOTE_DIR%/}/${NAME}"
LOCAL_PATH="${LOCAL_DIR}/${NAME}"
if [ -e "$LOCAL_PATH" ]; then
    echo "Fehler: '${LOCAL_PATH}' existiert lokal schon, nichts überschrieben!"
    exit 1
fi

echo "Datei:  ${SSH_HOST}:${REMOTE_PATH}"
echo "Ziel:   ${LOCAL_PATH}"
ask_yes_no "Holen? (y/N) " || { echo "Abgebrochen."; exit 1; }

mkdir -p "$LOCAL_DIR" || exit 1
# Erst unter .part holen und dann umbenennen, damit nie eine halbe Datei als Dump dasteht
if ! scp -q -- "${SSH_HOST}:${REMOTE_PATH}" "${LOCAL_PATH}.part"; then
    echo "Fehler: Kopieren fehlgeschlagen (Datei auf dem Server vorhanden?)!"
    rm -f -- "${LOCAL_PATH}.part"
    exit 1
fi
mv -- "${LOCAL_PATH}.part" "$LOCAL_PATH" || exit 1
echo "Fertig: ${LOCAL_PATH}"
