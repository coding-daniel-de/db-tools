#!/bin/bash

# Legt Symlinks für die Tools in einem Ordner im PATH an, damit sie ohne Pfad aufrufbar sind:
# db-export, db-import, db-decrypt, db-send, db-fetch, db-configs (backupAll.sh läuft per Cron mit vollem Pfad und bekommt keinen).
# Nutzung: ./install.sh [--path] [ziel-ordner]    (Standard: ~/bin)
#   --path   Eintragungen in ~/.bashrc (PATH, Tab-Vervollständigung) und bei Bedarf in die Login-Datei ohne Rückfrage vornehmen
#            (ohne --path kommt im Terminal eine Rückfrage, sonst nur ein Hinweis).

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "${REPO_DIR}/lib/shell-setup.sh" || exit 1

SS_YES=0
if [ "$1" = "--path" ]; then
    SS_YES=1
    shift
fi
TARGET=$(ss_abs_path "${1:-$HOME/bin}")

declare -A LINKS=(
    [db-export]="exportDB.sh"
    [db-import]="importDB.sh"
    [db-decrypt]="decryptDB.sh"
    [db-send]="sendDB.sh"
    [db-fetch]="fetchDB.sh"
    [db-configs]="configsDB.sh"
)
NAMES=(db-export db-import db-decrypt db-send db-fetch db-configs)

# Erst alles prüfen, damit bei einem Konflikt nichts halb installiert wird
for name in "${NAMES[@]}"; do
    link="${TARGET}/${name}"
    source_file="${REPO_DIR}/${LINKS[$name]}"
    if [ -e "$link" ] || [ -L "$link" ]; then
        if [ ! -L "$link" ] || [ "$(readlink -f "$link")" != "$source_file" ]; then
            echo "Fehler: '$link' existiert bereits und ist kein Symlink auf '$source_file'. Es wurde nichts geändert!"
            exit 1
        fi
    fi
done

mkdir -p "$TARGET" || exit 1

for name in "${NAMES[@]}"; do
    link="${TARGET}/${name}"
    source_file="${REPO_DIR}/${LINKS[$name]}"
    if [ -L "$link" ]; then
        echo "Schon vorhanden: $link"
    else
        ln -s "$source_file" "$link" || exit 1
        echo "Angelegt: $link -> $source_file"
    fi
done

# Zielordner im PATH? Sonst Eintrag in die ~/.bashrc (per --path oder Rückfrage) oder Hinweis
ss_ensure_path "$TARGET"

# Tab-Vervollständigung: Source-Zeile in die ~/.bashrc (per --path oder Rückfrage), einmal pro Datei
COMPLETION_FILE="${REPO_DIR}/dbtools-completion.sh"
echo
if grep -qF "$COMPLETION_FILE" "$SS_BASHRC" 2>/dev/null; then
    ss_ensure_source "$COMPLETION_FILE" "db-tools: Tab-Vervollständigung"
elif ss_confirm "Tab-Vervollständigung für die db-Befehle in $SS_BASHRC eintragen?"; then
    ss_ensure_source "$COMPLETION_FILE" "db-tools: Tab-Vervollständigung"
else
    echo "Hinweis: Tab-Vervollständigung nicht eingetragen. Zeile für ~/.bashrc (oder: ./install.sh --path):"
    echo "    [ -f \"$COMPLETION_FILE\" ] && source \"$COMPLETION_FILE\""
fi

ss_ensure_login_chain
