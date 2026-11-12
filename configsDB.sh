#!/bin/bash
# Zeigt alle Configs auf einmal: Datenbank-Umgebungen (db_<name>.conf, für db-export und db-import)
# und Server (remote_<name>.conf, für db-send und db-fetch) mit Spalte "Art". Keine Passwörter.
# Gesucht wird in ~/db-tools-conf/, conf/ und im Skript-Ordner (erste Fundstelle gewinnt, überdeckte
# Dateien werden als doppelt markiert). Pro Befehl gibt es dasselbe als Option: db-export --configs usw.
# Nutzung: configsDB.sh
#
# Intern für die Tab-Vervollständigung: configsDB.sh --names <db|remote> gibt nur die Namen aus.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

if [ "$1" = "--names" ]; then
    case "$2" in
        db|remote) conf_names "$2"; exit 0 ;;
        *) exit 1 ;;
    esac
fi

if [ $# -gt 0 ]; then
    echo "Fehler: Unbekannter Parameter '${1}'!"
    echo "Nutzung: $0"
    exit 1
fi

print_configs all
