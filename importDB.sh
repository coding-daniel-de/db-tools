#!/bin/bash

# Optionen (--...) an beliebiger Stelle herausnehmen, danach gelten nur noch die Positionsparameter
GUNZIP=0
PATCH=0
POSITIONAL=()
for ARG in "$@"; do
    case "$ARG" in
        --gunzip)
            GUNZIP=1
            ;;
        --patch)
            PATCH=1
            ;;
        --*)
            echo "Fehler: Unbekannte Option '${ARG}'!"
            exit 1
            ;;
        *)
            POSITIONAL+=("$ARG")
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 [ziel-umgebung | ddev | decrypt] [optional: dateiname.sql[.gz[.gpg]] | quell-umgebung | list] [--gunzip] [--patch]"
    echo "Beispiel: $0 dev"
    echo "Beispiel: $0 update dev    (neuesten dev-Dump nach update importieren)"
    echo "Beispiel: $0 update list   (Dump aus einer Liste aller Dumps auswählen)"
    echo "Beispiel: $0 ddev dev      (dev-Dump in das DDEV-Projekt im aktuellen Ordner importieren)"
    echo "Beispiel: $0 ddev list     (dito, Dump aus einer Liste auswählen)"
    echo "Beispiel: $0 decrypt list  (Dump nur entschlüsseln, Ergebnis im aktuellen Ordner)"
    echo "Beispiel: $0 decrypt dev --gunzip   (entschlüsseln und entpacken, --gunzip nur bei decrypt)"
    echo "Beispiel: $0 live aenderungen.sql --patch   (nur die Befehle der Datei ausführen, DB wird nicht geleert)"
    exit 1
fi

# Ordner dieses Skripts ermitteln, damit der Aufruf aus jedem Ordner funktioniert
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Gemeinsame Funktionen laden
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

# --- Funktionen ---

# Zweck eines reservierten Namens für den ersten Parameter (keine Umgebung mit db_<name>.conf).
# Gibt für normale Umgebungen nichts aus.
reserved_purpose() {
    case "$1" in
        ddev) echo "den Import in das DDEV-Projekt im aktuellen Ordner" ;;
        decrypt) echo "das Entschlüsseln von Dumps" ;;
    esac
}

is_reserved_env() {
    [ -n "$(reserved_purpose "$1")" ]
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

# Inhalt des Dumps FILE entschlüsselt und entpackt auf stdout ausgeben.
# Die Art des Dumps muss vorher mit detect_dump_kind in DUMP_KIND abgelegt worden sein.
dump_content() {
    case "$DUMP_KIND" in
        gpg) gpg_decrypt "$FILE" | gunzip ;;
        gzip) gunzip -c "$FILE" ;;
        *) cat "$FILE" ;;
    esac
}

# Art des Dumps FILE ermitteln, in DUMP_KIND ablegen (gpg, gzip oder plain) und melden.
# gzip wird an den Magic-Bytes erkannt (die ersten beiden Bytes einer gzip-Datei sind immer 1f 8b).
detect_dump_kind() {
    if [[ "$FILE" == *.gpg ]]; then
        DUMP_KIND=gpg
        echo "Erkannt: verschlüsselter, gzip-komprimierter Dump"
    elif [ "$(head -c 2 "$FILE" | od -An -tx1 | tr -d ' ')" = "1f8b" ]; then
        DUMP_KIND=gzip
        echo "Erkannt: gzip-komprimierter Dump"
    else
        DUMP_KIND=plain
        echo "Erkannt: unkomprimierter SQL-Dump"
    fi
}

# Tabellen, Views und Sequenzen der Ziel-DB abfragen und in DB_OBJECTS ablegen
# (je Zeile "TYP<Tab>NAME"). Bricht bei einem Verbindungsfehler das Skript ab.
load_db_objects() {
    local OUTPUT
    if ! OUTPUT=$(mysql -h "$DB_HOST" -u "$DB_USER" -N -B -r \
        -e "SELECT TABLE_TYPE, TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()" \
        "$DB_NAME"); then
        unset MYSQL_PWD DUMP_PASS
        echo "Fehler: Die Tabellen der Datenbank [ $DB_NAME ] konnten nicht ermittelt werden! Die Datenbank wurde nicht angefasst."
        exit 1
    fi
    DB_OBJECTS=()
    if [ -n "$OUTPUT" ]; then
        mapfile -t DB_OBJECTS <<< "$OUTPUT"
    fi
}

# Namen $1 für SQL in Backticks setzen. Backticks im Namen werden verdoppelt,
# damit der Name sicher in `...` steht.
quote_ident() {
    echo "\`${1//\`/\`\`}\`"
}

# DROP-Befehle für alle Objekte in DB_OBJECTS ausgeben, Views zuerst
drop_statements() {
    local TYPE NAME LINE
    echo "SET FOREIGN_KEY_CHECKS=0;"
    for LINE in "${DB_OBJECTS[@]}"; do
        IFS=$'\t' read -r TYPE NAME <<< "$LINE"
        [ "$TYPE" = "VIEW" ] && echo "DROP VIEW IF EXISTS $(quote_ident "$NAME");"
    done
    for LINE in "${DB_OBJECTS[@]}"; do
        IFS=$'\t' read -r TYPE NAME <<< "$LINE"
        case "$TYPE" in
            VIEW) ;;
            SEQUENCE) echo "DROP SEQUENCE IF EXISTS $(quote_ident "$NAME");" ;;
            *) echo "DROP TABLE IF EXISTS $(quote_ident "$NAME");" ;;
        esac
    done
}

# --- Ablauf ---

# Umgebung festlegen anhand des Parameters
ENV=$1
CONF_FILE="${SCRIPT_DIR}/db_${ENV}.conf"

if is_reserved_env "$ENV"; then
    # Reservierter Name: eine gleichnamige Config würde ignoriert, deshalb vorher abbrechen
    if [ -f "$CONF_FILE" ]; then
        echo "Fehler: '${ENV}' ist ein reservierter Name für $(reserved_purpose "$ENV")."
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

if [ "$GUNZIP" -eq 1 ] && [ "$ENV" != "decrypt" ]; then
    echo "Hinweis: --gunzip wird beim Import nicht benötigt, es wird automatisch entpackt."
fi

# --patch nur beim Import und nur mit einer konkreten .sql-Datei, damit nicht versehentlich
# ein kompletter Dump (neuester, aus der Liste, aus einer Quell-Umgebung) als Patch läuft.
# Dumps sind immer komprimiert, deshalb schließt das auch die meisten Vertipper aus.
if [ "$PATCH" -eq 1 ]; then
    if [ "$ENV" = "decrypt" ]; then
        echo "Fehler: --patch gibt es nur beim Import, nicht bei decrypt!"
        exit 1
    fi
    case "$2" in
        *.sql) ;;
        *.sql.gz|*.sql.gz.gpg)
            echo "Fehler: --patch nimmt nur .sql-Dateien! Komprimierte oder verschlüsselte Dateien vorher mit 'decryptDB.sh $2 --gunzip' entpacken."
            exit 1
            ;;
        *)
            echo "Fehler: --patch braucht als 2. Parameter eine .sql-Datei!"
            exit 1
            ;;
    esac
fi

# Voller Import in eine normale Umgebung: die Ziel-DB wird vorher komplett geleert, damit danach
# exakt der Stand des Dumps vorliegt (sonst blieben Tabellen, die nur in der Ziel-DB existieren,
# erhalten). DDEV leert die Datenbank bei import-db selbst, bei --patch wird nichts geleert.
LEEREN=0
if [ "$ENV" != "ddev" ] && [ "$PATCH" -eq 0 ]; then
    LEEREN=1
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

# decrypt: Zieldatei im aktuellen Ordner festlegen und Rückfrage bei vorhandener Datei,
# bevor ein Passwort abgefragt wird
if [ "$ENV" = "decrypt" ]; then
    OUT="$(basename "$FILE")"
    if [[ "$FILE" == *.gpg ]]; then
        OUT="${OUT%.gpg}"
    elif [ "$GUNZIP" -eq 0 ]; then
        echo "Fehler: Dump ist nicht verschlüsselt, nichts zu tun (mit --gunzip nur entpacken)!"
        exit 1
    fi
    if [ "$GUNZIP" -eq 1 ]; then
        if [[ "$OUT" != *.gz ]]; then
            echo "Fehler: Dump ist nicht komprimiert, nichts zu tun!"
            exit 1
        fi
        OUT="${OUT%.gz}"
    fi
    if [ -e "$OUT" ]; then
        read -p "Datei '${OUT}' existiert bereits. Überschreiben? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
            echo "Abgebrochen."
            exit 0
        fi
    fi
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
        if [ "$ENV" = "decrypt" ]; then
            echo "Fehler: Falsches Passwort oder beschädigter Dump!"
        else
            echo "Fehler: Falsches Passwort oder beschädigter Dump! Die Datenbank wurde nicht angefasst."
        fi
        exit 1
    fi
fi

# decrypt: Ergebnis erst in eine Temp-Datei (Rechte 600) schreiben, damit bei einem Fehler
# oder Abbruch keine halbe Datei zurückbleibt
if [ "$ENV" = "decrypt" ]; then
    set -o pipefail
    TMP=$(mktemp "./${OUT}.XXXXXX") || exit 1
    trap 'rm -f "$TMP"; exit 130' INT TERM
    if [[ "$FILE" == *.gpg && "$GUNZIP" -eq 1 ]]; then
        gpg_decrypt "$FILE" | gunzip > "$TMP"
    elif [[ "$FILE" == *.gpg ]]; then
        gpg_decrypt "$FILE" > "$TMP"
    else
        gunzip -c "$FILE" > "$TMP"
    fi
    STATUS=$?
    unset DUMP_PASS
    if [ "$STATUS" -ne 0 ]; then
        rm -f "$TMP"
        echo "Fehler: Beim Entschlüsseln ist ein Problem aufgetreten!"
        exit 1
    fi
    mv -f "$TMP" "$OUT"
    trap - INT TERM
    if [[ "$FILE" != *.gpg ]]; then
        echo "Entpackt nach: ./${OUT}"
    elif [ "$GUNZIP" -eq 1 ]; then
        echo "Entschlüsselt und entpackt nach: ./${OUT}"
    else
        echo "Entschlüsselt nach: ./${OUT}"
    fi
    if [ "$GUNZIP" -eq 0 ]; then
        echo "Ansehen ohne Entpacken: zless ${OUT}  |  zgrep \"suchbegriff\" ${OUT}"
    fi
    exit 0
fi

detect_dump_kind

# --patch prüft oben nur die Endung. Ist eine .sql-Datei in Wahrheit komprimiert (etwa ein
# umbenannter Dump), zeigte die Vorschau nur Binärdaten, deshalb auch das ablehnen.
if [ "$PATCH" -eq 1 ] && [ "$DUMP_KIND" != "plain" ]; then
    echo "Fehler: --patch nimmt nur .sql-Dateien mit unkomprimiertem Inhalt! '${FILE}' ist gzip-komprimiert."
    exit 1
fi

# Für mysql das Passwort sicher bereitstellen (nie als Argument, sonst per ps sichtbar)
if [ "$ENV" != "ddev" ]; then
    export MYSQL_PWD="$DB_PASS"
fi

# Beim Leeren die Objekte schon vor der Sicherheitsabfrage ermitteln, damit sie ihre Anzahl
# nennen kann und ein Verbindungsfehler auffällt, bevor etwas passiert
if [ "$LEEREN" -eq 1 ]; then
    load_db_objects
fi

# Bei --patch den Inhalt der Datei vor der Sicherheitsabfrage zeigen. Lange Dateien und lange
# Zeilen werden gekürzt, damit ein versehentlich angegebener Dump (eine Tabelle pro INSERT-Zeile,
# oft mehrere MB) die Warnung nicht aus dem Terminal schiebt.
if [ "$PATCH" -eq 1 ]; then
    PREVIEW_LINES=30
    PREVIEW_CHARS=200
    # awk statt wc -l, damit eine letzte Zeile ohne Zeilenumbruch mitgezählt wird
    TOTAL_LINES=$(awk 'END { print NR }' "$FILE")
    echo "Inhalt von '${FILE}' (${TOTAL_LINES} Zeilen):"
    echo "----------------------------------------"
    head -n "$PREVIEW_LINES" "$FILE" \
        | awk -v max="$PREVIEW_CHARS" '{ if (length($0) > max) print substr($0, 1, max) "…"; else print }'
    echo "----------------------------------------"
    if [ "$TOTAL_LINES" -gt "$PREVIEW_LINES" ]; then
        echo "(nur die ersten ${PREVIEW_LINES} von ${TOTAL_LINES} Zeilen angezeigt)"
    fi
fi

# Sicherheitsabfrage vor dem Import (besonders wichtig bei 'live')
if [ "$PATCH" -eq 1 ]; then
    if [ "$ENV" = "ddev" ]; then
        echo "ACHTUNG: Die SQL-Befehle aus '${FILE}' werden auf der Datenbank des DDEV-Projekts im aktuellen Ordner ($PWD) AUSGEFÜHRT!"
    else
        echo "ACHTUNG: Die SQL-Befehle aus '${FILE}' werden auf der Datenbank [ $DB_NAME ] (Umgebung: $ENV) AUSGEFÜHRT!"
    fi
    echo "Die Datenbank wird vorher nicht geleert."
elif [ "$ENV" = "ddev" ]; then
    echo "ACHTUNG: Die Datenbank des DDEV-Projekts im aktuellen Ordner ($PWD) wird GELEERT und durch den Inhalt von '${FILE}' ERSETZT!"
elif [ ${#DB_OBJECTS[@]} -eq 0 ]; then
    echo "ACHTUNG: Die Datenbank [ $DB_NAME ] (Umgebung: $ENV) ist leer und wird mit dem Inhalt von '${FILE}' befüllt!"
else
    echo "ACHTUNG: Alle ${#DB_OBJECTS[@]} Tabellen/Views der Datenbank [ $DB_NAME ] (Umgebung: $ENV) werden GELÖSCHT und durch den Inhalt von '${FILE}' ERSETZT!"
fi
read -p "Bist du dir absolut sicher? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    unset MYSQL_PWD DUMP_PASS
    echo "Import abgebrochen."
    exit 0
fi

# Liste nach der Bestätigung neu holen, damit auch Tabellen gelöscht werden, die entstanden sind,
# während die Abfrage offen war
if [ "$LEEREN" -eq 1 ]; then
    load_db_objects
fi

echo "Starte Import für Umgebung: [$ENV] aus Datei: $FILE ..."

# Import-Kommando festlegen: DDEV liest den Dump von stdin und leert die DB vorher, außer bei --patch
if [ "$ENV" = "ddev" ]; then
    IMPORT_CMD=(ddev import-db)
    [ "$PATCH" -eq 1 ] && IMPORT_CMD+=(--no-drop)
else
    IMPORT_CMD=(mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME")
fi

# Schlägt ein Schritt der Pipe fehl (z. B. gpg oder gunzip), soll das nicht als Erfolg durchgehen
set -o pipefail

# Beim Leeren laufen die DROP-Befehle in derselben mysql-Sitzung direkt vor dem Dump
if [ "$LEEREN" -eq 1 ]; then
    { drop_statements; dump_content; } | "${IMPORT_CMD[@]}"
else
    dump_content | "${IMPORT_CMD[@]}"
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
