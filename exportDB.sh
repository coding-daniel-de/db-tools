#!/bin/bash

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 [umgebung]"
    echo "Beispiel: $0 dev"
    exit 1
fi

# Ordner dieses Skripts ermitteln, damit der Aufruf aus jedem Ordner funktioniert
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Umgebung festlegen anhand des Parameters
ENV=$1
CONF_FILE="${SCRIPT_DIR}/db_${ENV}.conf"

# Prüfen, ob die zugehörige Konfigurationsdatei existiert
if [ ! -f "$CONF_FILE" ]; then
    echo "Fehler: Konfigurationsdatei 'db_${ENV}.conf' wurde nicht gefunden (gesucht in '${SCRIPT_DIR}')!"
    exit 1
fi

# Konfiguration einlesen (lädt die Variablen)
source "$CONF_FILE"

# Dump-Verzeichnis: Default, optional überschrieben durch dbtools.conf
# (relativer Pfad gilt relativ zum Skript-Ordner)
DUMP_DIR="${SCRIPT_DIR}/../sql-dumps"
if [ -f "${SCRIPT_DIR}/dbtools.conf" ]; then
    source "${SCRIPT_DIR}/dbtools.conf"
fi
case "$DUMP_DIR" in
    /*) ;;
    *) DUMP_DIR="${SCRIPT_DIR}/${DUMP_DIR}" ;;
esac
TARGET_DIR="$DUMP_DIR"

# Zielverzeichnis erstellen, falls es nicht existiert
mkdir -p "$TARGET_DIR"

# Dateiname generieren
FILE="${PREFIX}-$(date +%Y-%m-%d-%H)Uhr.sql.gz"

echo "Starte Export für Umgebung: [$ENV]..."

# MySQL-Passwort sicher für den Prozess bereitstellen
export MYSQL_PWD="$DB_PASS"

# Dump ausführen
# tail -n +2 Entfernt Zeile 1 (MariaDB Sandbox-Kommentar), um '\-' Importfehler auf anderen Systemen zu verhindern
mysqldump -h "$DB_HOST" -u "$DB_USER" -v --opt "$DB_NAME" | tail -n +2 | gzip > "${TARGET_DIR}/${FILE}"

# Passwort-Variable wieder leeren
unset MYSQL_PWD

echo "Erfolgreich exportiert nach: ${TARGET_DIR}/${FILE}"
