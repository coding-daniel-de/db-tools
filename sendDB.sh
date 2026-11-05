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
    echo "Beispiel: $0 projekt-live                     (Dump aus einer Liste wählen und zum Server kopieren)"
    echo "Beispiel: $0 projekt-live dump.sql.gz         (diese Datei kopieren)"
    echo "Beispiel: $0 projekt-live --env live          (Liste auf den PREFIX der Umgebung live eingrenzen)"
    echo "Beispiel: $0 projekt-live --patch             (Patch-Datei aus einer Liste wählen)"
    echo "Beispiel: $0 projekt-live fix.sql --patch     (diesen Patch kopieren)"
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

# Datei bestimmen: angegeben (Pfad oder Name im Quellordner) oder aus der Liste gewählt
if [ -n "$FILE_ARG" ]; then
    if [ -f "$FILE_ARG" ]; then
        FILE="$FILE_ARG"
    elif [ -f "${LOCAL_DIR}/${FILE_ARG}" ]; then
        FILE="${LOCAL_DIR}/${FILE_ARG}"
    else
        echo "Fehler: Datei '${FILE_ARG}' nicht gefunden (auch nicht in '${LOCAL_DIR}')!"
        exit 1
    fi
else
    ITEMS=()
    if [ -d "$LOCAL_DIR" ]; then
        while IFS= read -r NAME; do
            transfer_name_ok "$KIND" "$NAME" || continue
            [ -n "$ENV_FILTER" ] && [[ "$NAME" != "${ENV_PREFIX}-"* ]] && continue
            ITEMS+=("$NAME")
        done < <(find "$LOCAL_DIR" -maxdepth 1 -type f -printf '%T@\t%f\n' | sort -rn | cut -f2-)
    fi
    if [ ${#ITEMS[@]} -eq 0 ]; then
        echo "Fehler: Keine ${WHAT} in '${LOCAL_DIR}' gefunden!"
        exit 1
    fi
    pick_item "Verfügbare ${WHAT} in '${LOCAL_DIR}' (neueste zuerst):" || exit 1
    FILE="${LOCAL_DIR}/${PICKED}"
fi

NAME=$(basename "$FILE")
if ! transfer_name_ok "$KIND" "$NAME"; then
    if [ "$KIND" = "patch" ]; then
        echo "Fehler: '${NAME}' ist keine Patch-Datei (.sql oder .sql.gz, nicht verschlüsselt)!"
    else
        echo "Fehler: '${NAME}' ist kein Dump (.sql.gz oder .sql.gz.gpg), für Patch-Dateien --patch angeben!"
    fi
    exit 1
fi
if ! transfer_name_safe "$NAME"; then
    echo "Fehler: Dateiname '${NAME}' enthält Zeichen außerhalb von A-Z a-z 0-9 . _ + -, bitte umbenennen!"
    exit 1
fi

REMOTE_PATH="${REMOTE_DIR%/}/${NAME}"
SIZE=$(du -h -- "$FILE" | cut -f1)
echo "Datei:  ${FILE} (${SIZE})"
echo "Ziel:   ${SSH_HOST}:${REMOTE_PATH}"
ask_yes_no "Kopieren? (y/N) " || { echo "Abgebrochen."; exit 1; }

# Zielordner anlegen und prüfen, dass die Datei dort noch nicht existiert (Exit 10 = existiert)
ssh -n "$SSH_HOST" "mkdir -p $(printf '%q' "$REMOTE_DIR") && if test -e $(printf '%q' "$REMOTE_PATH"); then exit 10; fi"
RC=$?
if [ "$RC" -eq 10 ]; then
    echo "Fehler: '${REMOTE_PATH}' existiert auf dem Server schon, nichts überschrieben!"
    exit 1
elif [ "$RC" -ne 0 ]; then
    echo "Fehler: Verbindung zu '${SSH_HOST}' oder Zielordner nicht möglich (Exit ${RC})!"
    exit 1
fi

# Erst unter .part kopieren und dann umbenennen, damit nie eine halbe Datei als Dump dasteht
if ! scp -q -- "$FILE" "${SSH_HOST}:${REMOTE_PATH}.part"; then
    echo "Fehler: Kopieren fehlgeschlagen!"
    ssh -n "$SSH_HOST" "rm -f -- $(printf '%q' "${REMOTE_PATH}.part")" 2>/dev/null
    exit 1
fi
if ! ssh -n "$SSH_HOST" "mv -- $(printf '%q' "${REMOTE_PATH}.part") $(printf '%q' "$REMOTE_PATH")"; then
    echo "Fehler: Umbenennen von '${REMOTE_PATH}.part' auf dem Server fehlgeschlagen!"
    exit 1
fi
echo "Fertig: ${SSH_HOST}:${REMOTE_PATH}"
