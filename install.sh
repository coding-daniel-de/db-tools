#!/bin/bash

# Legt Symlinks für die Tools in einem Ordner im PATH an, damit sie ohne Pfad aufrufbar sind:
# db-export, db-import, db-decrypt, db-send, db-fetch, db-configs, db-init-config (backupAll.sh läuft per Cron mit vollem Pfad und bekommt keinen).
# Nutzung: ./install.sh [--path] [ziel-ordner]    (Standard: ~/bin)
#          sudo ./install.sh --global
#   --path     Eintragungen in ~/.bashrc (PATH, Tab-Vervollständigung) und bei Bedarf in die Login-Datei ohne Rückfrage vornehmen
#              (ohne --path kommt im Terminal eine Rückfrage, sonst nur ein Hinweis).
#   --global   Symlinks nach /usr/local/bin für alle Accounts (braucht root, sudo ruft das Skript nicht selbst auf).
#              Kein PATH-Eintrag und keine Login-Kette nötig. Nicht mit --path oder einem Zielordner kombinierbar.
#              Die Tab-Vervollständigung kommt als Symlink nach /etc/bash_completion.d/db-tools, wenn der Ordner existiert.
#              Sonst fragt das Skript im Terminal, ob es /etc/profile.d/db-tools.sh anlegen soll (ohne Terminal nur ein Hinweis).
#              Bricht ab, wenn die Installation für andere Accounts nicht erreichbar ist (Empfehlung: Klon nach /opt/db-tools).

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "${REPO_DIR}/lib/shell-setup.sh" || exit 1

SS_YES=0
GLOBAL=0
USE_PATH=0
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --path) USE_PATH=1 ;;
        --global) GLOBAL=1 ;;
        --*)
            echo "Fehler: Unbekannte Option '${1}'!"
            echo "Nutzung: $0 [--path] [ziel-ordner]    oder    sudo $0 --global"
            exit 1
            ;;
        *) POSITIONAL+=("$1") ;;
    esac
    shift
done
[ "$USE_PATH" -eq 1 ] && SS_YES=1

if [ "${#POSITIONAL[@]}" -gt 1 ]; then
    echo "Fehler: Es kann nur ein Zielordner angegeben werden!"
    exit 1
fi

if [ "$GLOBAL" -eq 1 ]; then
    if [ "$USE_PATH" -eq 1 ] || [ "${#POSITIONAL[@]}" -gt 0 ]; then
        echo "Fehler: --global installiert nach /usr/local/bin und lässt sich nicht mit --path oder einem Zielordner kombinieren!"
        exit 1
    fi
    # DBTOOLS_GLOBAL_BIN nur für die Tests (Wegwerf-Ordner statt /usr/local/bin)
    TARGET="${DBTOOLS_GLOBAL_BIN:-/usr/local/bin}"
else
    TARGET=$(ss_abs_path "${POSITIONAL[0]:-$HOME/bin}")
fi

declare -A LINKS=(
    [db-export]="exportDB.sh"
    [db-import]="importDB.sh"
    [db-decrypt]="decryptDB.sh"
    [db-send]="sendDB.sh"
    [db-fetch]="fetchDB.sh"
    [db-configs]="configsDB.sh"
    [db-init-config]="initConfigDB.sh"
)
NAMES=(db-export db-import db-decrypt db-send db-fetch db-configs db-init-config)

# Global: root nötig und die Installation muss für andere Accounts les- und ausführbar sein
# (root kann alles lesen und würde das sonst nicht merken). Es wird nichts geändert, nur geprüft.
if [ "$GLOBAL" -eq 1 ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "Fehler: --global braucht root. Bitte mit sudo aufrufen: sudo $0 --global"
        exit 1
    fi
    unreachable=()
    # Jeder Ordner auf dem Weg zum Repo braucht für "andere" das x-Recht
    dir="$REPO_DIR"
    while [ "$dir" != "/" ]; do
        mode=$(stat -c %a "$dir") && (( 8#$mode & 1 )) || unreachable+=("$dir (Ordner, fehlt: x für andere)")
        dir=$(dirname "$dir")
    done
    mode=$(stat -c %a "${REPO_DIR}/conf") && (( 8#$mode & 1 )) || unreachable+=("${REPO_DIR}/conf (Ordner, fehlt: x für andere)")
    # Skripte (Ziel der Symlinks): lesen und ausführen; Hilfsdateien und Vorlagen: lesen
    for name in "${NAMES[@]}"; do
        f="${REPO_DIR}/${LINKS[$name]}"
        mode=$(stat -c %a "$f" 2>/dev/null) && (( (8#$mode & 5) == 5 )) || unreachable+=("$f (fehlt: r und x für andere)")
    done
    for f in dbtools-lib.sh dbtools-completion.sh conf/db_template.conf conf/remote_template.conf conf/dbtools.conf.example; do
        mode=$(stat -c %a "${REPO_DIR}/${f}" 2>/dev/null) && (( (8#$mode & 4) == 4 )) || unreachable+=("${REPO_DIR}/${f} (fehlt: r für andere)")
    done
    if [ "${#unreachable[@]}" -gt 0 ]; then
        echo "Fehler: Die Installation ist für andere Accounts nicht erreichbar:"
        printf '  %s\n' "${unreachable[@]}"
        echo "Es wurde nichts geändert. Empfehlung: das Repo nach /opt/db-tools klonen und von dort installieren."
        exit 1
    fi
fi

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

# Global: Tab-Vervollständigung planen (COMP_MODE: link = Symlink in bash_completion.d, profile = Drop-in in
# profile.d, none = nur Hinweis). Die Rückfrage kommt vor dem ersten Anlegen, Konflikte brechen vor dem Anlegen ab.
# DBTOOLS_GLOBAL_COMPLETION_DIR und DBTOOLS_GLOBAL_PROFILE_DIR nur für die Tests.
COMP_MODE=none
COMPLETION_FILE="${REPO_DIR}/dbtools-completion.sh"
if [ "$GLOBAL" -eq 1 ]; then
    COMP_DIR="${DBTOOLS_GLOBAL_COMPLETION_DIR:-/etc/bash_completion.d}"
    PROFILE_DIR="${DBTOOLS_GLOBAL_PROFILE_DIR:-/etc/profile.d}"
    if [ -d "$COMP_DIR" ]; then
        COMP_MODE=link
        COMP_DEST="${COMP_DIR}/db-tools"
        if [ -e "$COMP_DEST" ] || [ -L "$COMP_DEST" ]; then
            if [ ! -L "$COMP_DEST" ] || [ "$(readlink -f "$COMP_DEST")" != "$COMPLETION_FILE" ]; then
                echo "Fehler: '$COMP_DEST' existiert bereits und ist kein Symlink auf '$COMPLETION_FILE'. Es wurde nichts geändert!"
                exit 1
            fi
        fi
    elif [ -d "$PROFILE_DIR" ] && ss_confirm "$COMP_DIR fehlt. Tab-Vervollständigung stattdessen als $PROFILE_DIR/db-tools.sh anlegen?"; then
        COMP_MODE=profile
        COMP_DEST="${PROFILE_DIR}/db-tools.sh"
        # Kleine echte Datei mit Guard, weil /etc/profile *.sh auch für sh/dash liest (nur POSIX-Syntax, nur interaktives Bash)
        COMP_CONTENT=$(printf '%s\n' \
            '# db-tools: Tab-Vervollständigung (angelegt von install.sh --global)' \
            'if [ -n "$BASH_VERSION" ]; then' \
            '    case $- in' \
            "        *i*) [ -f \"${COMPLETION_FILE}\" ] && . \"${COMPLETION_FILE}\" ;;" \
            '    esac' \
            'fi')
        if [ -e "$COMP_DEST" ] || [ -L "$COMP_DEST" ]; then
            if [ -L "$COMP_DEST" ] || [ "$(cat "$COMP_DEST" 2>/dev/null)" != "$COMP_CONTENT" ]; then
                echo "Fehler: '$COMP_DEST' existiert bereits und stammt nicht von diesem Installer. Es wurde nichts geändert!"
                exit 1
            fi
        fi
    fi
fi

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

if [ "$GLOBAL" -eq 1 ]; then
    echo
    case "$COMP_MODE" in
        link)
            if [ -L "$COMP_DEST" ]; then
                echo "Schon vorhanden: $COMP_DEST"
            else
                ln -s "$COMPLETION_FILE" "$COMP_DEST" || exit 1
                echo "Angelegt: $COMP_DEST -> $COMPLETION_FILE (Tab-Vervollständigung, gilt ab der nächsten Shell)"
            fi
            ;;
        profile)
            if [ -e "$COMP_DEST" ]; then
                echo "Schon vorhanden: $COMP_DEST"
            else
                printf '%s\n' "$COMP_CONTENT" > "$COMP_DEST" || exit 1
                chmod 644 "$COMP_DEST"
                echo "Angelegt: $COMP_DEST (Tab-Vervollständigung, gilt ab dem nächsten Login)"
            fi
            ;;
        *)
            echo "Tab-Vervollständigung nicht eingetragen (optional, pro Account in die ~/.bashrc):"
            echo "    [ -f \"${COMPLETION_FILE}\" ] && source \"${COMPLETION_FILE}\""
            ;;
    esac
    echo "Global installiert. Pro Account (als dieser User): db-init-config legt ~/db-tools-conf/ mit den Vorlagen an."
    exit 0
fi

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
