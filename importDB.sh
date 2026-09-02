#!/bin/bash

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 [ziel-umgebung] [optional: dateiname.sql.gz | quell-umgebung]"
    echo "Beispiel: $0 dev"
    echo "Beispiel: $0 update dev   (neuesten dev-Dump nach update importieren)"
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

# Quellverzeichnis der Dumps
SOURCE_DIR="../sql-dumps"

# Dump-Datei bestimmen:
# - 2. Parameter endet auf .sql/.sql.gz -> als Dateiname behandeln
# - 2. Parameter ist sonst gesetzt -> als Quell-Umgebung behandeln, deren PREFIX
#   für die Dump-Suche übernehmen (Zugangsdaten bleiben die der Ziel-Umgebung!)
# - kein 2. Parameter -> neuesten Dump der Ziel-Umgebung (eigener PREFIX) suchen
if [ -n "$2" ]; then
    case "$2" in
        *.sql|*.sql.gz)
            FILE="$2"
            ;;
        *)
            SOURCE_CONF="db_${2}.conf"
            if [ ! -f "$SOURCE_CONF" ]; then
                echo "Fehler: '$2' ist weder eine Dump-Datei noch wurde '$SOURCE_CONF' gefunden!"
                exit 1
            fi
            SOURCE_PREFIX=$(grep -E '^PREFIX=' "$SOURCE_CONF" | head -n 1 | cut -d '=' -f2- | tr -d '"')
            if [ -z "$SOURCE_PREFIX" ]; then
                echo "Fehler: In '$SOURCE_CONF' wurde kein PREFIX gefunden!"
                exit 1
            fi
            FILE=$(ls -t "${SOURCE_DIR}/${SOURCE_PREFIX}"-*.sql.gz 2>/dev/null | head -n 1)
            if [ -z "$FILE" ]; then
                echo "Fehler: Kein Dump für Umgebung '$2' (Präfix '${SOURCE_PREFIX}') in '${SOURCE_DIR}' gefunden!"
                exit 1
            fi
            ;;
    esac
else
    FILE=$(ls -t "${SOURCE_DIR}/${PREFIX}"-*.sql.gz 2>/dev/null | head -n 1)
    if [ -z "$FILE" ]; then
        echo "Fehler: Kein Dump für Präfix '${PREFIX}' in '${SOURCE_DIR}' gefunden!"
        exit 1
    fi
fi

# Prüfen, ob die Dump-Datei existiert
if [ ! -f "$FILE" ]; then
    echo "Fehler: Dump-Datei '$FILE' wurde nicht gefunden!"
    exit 1
fi

# Sicherheitsabfrage vor dem Import (besonders wichtig bei 'live')
echo "ACHTUNG: Die Datenbank [ $DB_NAME ] (Umgebung: $ENV) wird mit dem Inhalt von '${FILE}' ÜBERSCHRIEBEN!"
read -p "Bist du dir absolut sicher? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Import abgebrochen."
    exit 0
fi

echo "Starte Import für Umgebung: [$ENV] aus Datei: $FILE ..."

# MySQL-Passwort sicher für den Prozess bereitstellen
export MYSQL_PWD="$DB_PASS"

# Anhand der Magic-Bytes prüfen, ob es sich um eine gzip-komprimierte Datei handelt
# (die ersten beiden Bytes einer gzip-Datei sind immer 1f 8b)
if [ "$(head -c 2 "$FILE" | od -An -tx1 | tr -d ' ')" = "1f8b" ]; then
    echo "Erkannt: gzip-komprimierter Dump"
    gunzip -c "$FILE" | mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME"
else
    echo "Erkannt: unkomprimierter SQL-Dump"
    mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" < "$FILE"
fi

# Status des letzten Befehls prüfen
if [ $? -eq 0 ]; then
    echo "Erfolgreich importiert aus: ${FILE}"
else
    echo "Fehler: Beim Import ist ein Problem aufgetreten!"
fi

# Passwort-Variable wieder leeren
unset MYSQL_PWD
