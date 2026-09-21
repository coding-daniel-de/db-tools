#!/bin/bash

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 [ziel-umgebung | ddev] [optional: dateiname.sql[.gz[.gpg]] | quell-umgebung | list]"
    echo "Beispiel: $0 dev"
    echo "Beispiel: $0 update dev    (neuesten dev-Dump nach update importieren)"
    echo "Beispiel: $0 update list   (Dump aus einer Liste aller Dumps auswählen)"
    echo "Beispiel: $0 ddev dev      (dev-Dump in das DDEV-Projekt im aktuellen Ordner importieren)"
    echo "Beispiel: $0 ddev list     (dito, Dump aus einer Liste auswählen)"
    exit 1
fi

# Ordner dieses Skripts ermitteln, damit der Aufruf aus jedem Ordner funktioniert
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Gemeinsame Funktionen laden
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

# --- Funktionen ---

# Reservierte Namen für den ersten Parameter (keine Umgebung mit db_<name>.conf)
is_reserved_env() {
    [ "$1" = "ddev" ]
}

# Dump $1 mit dem Passwort aus DUMP_PASS entschlüsseln (Ausgabe auf stdout).
# Das Passwort geht nur über den Dateideskriptor 3 an gpg (nie als Argument, sonst per ps sichtbar).
gpg_decrypt() {
    gpg --batch --quiet --pinentry-mode loopback --no-symkey-cache --passphrase-fd 3 -d "$1" \
        3< <(printf '%s' "$DUMP_PASS")
}

# Neuesten Dump (.sql.gz oder .sql.gz.gpg) zum Präfix $1 in SOURCE_DIR suchen und in FILE ablegen.
# $2 beschreibt die Suche für die Fehlermeldung. Bricht das Skript ab, wenn nichts gefunden wird.
find_latest_dump() {
    FILE=$(ls -t "${SOURCE_DIR}/${1}"-*.sql.gz "${SOURCE_DIR}/${1}"-*.sql.gz.gpg 2>/dev/null | head -n 1)
    if [ -z "$FILE" ]; then
        echo "Fehler: Kein Dump für $2 in '${SOURCE_DIR}' gefunden!"
        exit 1
    fi
    echo "Verwende Dump: ${FILE}"
}

# --- Ablauf ---

# Umgebung festlegen anhand des Parameters
ENV=$1
CONF_FILE="${SCRIPT_DIR}/db_${ENV}.conf"

if is_reserved_env "$ENV"; then
    # Reservierter Name: eine gleichnamige Config würde ignoriert, deshalb vorher abbrechen
    if [ -f "$CONF_FILE" ]; then
        echo "Fehler: '${ENV}' ist ein reservierter Name für den Import in das DDEV-Projekt im aktuellen Ordner."
        echo "Die Datei 'db_${ENV}.conf' würde ignoriert. Bitte umbenennen oder löschen."
        exit 1
    fi
else
    # Prüfen, ob die zugehörige Konfigurationsdatei existiert
    if [ ! -f "$CONF_FILE" ]; then
        echo "Fehler: Konfigurationsdatei 'db_${ENV}.conf' wurde nicht gefunden (gesucht in '${SCRIPT_DIR}')!"
        exit 1
    fi

    # Konfiguration einlesen (lädt die Variablen)
    source "$CONF_FILE"
fi

# Quellverzeichnis der Dumps ermitteln (Default oder dbtools.conf)
resolve_dump_dir
SOURCE_DIR="$DUMP_DIR"

# Dump-Datei bestimmen:
# - 2. Parameter endet auf .sql/.sql.gz/.sql.gz.gpg -> als Dateiname behandeln
# - 2. Parameter ist "list" -> alle Dumps im Dump-Verzeichnis zur Auswahl anzeigen
# - 2. Parameter ist sonst gesetzt -> als Quell-Umgebung behandeln, deren PREFIX
#   für die Dump-Suche übernehmen (Zugangsdaten bleiben die der Ziel-Umgebung!)
# - kein 2. Parameter -> neuesten Dump der Ziel-Umgebung (eigener PREFIX) suchen;
#   reservierte Namen haben keinen eigenen PREFIX, dort wird stattdessen "list" gezeigt
SOURCE_ARG="$2"
if [ -z "$SOURCE_ARG" ] && is_reserved_env "$ENV"; then
    SOURCE_ARG="list"
fi
if [ -n "$SOURCE_ARG" ]; then
    case "$SOURCE_ARG" in
        *.sql|*.sql.gz|*.sql.gz.gpg)
            FILE="$SOURCE_ARG"
            ;;
        list)
            mapfile -t DUMPS < <(ls -t "${SOURCE_DIR}"/*.sql "${SOURCE_DIR}"/*.sql.gz "${SOURCE_DIR}"/*.sql.gz.gpg 2>/dev/null)
            if [ ${#DUMPS[@]} -eq 0 ]; then
                echo "Fehler: Keine Dumps in '${SOURCE_DIR}' gefunden!"
                exit 1
            fi
            echo "Verfügbare Dumps in '${SOURCE_DIR}' (neuester zuerst):"
            for i in "${!DUMPS[@]}"; do
                echo "  $((i + 1))) $(basename "${DUMPS[$i]}")"
            done
            read -p "Nummer wählen: " SELECTION
            if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#DUMPS[@]}" ]; then
                echo "Fehler: Ungültige Auswahl '${SELECTION}'!"
                exit 1
            fi
            FILE="${DUMPS[$((SELECTION - 1))]}"
            ;;
        *)
            SOURCE_CONF="${SCRIPT_DIR}/db_${SOURCE_ARG}.conf"
            if [ ! -f "$SOURCE_CONF" ]; then
                echo "Fehler: '$SOURCE_ARG' ist weder eine Dump-Datei noch wurde 'db_${SOURCE_ARG}.conf' gefunden!"
                exit 1
            fi
            SOURCE_PREFIX=$(grep -E '^PREFIX=' "$SOURCE_CONF" | head -n 1 | cut -d '=' -f2- | tr -d '"')
            if [ -z "$SOURCE_PREFIX" ]; then
                echo "Fehler: In '$SOURCE_CONF' wurde kein PREFIX gefunden!"
                exit 1
            fi
            find_latest_dump "$SOURCE_PREFIX" "Umgebung '$SOURCE_ARG' (Präfix '${SOURCE_PREFIX}')"
            ;;
    esac
else
    find_latest_dump "$PREFIX" "Präfix '${PREFIX}'"
fi

# Prüfen, ob die Dump-Datei existiert
if [ ! -f "$FILE" ]; then
    echo "Fehler: Dump-Datei '$FILE' wurde nicht gefunden!"
    exit 1
fi

# Passwort für verschlüsselte Dumps abfragen und sofort prüfen, noch vor der Sicherheitsabfrage.
# gpg erkennt ein falsches Passwort nur mit einer 16-Bit-Kontrollsumme (etwa 1 von 65000 falschen
# Passwörtern rutscht durch), die Integritätsprüfung am Dateiende greift erst nach dem Import.
# Deshalb werden die ersten Bytes entschlüsselt und auf die gzip-Magic-Bytes (1f 8b) geprüft.
if [[ "$FILE" == *.gpg ]]; then
    require_gpg || exit 1
    IFS= read -r -s -p "Passwort für '$(basename "$FILE")': " DUMP_PASS
    echo
    MAGIC=$(gpg_decrypt "$FILE" 2>/dev/null | head -c 2 | od -An -tx1 | tr -d ' ')
    if [ "$MAGIC" != "1f8b" ]; then
        unset DUMP_PASS
        echo "Fehler: Falsches Passwort oder beschädigter Dump! Die Datenbank wurde nicht angefasst."
        exit 1
    fi
fi

# Sicherheitsabfrage vor dem Import (besonders wichtig bei 'live')
if [ "$ENV" = "ddev" ]; then
    echo "ACHTUNG: Die Datenbank des DDEV-Projekts im aktuellen Ordner ($PWD) wird mit dem Inhalt von '${FILE}' ÜBERSCHRIEBEN!"
else
    echo "ACHTUNG: Die Datenbank [ $DB_NAME ] (Umgebung: $ENV) wird mit dem Inhalt von '${FILE}' ÜBERSCHRIEBEN!"
fi
read -p "Bist du dir absolut sicher? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    unset DUMP_PASS
    echo "Import abgebrochen."
    exit 0
fi

echo "Starte Import für Umgebung: [$ENV] aus Datei: $FILE ..."

# Import-Kommando festlegen: DDEV liest den Dump von stdin, für mysql das Passwort sicher bereitstellen
if [ "$ENV" = "ddev" ]; then
    IMPORT_CMD=(ddev import-db)
else
    export MYSQL_PWD="$DB_PASS"
    IMPORT_CMD=(mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME")
fi

# Schlägt ein Schritt der Pipe fehl (z. B. gpg oder gunzip), soll das nicht als Erfolg durchgehen
set -o pipefail

if [[ "$FILE" == *.gpg ]]; then
    echo "Erkannt: verschlüsselter, gzip-komprimierter Dump"
    gpg_decrypt "$FILE" | gunzip | "${IMPORT_CMD[@]}"
elif [ "$(head -c 2 "$FILE" | od -An -tx1 | tr -d ' ')" = "1f8b" ]; then
    # Anhand der Magic-Bytes erkannt (die ersten beiden Bytes einer gzip-Datei sind immer 1f 8b)
    echo "Erkannt: gzip-komprimierter Dump"
    gunzip -c "$FILE" | "${IMPORT_CMD[@]}"
else
    echo "Erkannt: unkomprimierter SQL-Dump"
    "${IMPORT_CMD[@]}" < "$FILE"
fi

# Status der Pipeline sichern und Passwort-Variablen wieder leeren
STATUS=$?
unset MYSQL_PWD
unset DUMP_PASS

if [ "$STATUS" -eq 0 ]; then
    echo "Erfolgreich importiert aus: ${FILE}"
else
    echo "Fehler: Beim Import ist ein Problem aufgetreten!"
    exit 1
fi
