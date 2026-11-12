#!/bin/bash
# Legt den User-Ordner ~/db-tools-conf/ für eigene Configs an und füllt ihn mit den Vorlagen aus conf/
# der Installation (db_template.conf, remote_template.conf, dbtools.conf.example). Nur fehlende Dateien,
# vorhandene werden nie überschrieben (außer mit --templates, und das betrifft nur die drei Vorlagen).
# Nutzung: initConfigDB.sh [name] [--templates]
#   (ohne Name)    Ordner (Rechte 700) und fehlende Vorlagen anlegen, ändert bei Wiederholung nichts
#   name           zusätzlich db_<name>.conf aus der Vorlage (Rechte 600), Abbruch wenn sie schon existiert
#   --templates    nur die drei Vorlagen aktualisieren (überschreiben ohne Rückfrage), nicht mit name

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "${SCRIPT_DIR}/dbtools-lib.sh" || exit 1

TEMPLATES=(db_template.conf remote_template.conf dbtools.conf.example)

usage() {
    echo "Nutzung: $0 [name] [--templates]"
    echo "         legt ${USER_DIR} (Rechte 700) an und kopiert die fehlenden Vorlagen aus ${SCRIPT_DIR}/conf hinein"
    echo "         name: zusätzlich db_<name>.conf aus der Vorlage anlegen (Rechte 600), Abbruch wenn sie schon existiert"
    echo "         --templates: nur die drei Vorlagen überschreiben (meldet, welche sich geändert haben), nicht mit name"
    echo "Beispiel: $0                  (Ordner und Vorlagen anlegen, vorhandenes bleibt unberührt)"
    echo "Beispiel: $0 live             (zusätzlich db_live.conf aus der Vorlage anlegen, Pfad wird genannt)"
    echo "Beispiel: $0 --templates      (Vorlagen auf den Stand der Installation bringen, echte Configs bleiben)"
}

USER_DIR="$(user_conf_dir)"
UPDATE_TEMPLATES=0
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --templates)
            UPDATE_TEMPLATES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "Fehler: Unbekannte Option '${1}'!"
            usage
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift
done

if [ ${#POSITIONAL[@]} -gt 1 ]; then
    echo "Fehler: Es kann nur ein Name angegeben werden!"
    usage
    exit 1
fi
NAME="${POSITIONAL[0]}"

if [ -n "$NAME" ]; then
    if [ "$UPDATE_TEMPLATES" -eq 1 ]; then
        echo "Fehler: --templates und ein Name lassen sich nicht kombinieren (--templates fasst nur die Vorlagen an)!"
        usage
        exit 1
    fi
    # ddev und decrypt sind beim Import reservierte Wörter, template wäre die Vorlage selbst
    if ! [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Fehler: Ungültiger Name '${NAME}' (erlaubt: Buchstaben, Ziffern, Punkt, Unterstrich, Bindestrich)!"
        exit 1
    fi
    case "$NAME" in
        ddev|decrypt|template)
            echo "Fehler: '${NAME}' ist als Name reserviert!"
            exit 1
            ;;
    esac
fi

for t in "${TEMPLATES[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/conf/${t}" ]; then
        echo "Fehler: Vorlage '${SCRIPT_DIR}/conf/${t}' fehlt!"
        exit 1
    fi
done

NEW_CONF="${USER_DIR}/db_${NAME}.conf"
if [ -n "$NAME" ] && [ -e "$NEW_CONF" ]; then
    echo "Fehler: '${NEW_CONF}' existiert bereits! Es wurde nichts geändert."
    exit 1
fi

# Ordner anlegen (700), ein vorhandener bleibt unverändert
if [ -d "$USER_DIR" ]; then
    echo "Schon vorhanden: ${USER_DIR}"
else
    mkdir -m 700 -p "$USER_DIR" || exit 1
    echo "Angelegt: ${USER_DIR} (Rechte 700)"
fi

# Vorlagen: fehlende anlegen, mit --templates zusätzlich abweichende überschreiben
for t in "${TEMPLATES[@]}"; do
    src="${SCRIPT_DIR}/conf/${t}"
    dst="${USER_DIR}/${t}"
    if [ ! -e "$dst" ]; then
        cp "$src" "$dst" || exit 1
        echo "Angelegt: $dst"
    elif [ "$UPDATE_TEMPLATES" -eq 1 ]; then
        if cmp -s "$src" "$dst"; then
            echo "Unverändert: $dst"
        else
            cp "$src" "$dst" || exit 1
            echo "Aktualisiert: $dst"
        fi
    else
        echo "Schon vorhanden: $dst"
    fi
done

# Neue Umgebung aus der Vorlage (enthält später Passwörter, deshalb von Anfang an 600)
if [ -n "$NAME" ]; then
    ( umask 077; cp "${SCRIPT_DIR}/conf/db_template.conf" "$NEW_CONF" ) || exit 1
    chmod 600 "$NEW_CONF" || exit 1
    echo "Angelegt: $NEW_CONF (Rechte 600), bitte DB_HOST, DB_USER, DB_PASS, DB_NAME und PREFIX eintragen."
fi
