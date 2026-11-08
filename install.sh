#!/bin/bash

# Legt Symlinks für die Tools in einem Ordner im PATH an, damit sie ohne Pfad aufrufbar sind:
# db-export, db-import, db-decrypt, db-send, db-fetch (backupAll.sh läuft per Cron mit vollem Pfad und bekommt keinen).
# Nutzung: ./install.sh [--path] [ziel-ordner]    (Standard: ~/bin)
#   --path   Liegt der Zielordner nicht im PATH, wird er ohne Rückfrage in die ~/.bashrc eingetragen
#            (ohne --path kommt im Terminal eine Rückfrage, sonst nur ein Hinweis).

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ADD_PATH=0
if [ "$1" = "--path" ]; then
    ADD_PATH=1
    shift
fi
TARGET="${1:-$HOME/bin}"
# Pfad absolut machen und Slashes bereinigen (ohne realpath, das fehlt auf älteren Debian-Servern)
case "$TARGET" in
    /*) ;;
    *)  TARGET="$PWD/$TARGET" ;;
esac
while [[ "$TARGET" == */ && "$TARGET" != "/" ]]; do TARGET="${TARGET%/}"; done
while [[ "$TARGET" == *//* ]]; do TARGET="${TARGET//\/\//\/}"; done

declare -A LINKS=(
    [db-export]="exportDB.sh"
    [db-import]="importDB.sh"
    [db-decrypt]="decryptDB.sh"
    [db-send]="sendDB.sh"
    [db-fetch]="fetchDB.sh"
)
NAMES=(db-export db-import db-decrypt db-send db-fetch)

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
case ":${PATH}:" in
    *":${TARGET}:"*) ;;
    *)
        BASHRC="$HOME/.bashrc"
        MARKER="# bin-path: ${TARGET}"
        # Im Home-Ordner mit $HOME schreiben, damit der Eintrag auch bei verschobenem Home stimmt
        case "$TARGET" in
            "$HOME"/*) TARGET_EXPR="\$HOME/${TARGET#"$HOME"/}" ;;
            *)         TARGET_EXPR="$TARGET" ;;
        esac
        EXPORT_LINE="export PATH=\"${TARGET_EXPR}:\$PATH\""
        echo
        if [ -f "$BASHRC" ] && grep -qxF "$MARKER" "$BASHRC"; then
            echo "'$TARGET' ist schon in $BASHRC eingetragen, gilt ab der nächsten Shell (oder: source ~/.bashrc)."
        else
            DO_ADD=$ADD_PATH
            if [ "$DO_ADD" -eq 0 ] && [ -t 0 ]; then
                read -r -n 1 -p "'$TARGET' liegt nicht im PATH. In $BASHRC eintragen? (y/N) " answer
                [ -n "$answer" ] && echo
                [[ "$answer" =~ ^[yY]$ ]] && DO_ADD=1
            fi
            if [ "$DO_ADD" -eq 1 ]; then
                printf '\n%s\n%s\n' "$MARKER" "$EXPORT_LINE" >> "$BASHRC" || exit 1
                echo "Eingetragen in $BASHRC, gilt ab der nächsten Shell (oder: source ~/.bashrc)."
            else
                echo "Hinweis: '$TARGET' liegt nicht im PATH. Zeile für ~/.bashrc (oder: ./install.sh --path):"
                echo "    $EXPORT_LINE"
                echo "(~/.profile nimmt ~/bin und ~/.local/bin auf Debian/Ubuntu nur auf, wenn der Ordner beim Login schon existiert.)"
            fi
        fi
        ;;
esac
