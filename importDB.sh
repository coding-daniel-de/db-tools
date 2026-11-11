#!/bin/bash

# Optionen (--...) an beliebiger Stelle herausnehmen, danach gelten nur noch die Positionsparameter
GUNZIP=0
PATCH=0
LATEST=0
FROM_ENV=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --gunzip)
            GUNZIP=1
            ;;
        --patch)
            PATCH=1
            ;;
        --latest)
            LATEST=1
            ;;
        --from)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "Fehler: --from braucht eine Quell-Umgebung (z. B. --from dev)!"
                exit 1
            fi
            FROM_ENV="$2"
            shift
            ;;
        --*)
            echo "Fehler: Unbekannte Option '${1}'!"
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift
done
set -- "${POSITIONAL[@]}"

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 <ziel-umgebung | ddev | decrypt> [dateiname.sql[.gz[.gpg]]] [--from quell-umgebung] [--latest] [--gunzip] [--patch]"
    echo "         ohne Dateiname wird eine Liste der Dumps gezeigt (Enter = Nr. 1, der neueste)"
    echo "         --from filtert die Liste auf die Dumps dieser Umgebung (sonst auf die der Ziel-Umgebung)"
    echo "         --latest nimmt ohne Liste den neuesten Dump"
    echo "         mit --patch: Liste bzw. Dateiname im Patch-Ordner (.sql/.sql.gz), ohne --from und --latest"
    echo "Beispiel: $0 dev                      (Liste der dev-Dumps, in die Umgebung dev importieren)"
    echo "Beispiel: $0 update --from dev        (Liste der dev-Dumps, nach update importieren)"
    echo "Beispiel: $0 update --from dev --latest   (neuesten dev-Dump ohne Liste nach update importieren)"
    echo "Beispiel: $0 update dump.sql.gz       (diese Datei nach update importieren)"
    echo "Beispiel: $0 ddev --from dev          (dev-Dump aus Liste in das DDEV-Projekt im aktuellen Ordner importieren)"
    echo "Beispiel: $0 ddev                     (dito, Liste aller Dumps)"
    echo "Beispiel: $0 decrypt                  (Dump aus Liste nur entschlüsseln, Ergebnis im aktuellen Ordner)"
    echo "Beispiel: $0 decrypt --from dev --gunzip   (entschlüsseln und entpacken, --gunzip nur bei decrypt)"
    echo "Beispiel: $0 live aenderungen.sql --patch  (nur die Befehle der Datei ausführen, DB wird nicht geleert)"
    echo "Beispiel: $0 stage --patch            (dito, Datei aus einer Liste des Patch-Ordners auswählen)"
    exit 1
fi

if [ $# -gt 2 ]; then
    echo "Fehler: Zu viele Parameter ('${3}')! Erlaubt sind Ziel und optional ein Dateiname, die Quell-Umgebung steht in --from."
    exit 1
fi

# Ordner dieses Skripts ermitteln, damit der Aufruf aus jedem Ordner funktioniert
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Gemeinsame Funktionen laden
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

# --- Funktionen ---

# Zweck eines reservierten Namens für den ersten Parameter (keine Umgebung mit db_<name>.conf).
# Gibt für normale Umgebungen nichts aus.
# BEWUSSTE ABWEICHUNG von der Aufrufkonvention (Modi nicht an der Umgebungs-Position): ddev und
# decrypt sind echte Modi und bleiben als reservierte Namen an Position 1. Ein Umbau auf --ddev
# bzw. --decrypt brächte Aufwand ohne Gewinn im Alltag (siehe README).
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

# Ordner, in denen nach Dumps gesucht wird, als Text für Meldungen ('a' und 'b')
search_dirs_text() {
    local d TEXT=""
    for d in "${SEARCH_DIRS[@]}"; do
        [ -n "$TEXT" ] && TEXT+=" und "
        TEXT+="'${d}'"
    done
    echo "$TEXT"
}

# Dumps in SEARCH_DIRS einsammeln und nach Datum sortiert (neueste zuerst) in DUMPS ablegen.
# $1 ist der Anfang des Dateinamens (leer = alle, sonst z. B. "proj-dev-"), die weiteren Parameter
# sind die Endungen (z. B. .sql .sql.gz). Die Sortierung gilt über alle Ordner hinweg.
gather_dumps() {
    local GLOB_START="$1" DIR EXT CANDIDATE
    shift
    local PATTERNS=()
    for DIR in "${SEARCH_DIRS[@]}"; do
        for EXT in "$@"; do
            PATTERNS+=("${DIR}/${GLOB_START}"*"${EXT}")
        done
    done
    local CANDIDATES
    mapfile -t CANDIDATES < <(ls -td "${PATTERNS[@]}" 2>/dev/null)
    # Nur echte Dateien anbieten (-d verhindert, dass ls Unterordner wie x.sql/ aufklappt)
    DUMPS=()
    for CANDIDATE in "${CANDIDATES[@]}"; do
        [ -f "$CANDIDATE" ] && DUMPS+=("$CANDIDATE")
    done
}

# Label (Name des Ordners) je Eintrag von SEARCH_DIRS in DIR_LABELS ablegen. Haben zwei Ordner
# denselben Namen, wird der volle Pfad als Label genommen, damit es eindeutig bleibt.
compute_dir_labels() {
    local I J NAMES=()
    DIR_LABELS=()
    for I in "${!SEARCH_DIRS[@]}"; do
        NAMES[$I]="$(basename "${SEARCH_DIRS[$I]}")"
        DIR_LABELS[$I]="${NAMES[$I]}"
    done
    for I in "${!SEARCH_DIRS[@]}"; do
        for J in "${!SEARCH_DIRS[@]}"; do
            if [ "$I" -ne "$J" ] && [ "${NAMES[$I]}" = "${NAMES[$J]}" ]; then
                DIR_LABELS[$I]="${SEARCH_DIRS[$I]}"
            fi
        done
    done
}

# Auswahlliste anzeigen (siehe gather_dumps für die Parameter), Nummer abfragen und FILE setzen.
# $1 ist ein Text für die Überschrift ("Dumps", "Patch-Dateien"). Bei mehreren Ordnern steht hinter
# jedem Eintrag das Label seines Ordners. Bricht das Skript bei leerer Liste oder ungültiger Auswahl ab.
select_dump() {
    local WHAT="$1" I J SELECTION LABEL
    shift
    gather_dumps "$@"
    if [ ${#DUMPS[@]} -eq 0 ]; then
        echo "Fehler: Keine ${WHAT} in $(search_dirs_text) gefunden!"
        exit 1
    fi
    if [ ${#SEARCH_DIRS[@]} -gt 1 ]; then
        compute_dir_labels
        echo "Verfügbare ${WHAT} (neueste zuerst) aus:"
        for I in "${!SEARCH_DIRS[@]}"; do
            echo "  ${SEARCH_DIRS[$I]}"
        done
    else
        echo "Verfügbare ${WHAT} in '${SEARCH_DIRS[0]}' (neueste zuerst):"
    fi
    for I in "${!DUMPS[@]}"; do
        LABEL=""
        if [ ${#SEARCH_DIRS[@]} -gt 1 ]; then
            for J in "${!SEARCH_DIRS[@]}"; do
                [ "$(dirname "${DUMPS[$I]}")" = "${SEARCH_DIRS[$J]}" ] && LABEL="      [${DIR_LABELS[$J]}]"
            done
        fi
        echo "  $((I + 1))) $(basename "${DUMPS[$I]}")${LABEL}"
    done
    # Enter nimmt Nr. 1 (neueste), aber nur bei echter Eingabe: bei EOF (read schlägt fehl) kein Default
    if read -p "Nummer wählen [1 = neueste]: " SELECTION; then
        SELECTION="${SELECTION:-1}"
    fi
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#DUMPS[@]}" ]; then
        echo "Fehler: Ungültige Auswahl '${SELECTION}'!"
        exit 1
    fi
    FILE="${DUMPS[$((SELECTION - 1))]}"
}

# Neuesten Dump (.sql, .sql.gz oder .sql.gz.gpg) zum Präfix $1 in SEARCH_DIRS suchen und in FILE ablegen.
# $2 beschreibt die Suche für die Fehlermeldung. Bricht das Skript ab, wenn nichts gefunden wird.
# Merkt sich Präfix in AUTO_PREFIX, damit die Sicherheitsabfrage auf diese Quelle filtern kann.
find_latest_dump() {
    AUTO_PREFIX="$1"
    gather_dumps "${1}-" .sql .sql.gz .sql.gz.gpg
    if [ ${#DUMPS[@]} -eq 0 ]; then
        echo "Fehler: Kein Dump für $2 in $(search_dirs_text) gefunden!"
        exit 1
    fi
    FILE="${DUMPS[0]}"
    echo "Verwende Dump: ${FILE}"
}

# Passwort für verschlüsselte Dumps abfragen und sofort prüfen, noch vor der Sicherheitsabfrage.
# gpg erkennt ein falsches Passwort nur mit einer 16-Bit-Kontrollsumme (etwa 1 von 65000 falschen
# Passwörtern rutscht durch), die Integritätsprüfung am Dateiende greift erst nach dem Import.
# Deshalb werden die ersten Bytes entschlüsselt und auf die gzip-Magic-Bytes (1f 8b) geprüft.
prompt_dump_password() {
    [[ "$FILE" == *.gpg ]] || return 0
    require_gpg || exit 1
    IFS= read -r -s -p "Passwort für '$(basename "$FILE")': " DUMP_PASS
    echo
    local MAGIC
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
    if ! OUTPUT=$(mysql -h "$DB_HOST" "${DB_PORT_ARGS[@]}" -u "$DB_USER" -N -B -r \
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
    load_db_conf "$CONF_FILE" || exit 1
fi

if [ "$GUNZIP" -eq 1 ] && [ "$ENV" != "decrypt" ]; then
    echo "Hinweis: --gunzip wird beim Import nicht benötigt, es wird automatisch entpackt."
fi

# --patch nur beim Import und nur mit einer konkreten Datei oder der Liste des Patch-Ordners,
# damit nicht versehentlich ein kompletter Dump (neuester, aus einer Quell-Umgebung) als Patch
# läuft. Ohne Dateiname wird die Liste gezeigt.
if [ "$PATCH" -eq 1 ]; then
    if [ "$ENV" = "decrypt" ]; then
        echo "Fehler: --patch gibt es nur beim Import, nicht bei decrypt!"
        exit 1
    fi
    case "$2" in
        *.sql.gz.gpg)
            echo "Fehler: --patch nimmt keine verschlüsselten Dateien! Vorher mit 'decryptDB.sh $2' entschlüsseln, das Ergebnis (.sql.gz) geht dann."
            exit 1
            ;;
    esac
    if [ -n "$FROM_ENV" ] || [ "$LATEST" -eq 1 ]; then
        echo "Fehler: --patch nimmt weder --from noch --latest (Patch-Dateien liegen im Patch-Ordner und haben keinen Umgebungs-Präfix)!"
        exit 1
    fi
fi

# Voller Import in eine normale Umgebung: die Ziel-DB wird vorher komplett geleert, damit danach
# exakt der Stand des Dumps vorliegt (sonst blieben Tabellen, die nur in der Ziel-DB existieren,
# erhalten). DDEV leert die Datenbank bei import-db selbst, bei --patch wird nichts geleert.
LEEREN=0
if [ "$ENV" != "ddev" ] && [ "$PATCH" -eq 0 ]; then
    LEEREN=1
fi

# Verzeichnisse für Dumps und Patch-Dateien ermitteln (Default oder dbtools.conf)
resolve_dirs
SOURCE_DIR="$DUMP_DIR"
# Suchordner für Dumps: normale Ziele nur DUMP_DIR, ddev zusätzlich DDEV_DUMP_DIR (zuerst), außer
# beide sind nach Auflösung derselbe Ordner
SEARCH_DIRS=("$SOURCE_DIR")
AUTO_PREFIX=""
if [ "$ENV" = "ddev" ] && [ "$(realpath -m "$DDEV_DUMP_DIR")" != "$(realpath -m "$DUMP_DIR")" ]; then
    SEARCH_DIRS=("$DDEV_DUMP_DIR" "$DUMP_DIR")
fi

# Dump-Datei bestimmen.
# Der 2. Parameter ist nur ein Dateiname (.sql/.sql.gz/.sql.gz.gpg). Die Quell-Umgebung steht in
# --from, ohne Dateiname kommt die Liste (Enter = Nr. 1, der neueste), --latest nimmt den neuesten
# Dump ohne Liste. Die Liste und --latest filtern auf den PREFIX der Quell-Umgebung (--from) bzw.
# der Ziel-Umgebung. Zugangsdaten bleiben immer die der Ziel-Umgebung! ddev und decrypt haben
# keinen eigenen PREFIX: ohne --from zeigt die Liste alle Dumps, --latest braucht dort --from.
# --patch: Liste bzw. Dateiname im Patch-Ordner (ohne --from und --latest, siehe oben).
FILE_ARG="$2"
if [ -n "$FILE_ARG" ]; then
    case "$FILE_ARG" in
        *.sql|*.sql.gz|*.sql.gz.gpg)
            FILE="$FILE_ARG"
            ;;
        *)
            echo "Fehler: '${FILE_ARG}' ist keine Dump-Datei (.sql, .sql.gz oder .sql.gz.gpg)!"
            if [ "$FILE_ARG" = "list" ]; then
                echo "Hinweis: 'list' gibt es nicht mehr. Ohne Dateiname wird die Liste automatisch gezeigt."
            elif [ -f "${SCRIPT_DIR}/db_${FILE_ARG}.conf" ]; then
                echo "Hinweis: Die Quell-Umgebung wird mit --from angegeben: $0 ${ENV} --from ${FILE_ARG}"
            fi
            exit 1
            ;;
    esac
    if [ -n "$FROM_ENV" ] || [ "$LATEST" -eq 1 ]; then
        echo "Fehler: Zusammen mit einem Dateinamen sind --from und --latest nicht sinnvoll!"
        exit 1
    fi
elif [ "$PATCH" -eq 1 ]; then
    SEARCH_DIRS=("$PATCH_DIR")
    select_dump "Patch-Dateien" "" .sql .sql.gz
else
    FILTER_PREFIX=""
    FILTER_TEXT=""
    if [ -n "$FROM_ENV" ]; then
        SOURCE_CONF="${SCRIPT_DIR}/db_${FROM_ENV}.conf"
        if [ ! -f "$SOURCE_CONF" ]; then
            echo "Fehler: Für --from '${FROM_ENV}' wurde 'db_${FROM_ENV}.conf' nicht gefunden (gesucht in '${SCRIPT_DIR}')!"
            exit 1
        fi
        FILTER_PREFIX=$(grep -E '^PREFIX=' "$SOURCE_CONF" | head -n 1 | cut -d '=' -f2- | tr -d '"')
        if [ -z "$FILTER_PREFIX" ]; then
            echo "Fehler: In '$SOURCE_CONF' wurde kein PREFIX gefunden!"
            exit 1
        fi
        FILTER_TEXT="Umgebung '${FROM_ENV}' (Präfix '${FILTER_PREFIX}')"
    elif ! is_reserved_env "$ENV"; then
        FILTER_PREFIX="$PREFIX"
        FILTER_TEXT="Präfix '${PREFIX}'"
    elif [ "$LATEST" -eq 1 ]; then
        echo "Fehler: --latest braucht bei '${ENV}' eine Quell-Umgebung (--from <umgebung>)!"
        exit 1
    fi
    if [ "$LATEST" -eq 1 ]; then
        find_latest_dump "$FILTER_PREFIX" "$FILTER_TEXT"
    else
        select_dump "Dumps" "${FILTER_PREFIX:+${FILTER_PREFIX}-}" .sql .sql.gz .sql.gz.gpg
    fi
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

prompt_dump_password

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

# Für mysql das Passwort sicher bereitstellen (nie als Argument, sonst per ps sichtbar)
if [ "$ENV" != "ddev" ]; then
    export MYSQL_PWD="$DB_PASS"
fi

# Beim Leeren die Objekte schon vor der Sicherheitsabfrage ermitteln, damit sie ihre Anzahl
# nennen kann und ein Verbindungsfehler auffällt, bevor etwas passiert
if [ "$LEEREN" -eq 1 ]; then
    load_db_objects
fi

# Bei --patch den (entpackten) Inhalt der Datei vor der Sicherheitsabfrage zeigen. Lange Dateien
# und lange Zeilen werden gekürzt, damit ein versehentlich angegebener Dump (eine Tabelle pro
# INSERT-Zeile, oft mehrere MB) die Warnung nicht aus dem Terminal schiebt.
if [ "$PATCH" -eq 1 ]; then
    PREVIEW_LINES=30
    PREVIEW_CHARS=200
    # awk statt wc -l, damit eine letzte Zeile ohne Zeilenumbruch mitgezählt wird
    TOTAL_LINES=$(dump_content | awk 'END { print NR }')
    echo "Inhalt von '${FILE}' (${TOTAL_LINES} Zeilen):"
    echo "----------------------------------------"
    dump_content | head -n "$PREVIEW_LINES" \
        | awk -v max="$PREVIEW_CHARS" '{ if (length($0) > max) print substr($0, 1, max) "…"; else print }'
    echo "----------------------------------------"
    if [ "$TOTAL_LINES" -gt "$PREVIEW_LINES" ]; then
        echo "(nur die ersten ${PREVIEW_LINES} von ${TOTAL_LINES} Zeilen angezeigt)"
    fi
    # Ein mysqldump ist mit --patch erlaubt (z. B. gezielt eine einzelne Tabelle ersetzen),
    # soll aber auffallen. Erkannt wird er an seinem Kopf in den ersten Zeilen.
    if dump_content | head -n 5 | grep -qE '^-- (MySQL|MariaDB) dump'; then
        echo "Hinweis: Die Datei ist ein mysqldump. Mit --patch werden nur die darin enthaltenen Tabellen ersetzt, alle anderen bleiben erhalten."
    fi
fi

# Sicherheitsabfrage vor dem Import (besonders wichtig bei 'live'). Wurde der Dump automatisch
# gewählt (neuester einer Quelle), kann mit l stattdessen ein anderer Dump derselben Quelle gewählt
# werden. Bewusst weiter mit Enter bestätigen, damit ein versehentlicher Tastendruck nicht reicht.
while true; do
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
    if [ -n "$AUTO_PREFIX" ]; then
        read -p "Bist du dir absolut sicher? (y/N/l): " CONFIRM
        if [[ "$CONFIRM" =~ ^[lL]$ ]]; then
            unset DUMP_PASS
            select_dump "Dumps" "${AUTO_PREFIX}-" .sql .sql.gz .sql.gz.gpg
            prompt_dump_password
            detect_dump_kind
            continue
        fi
    else
        read -p "Bist du dir absolut sicher? (y/N): " CONFIRM
    fi
    break
done
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
    IMPORT_CMD=(mysql -h "$DB_HOST" "${DB_PORT_ARGS[@]}" -u "$DB_USER" "$DB_NAME")
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
