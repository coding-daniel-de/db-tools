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

# Gemeinsame Funktionen laden
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

# --- Funktionen ---

# Passwort zweimal abfragen (ohne Anzeige) und in ENC_PASS ablegen.
# Rückgabe 1 bei leerem Passwort oder wenn beide Eingaben nicht übereinstimmen.
ask_new_password() {
    local pass2
    IFS= read -r -s -p "Passwort: " ENC_PASS
    echo
    IFS= read -r -s -p "Passwort wiederholen: " pass2
    echo
    if [ -z "$ENC_PASS" ]; then
        echo "Fehler: Das Passwort darf nicht leer sein!"
        return 1
    fi
    if [ "$ENC_PASS" != "$pass2" ]; then
        echo "Fehler: Die Passwörter stimmen nicht überein!"
        return 1
    fi
}

# Dump als gzip-Strom auf stdout ausgeben
# tail -n +2 Entfernt Zeile 1 (MariaDB Sandbox-Kommentar), um '\-' Importfehler auf anderen Systemen zu verhindern
dump_sql() {
    mysqldump -h "$DB_HOST" -u "$DB_USER" -v --opt "$DB_NAME" | tail -n +2 | gzip
}

# Bei Abbruch (Ctrl+C, SIGTERM) Passwörter leeren und die unvollständige Datei löschen
abort_export() {
    unset MYSQL_PWD ENC_PASS
    rm -f "${TARGET_DIR}/${FILE}"
    # Ausgabe nach stderr, denn stdout ist beim unverschlüsselten Export in die Dump-Datei umgeleitet
    echo >&2
    echo "Export abgebrochen, die unvollständige Datei wurde gelöscht!" >&2
    exit 130
}

# --- Ablauf ---

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

# Dump-Verzeichnis ermitteln (Default oder dbtools.conf)
resolve_dump_dir
TARGET_DIR="$DUMP_DIR"

# Verschlüsselung optional abfragen
ENCRYPT=0
read -r -p "Dump verschlüsseln? (y/N): " ENCRYPT_ANSWER
if [[ "$ENCRYPT_ANSWER" =~ ^[yY]$ ]]; then
    ENCRYPT=1
    require_gpg || exit 1
    if ! ask_new_password; then
        unset ENC_PASS
        exit 1
    fi
fi

# Zielverzeichnis erstellen, falls es nicht existiert
mkdir -p "$TARGET_DIR"

# Dateiname generieren
FILE="${PREFIX}-$(date +%Y-%m-%d-%H)Uhr.sql.gz"
if [ "$ENCRYPT" -eq 1 ]; then
    FILE="${FILE}.gpg"
fi

echo "Starte Export für Umgebung: [$ENV]..."

# MySQL-Passwort sicher für den Prozess bereitstellen
export MYSQL_PWD="$DB_PASS"

# Schlägt ein Schritt der Pipe fehl, soll das nicht unbemerkt bleiben
set -o pipefail

# Bei Abbruch aufräumen. Greift sofort bei Ctrl+C (das Signal trifft die ganze Pipeline).
# Ein gezieltes "kill <pid>" nur auf dieses Skript wirkt erst nach Ende des Dumps, danach wird
# die Datei gelöscht.
trap abort_export INT TERM

# Dump ausführen
# Das gpg-Passwort geht nur über den Dateideskriptor 3 (nie als Argument, sonst per ps sichtbar)
if [ "$ENCRYPT" -eq 1 ]; then
    dump_sql \
        | gpg --batch --yes --quiet --pinentry-mode loopback --no-symkey-cache \
              --passphrase-fd 3 --symmetric --cipher-algo AES256 --compress-algo none \
              3< <(printf '%s' "$ENC_PASS") > "${TARGET_DIR}/${FILE}"
else
    dump_sql > "${TARGET_DIR}/${FILE}"
fi
STATUS=$?
trap - INT TERM

# Passwort-Variablen wieder leeren (auch im Fehlerfall)
unset MYSQL_PWD
unset ENC_PASS

if [ "$STATUS" -ne 0 ]; then
    rm -f "${TARGET_DIR}/${FILE}"
    echo "Fehler: Der Export ist fehlgeschlagen, die unvollständige Datei wurde gelöscht!"
    exit 1
fi

echo "Erfolgreich exportiert nach: ${TARGET_DIR}/${FILE}"
