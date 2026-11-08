#!/bin/bash
# Hilfsfunktionen für install.sh-Skripte (wird per source geladen, nicht ausführbar):
# Pfade normalisieren, PATH und Alias-Dateien in die ~/.bashrc eintragen, Login-Kette absichern.
# Eigenständig, ohne realpath (fehlt auf älteren Debian-Servern). Es wird nur ergänzt, nie überschrieben.
#
# Erwartet vom aufrufenden Skript (optional): SS_YES=1 = alle Rückfragen mit "ja" beantworten.
# Setzt: SS_BASHRC_TOUCHED=1, wenn die ~/.bashrc einen Eintrag von uns enthält (neu oder schon vorhanden).

SS_BASHRC="${HOME}/.bashrc"
SS_BASHRC_TOUCHED=0

# Pfad absolut machen und Slashes bereinigen (Ordner muss nicht existieren)
ss_abs_path() {
    local p="$1"
    case "$p" in
        /*) ;;
        *)  p="$PWD/$p" ;;
    esac
    while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
    while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
    printf '%s\n' "$p"
}

# Rückfrage mit Einzeltaste: 0 = ja. Ohne Terminal und ohne SS_YES immer nein.
ss_confirm() {
    [ "${SS_YES:-0}" -eq 1 ] && return 0
    [ -t 0 ] || return 1
    local answer
    read -r -n 1 -p "$1 (y/N) " answer
    [ -n "$answer" ] && echo
    [[ "$answer" =~ ^[yY]$ ]]
}

# PATH-Eintrag für einen Ordner in die ~/.bashrc (Marker "# bin-path: <ordner>")
ss_ensure_path() {
    local target="$1" marker expr line
    case ":${PATH}:" in
        *":${target}:"*) return 0 ;;
    esac
    marker="# bin-path: ${target}"
    # Im Home-Ordner mit $HOME schreiben, damit der Eintrag auch bei verschobenem Home stimmt
    case "$target" in
        "$HOME"/*) expr="\$HOME/${target#"$HOME"/}" ;;
        *)         expr="$target" ;;
    esac
    line="export PATH=\"${expr}:\$PATH\""
    echo
    if [ -f "$SS_BASHRC" ] && grep -qxF "$marker" "$SS_BASHRC"; then
        echo "'$target' ist schon in $SS_BASHRC eingetragen, gilt ab der nächsten Shell (oder: source ~/.bashrc)."
        SS_BASHRC_TOUCHED=1
    elif ss_confirm "'$target' liegt nicht im PATH. In $SS_BASHRC eintragen?"; then
        printf '\n%s\n%s\n' "$marker" "$line" >> "$SS_BASHRC" || return 1
        echo "Eingetragen in $SS_BASHRC, gilt ab der nächsten Shell (oder: source ~/.bashrc)."
        SS_BASHRC_TOUCHED=1
    else
        echo "Hinweis: '$target' liegt nicht im PATH. Zeile für ~/.bashrc (oder: ./install.sh --path):"
        echo "    $line"
    fi
}

# Source-Zeile für eine Alias-Datei in die ~/.bashrc: ss_ensure_source <datei> <kommentar>
ss_ensure_source() {
    local file="$1" comment="$2"
    if grep -qF "$file" "$SS_BASHRC" 2>/dev/null; then
        echo "Bereits in $SS_BASHRC eingetragen: $file"
        SS_BASHRC_TOUCHED=1
        return 0
    fi
    printf '\n# %s\n[ -f "%s" ] && source "%s"\n' "$comment" "$file" "$file" >> "$SS_BASHRC" || return 1
    echo "Eingetragen in $SS_BASHRC: $file (neue Shell öffnen oder: source ~/.bashrc)"
    SS_BASHRC_TOUCHED=1
}

# Login-Kette: bash liest beim Login nur die erste von ~/.bash_profile, ~/.bash_login, ~/.profile.
# Bindet diese Datei die ~/.bashrc nicht ein, fehlen PATH-Eintrag und Aliase beim SSH-Login.
# Nur sinnvoll, wenn SS_BASHRC_TOUCHED=1.
ss_ensure_login_chain() {
    [ "$SS_BASHRC_TOUCHED" -eq 1 ] || return 0
    local f login_file="" line='[ -f ~/.bashrc ] && . ~/.bashrc'
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [ -f "$f" ]; then login_file="$f"; break; fi
    done
    if [ -z "$login_file" ]; then
        login_file="$HOME/.profile"
    elif grep -qE '(^|[^#]*[[:space:];&|])(\.|source)[[:space:]]+[^#]*bashrc' "$login_file"; then
        return 0
    fi
    echo
    if ss_confirm "Beim Login liest bash '$login_file', und die bindet ~/.bashrc nicht ein. Zeile dort ergänzen?"; then
        printf '\n%s\n' "$line" >> "$login_file" || return 1
        echo "Ergänzt in $login_file, gilt ab dem nächsten Login."
    else
        echo "Hinweis: Beim Login liest bash '$login_file', und die bindet ~/.bashrc nicht ein."
        echo "Ohne diese Zeile dort fehlen PATH-Eintrag und Aliase beim SSH-Login:"
        echo "    $line"
    fi
}
