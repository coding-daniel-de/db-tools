#!/bin/bash
# Sichert alle Umgebungen aus BACKUP_ENVS (dbtools.conf) unverschlüsselt nach BACKUP_DIR,
# gedacht für Cron. Bei Erfolg komplett still, bei Fehlern Meldung auf stderr und Exit 1
# (Cron schickt dann eine Mail an MAILTO). Ein fehlgeschlagener Export stoppt die anderen nicht.
# Nutzung: backupAll.sh

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

resolve_dirs

if [ -z "$BACKUP_ENVS" ]; then
    echo "Fehler: BACKUP_ENVS ist nicht gesetzt (Liste der Umgebungen in dbtools.conf)!" >&2
    exit 1
fi

FAILED=()
TOTAL=0
DETAILS=""
for ENV in $BACKUP_ENVS; do
    TOTAL=$((TOTAL + 1))
    # Ausgabe des Exports einsammeln, sie wird nur im Fehlerfall gezeigt
    if ! OUTPUT=$("${SCRIPT_DIR}/exportDB.sh" "$ENV" --no-encrypt --out "$BACKUP_DIR" </dev/null 2>&1); then
        FAILED+=("$ENV")
        DETAILS+=$'\n'"--- ${ENV}:"$'\n'"${OUTPUT}"$'\n'
    fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Backup: ${#FAILED[@]} von ${TOTAL} fehlgeschlagen: ${FAILED[*]}" >&2
    printf '%s' "$DETAILS" >&2
    exit 1
fi
