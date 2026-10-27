#!/bin/bash

# Legt Symlinks für die Tools in einem Ordner im PATH an, damit sie ohne Pfad aufrufbar sind:
# db-export, db-import, db-decrypt (backupAll.sh läuft per Cron mit vollem Pfad und bekommt keinen).
# Nutzung: ./install.sh [ziel-ordner]    (Standard: ~/.local/bin)

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TARGET="${1:-$HOME/.local/bin}"
TARGET=$(realpath -m -- "$TARGET")

declare -A LINKS=(
    [db-export]="exportDB.sh"
    [db-import]="importDB.sh"
    [db-decrypt]="decryptDB.sh"
)
NAMES=(db-export db-import db-decrypt)

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

# Hinweis, falls der Zielordner nicht im PATH liegt
case ":${PATH}:" in
    *":${TARGET}:"*) ;;
    *)
        echo
        echo "Hinweis: '$TARGET' liegt nicht im PATH. Zeile für ~/.bashrc:"
        echo "    export PATH=\"${TARGET}:\$PATH\""
        echo "(~/.profile nimmt ~/bin und ~/.local/bin auf Debian/Ubuntu nur auf, wenn der Ordner beim Login schon existiert.)"
        ;;
esac
