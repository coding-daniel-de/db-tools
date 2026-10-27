#!/bin/bash

# Optionen (--...) an beliebiger Stelle herausnehmen, danach gelten nur noch die Positionsparameter
DRY_RUN=0
NO_ENCRYPT=0
OUT_DIR=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --no-encrypt)
            NO_ENCRYPT=1
            ;;
        --out)
            if [ -z "$2" ]; then
                echo "Fehler: --out braucht einen Ordner!"
                exit 1
            fi
            OUT_DIR="$2"
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

# Ein Zielordner als Positionsparameter ist nicht (mehr) möglich
if [ "$#" -gt 1 ]; then
    echo "Fehler: Zielordner bitte mit --out angeben (z. B. --out ~/dumps)!"
    exit 1
fi

# Hilfe-Text anzeigen, wenn der erste Parameter komplett fehlt
if [ -z "$1" ]; then
    echo "Fehler: Bitte gib die Umgebung an!"
    echo "Nutzung: $0 [umgebung | ddev] [--dry-run] [--no-encrypt] [--out ordner]"
    echo "Beispiel: $0 dev"
    echo "Beispiel: $0 ddev              (DDEV-Projekt im aktuellen Ordner exportieren)"
    echo "Beispiel: $0 ddev --out ~/dumps    (dito, in einen anderen Ordner)"
    echo "Beispiel: $0 ddev --dry-run    (Befehl nur anzeigen, nicht ausführen)"
    echo "Beispiel: $0 dev --no-encrypt --out ~/backups    (ohne Rückfrage, in einen anderen Ordner)"
    exit 1
fi

# Ordner dieses Skripts ermitteln, damit der Aufruf aus jedem Ordner funktioniert
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

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
# DDEV liefert den Dump selbst gzip-komprimiert (ohne Sandbox-Kommentar in Zeile 1)
dump_sql() {
    if [ "$ENV" = "ddev" ]; then
        ddev export-db --gzip </dev/null
    else
        mysqldump -h "$DB_HOST" -u "$DB_USER" -v --opt "$DB_NAME" | tail -n +2 | gzip
    fi
}

# $1 in einfache Anführungszeichen setzen, damit der angezeigte Befehl kopierbar ist
# (Pfade wie "00_dumps" oder mit Leerzeichen)
shell_quote() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

# DDEV-Befehl so ausgeben, wie man ihn von Hand eingeben würde. gpg fragt das Passwort dabei
# selbst ab (die Ausführung im Skript übergibt es dagegen über einen Dateideskriptor).
ddev_command() {
    local cmd=""
    [ -d "$TARGET_DIR" ] || cmd="mkdir -p $(shell_quote "$TARGET_DIR") && "
    if [ "$ENCRYPT" -eq 1 ]; then
        cmd+="ddev export-db --gzip | gpg --symmetric --cipher-algo AES256 --compress-algo none -o $(shell_quote "${TARGET_DIR}/${FILE}")"
    else
        cmd+="ddev export-db --gzip > $(shell_quote "${TARGET_DIR}/${FILE}")"
    fi
    echo "$cmd"
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

if [ "$ENV" = "ddev" ]; then
    # Reservierter Name: eine gleichnamige Config würde ignoriert, deshalb vorher abbrechen
    if [ -f "$CONF_FILE" ]; then
        echo "Fehler: 'ddev' ist ein reservierter Name für den Export des DDEV-Projekts im aktuellen Ordner."
        echo "Die Datei 'db_ddev.conf' würde ignoriert. Bitte umbenennen oder löschen."
        exit 1
    fi
    # Projekt-Root: vom aktuellen Ordner nach oben bis zur ersten .ddev/config.yaml,
    # der Ordnername ergibt den PREFIX <ordner>-ddev
    PROJECT_ROOT="$PWD"
    while [ ! -f "${PROJECT_ROOT}/.ddev/config.yaml" ]; do
        if [ "$PROJECT_ROOT" = "/" ]; then
            echo "Fehler: Im aktuellen Ordner ($PWD) wurde kein DDEV-Projekt gefunden!"
            exit 1
        fi
        PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
    done
    PROJECT=$(basename "$PROJECT_ROOT")
    PREFIX="${PROJECT}-ddev"
else
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "Fehler: --dry-run gibt es nur bei ddev!"
        exit 1
    fi

    # Prüfen, ob die zugehörige Konfigurationsdatei existiert
    if [ ! -f "$CONF_FILE" ]; then
        echo "Fehler: Konfigurationsdatei 'db_${ENV}.conf' wurde nicht gefunden (gesucht in '${SCRIPT_DIR}')!"
        exit 1
    fi

    # Konfiguration einlesen (lädt die Variablen)
    source "$CONF_FILE"
fi

# Dump-Verzeichnis ermitteln (Default oder dbtools.conf)
resolve_dirs
if [ "$ENV" = "ddev" ]; then
    # Normalisieren (z. B. "tools/../sql-dumps"), damit der angezeigte Befehl gut lesbar ist
    TARGET_DIR=$(realpath -m -- "$DDEV_DUMP_DIR")
else
    TARGET_DIR="$DUMP_DIR"
fi
# --out hat Vorrang vor allem anderen (relativ zum aktuellen Ordner)
if [ -n "$OUT_DIR" ]; then
    TARGET_DIR=$(realpath -m -- "$OUT_DIR")
fi

# Verschlüsselung optional abfragen (bei --dry-run ohne Passwort, das fragt dann gpg selbst ab)
ENCRYPT=0
if [ "$NO_ENCRYPT" -eq 0 ] && ask_yes_no "Dump verschlüsseln? (y/N): "; then
    ENCRYPT=1
    if [ "$DRY_RUN" -eq 0 ]; then
        require_gpg || exit 1
        if ! ask_new_password; then
            unset ENC_PASS
            exit 1
        fi
    fi
fi

# Dateiname generieren
FILE="${PREFIX}-$(date +%Y-%m-%d-%H)Uhr.sql.gz"
if [ "$ENCRYPT" -eq 1 ]; then
    FILE="${FILE}.gpg"
fi

# DDEV mit --dry-run: nur den Befehl ausgeben
if [ "$DRY_RUN" -eq 1 ]; then
    ddev_command
    exit 0
fi

# Zielverzeichnis erstellen, falls es nicht existiert
mkdir -p "$TARGET_DIR"

# DDEV: auszuführenden Befehl anzeigen
if [ "$ENV" = "ddev" ]; then
    echo "Befehl: $(ddev_command)"
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
