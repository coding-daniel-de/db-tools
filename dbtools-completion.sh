# Tab-Vervollständigung für db-export, db-import, db-decrypt, db-send, db-fetch (bash).
# Wird per source aus der ~/.bashrc geladen (install.sh trägt das ein), nicht ausführbar.
# Die Config-Namen werden erst beim Tab-Druck gelesen (über configsDB.sh --names), nicht beim Shell-Start.

_DBTOOLS_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Namen der Configs der Art $1 (db oder remote) als Wörter für compgen
_dbtools_names() {
    "${_DBTOOLS_DIR}/configsDB.sh" --names "$1" 2>/dev/null
}

# Gemeinsame Vervollständigung. Umgebung des Aufrufs:
#   _dbtools_pos1: Art der Namen an Position 1 (db oder remote)
#   _dbtools_words: zusätzliche Wörter an Position 1 (reservierte Namen, die das Skript dort akzeptiert)
#   _dbtools_opts: alle Optionen des Befehls
#   _dbtools_valopts: Optionen mit Wert (--from, --env, --out), je als "option:art" (art = db oder dir)
_dbtools_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
    local pos1="$1" words="$2" opts="$3" valopts="$4"
    local entry opt kind i w pos=0 skip=0 candidates
    COMPREPLY=()

    # Wert einer Option mit Wert
    for entry in $valopts; do
        opt="${entry%%:*}"; kind="${entry##*:}"
        if [ "$prev" = "$opt" ]; then
            case "$kind" in
                dir) mapfile -t COMPREPLY < <(compgen -d -- "$cur") ;;
                *) mapfile -t COMPREPLY < <(compgen -W "$(_dbtools_names "$kind")" -- "$cur") ;;
            esac
            return 0
        fi
        # --opt=wert
        if [[ "$cur" == "${opt}="* ]]; then
            local val="${cur#*=}"
            case "$kind" in
                dir) mapfile -t COMPREPLY < <(compgen -d -- "$val") ;;
                *) mapfile -t COMPREPLY < <(compgen -W "$(_dbtools_names "$kind")" -- "$val") ;;
            esac
            COMPREPLY=("${COMPREPLY[@]/#/${opt}=}")
            return 0
        fi
    done

    # Optionen anbieten
    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
        return 0
    fi

    # Position der aktuellen Eingabe unter den Positionsparametern bestimmen (Optionen und ihre Werte zählen nicht)
    for ((i = 1; i < COMP_CWORD; i++)); do
        w="${COMP_WORDS[i]}"
        if [ "$skip" -eq 1 ]; then skip=0; continue; fi
        case "$w" in
            --*=*) continue ;;
            --*)
                for entry in $valopts; do
                    [ "${entry%%:*}" = "$w" ] && skip=1
                done
                continue
                ;;
        esac
        pos=$((pos + 1))
    done

    if [ "$pos" -eq 0 ]; then
        candidates="$(_dbtools_names "$pos1") $words"
        mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$cur")
    else
        # Dateiname (Position 2): normale Dateivervollständigung
        mapfile -t COMPREPLY < <(compgen -f -- "$cur")
    fi
    return 0
}

_dbtools_complete_export() {
    _dbtools_complete db "ddev" "--dry-run --no-encrypt --out --configs" "--out:dir"
}
_dbtools_complete_import() {
    _dbtools_complete db "ddev decrypt" "--from --latest --gunzip --patch --configs" "--from:db"
}
_dbtools_complete_decrypt() {
    # db-decrypt ist importDB.sh decrypt: kein Ziel an Position 1, die Position gehört dem Dateinamen
    local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
    if [ "$prev" = "--from" ]; then
        mapfile -t COMPREPLY < <(compgen -W "$(_dbtools_names db)" -- "$cur")
    elif [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--from --latest --gunzip --configs" -- "$cur")
    else
        mapfile -t COMPREPLY < <(compgen -f -- "$cur")
    fi
}
_dbtools_complete_transfer() {
    _dbtools_complete remote "" "--env --patch --configs" "--env:db"
}

complete -o default -F _dbtools_complete_export db-export
complete -o default -F _dbtools_complete_import db-import
complete -o default -F _dbtools_complete_decrypt db-decrypt
complete -o default -F _dbtools_complete_transfer db-send
complete -o default -F _dbtools_complete_transfer db-fetch
