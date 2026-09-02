#!/bin/bash

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 [umgebung]"
    echo "Beispiel: $0 dev"
    exit 1
fi

# Umgebung festlegen anhand des Parameters
ENV=$1
CONF_FILE="db_${ENV}.conf"

# Prüfen, ob die zugehörige Konfigurationsdatei existiert
if [ ! -f "$CONF_FILE" ]; then
    echo "Fehler: Konfigurationsdatei '$CONF_FILE' wurde nicht gefunden!"
    exit 1
fi

# Konfiguration einlesen (lädt die Variablen)
source "./$CONF_FILE"

# Dump-Verzeichnis: Default, optional überschrieben durch dbtools.conf
TARGET_DIR="../sql-dumps"
if [ -f "./dbtools.conf" ]; then
    source "./dbtools.conf"
    TARGET_DIR="$DUMP_DIR"
fi

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
