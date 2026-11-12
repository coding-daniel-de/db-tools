source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
# Eigene Kopie der Installation, damit die Rechte frei gesetzt werden können (mktemp -d ist 700)
chmod 755 "$T"
INST="$T/opt/db-tools"; mkdir -p "$INST/lib" "$INST/conf"
cp "$REPO"/*.sh "$INST/"; cp "$REPO"/lib/shell-setup.sh "$INST/lib/"; cp "$REPO"/conf/* "$INST/conf/"
chmod -R u=rwX,go=rX "$INST"; chmod 755 "$T/opt"
G="$T/usr-local-bin"; mkdir -p "$G"
export DBTOOLS_GLOBAL_BIN="$G"
H="$T/hg"; mkdir -p "$H"; : > "$H/.bashrc"; export HOME="$H"
NAMES="db-export db-import db-decrypt db-send db-fetch db-configs db-init-config"

# --- ohne root: Abbruch, nichts angelegt ---
STUB_ID_U=1000 "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: ohne root Abbruch mit Hinweis auf sudo, nichts angelegt" "[ $rc -ne 0 ] && grep -q 'braucht root' $T/out && grep -q sudo $T/out && [ -z \"\$(ls -A $G)\" ]"

# --- als root: Symlinks, kein PATH-Eintrag, keine Login-Kette ---
STUB_ID_U=0 "$INST/install.sh" --global </dev/null >$T/out 2>&1; rc=$?
all=1; for n in $NAMES; do [ -L "$G/$n" ] || all=0; done
ok "global: Exit 0, sieben Symlinks im Zielordner" "[ $rc -eq 0 ] && [ $all -eq 1 ] && [ \"\$(ls $G | wc -l)\" -eq 7 ]"
ok "global: Symlink db-init-config zeigt auf initConfigDB.sh der Installation" "[ \"\$(readlink $G/db-init-config)\" = '$INST/initConfigDB.sh' ] && [ \"\$(readlink $G/db-export)\" = '$INST/exportDB.sh' ]"
ok "global: ~/.bashrc und Login-Dateien unberührt, kein PATH-Hinweis" "[ ! -s $H/.bashrc ] && [ ! -e $H/.profile ] && [ ! -e $H/.bash_profile ] && ! grep -q 'liegt nicht im PATH' $T/out"
ok "global: Hinweis auf db-init-config und Completion" "grep -q 'db-init-config' $T/out && grep -q 'dbtools-completion.sh' $T/out"

# --- zweiter Lauf, Konflikt ---
STUB_ID_U=0 "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: zweiter Lauf ok, nichts zu tun" "[ $rc -eq 0 ] && [ \"\$(grep -c 'Schon vorhanden' $T/out)\" -eq 7 ]"
G2="$T/g2"; mkdir -p "$G2"; echo fremd > "$G2/db-fetch"
DBTOOLS_GLOBAL_BIN="$G2" STUB_ID_U=0 "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: fremde Datei am Ziel -> Abbruch, unverändert, nichts angelegt" "[ $rc -ne 0 ] && [ \"\$(cat $G2/db-fetch)\" = fremd ] && [ ! -e $G2/db-export ]"

# --- Erreichbarkeit ---
G3="$T/g3"; mkdir -p "$G3"
chmod o-x "$T/opt"
STUB_ID_U=0 DBTOOLS_GLOBAL_BIN="$G3" "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: Ordner auf dem Weg ohne x für andere -> Abbruch, /opt/db-tools empfohlen, nichts angelegt" "[ $rc -ne 0 ] && grep -q 'nicht erreichbar' $T/out && grep -qF '$T/opt (Ordner' $T/out && grep -q '/opt/db-tools' $T/out && [ -z \"\$(ls -A $G3)\" ]"
chmod o+x "$T/opt"
chmod o-x "$INST/importDB.sh"
STUB_ID_U=0 DBTOOLS_GLOBAL_BIN="$G3" "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: Skript ohne x für andere -> Abbruch, Datei genannt" "[ $rc -ne 0 ] && grep -qF 'importDB.sh (fehlt: r und x' $T/out && [ -z \"\$(ls -A $G3)\" ]"
chmod o+x "$INST/importDB.sh"; chmod o-r "$INST/dbtools-lib.sh"
STUB_ID_U=0 DBTOOLS_GLOBAL_BIN="$G3" "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: Lib nicht lesbar für andere -> Abbruch" "[ $rc -ne 0 ] && grep -qF 'dbtools-lib.sh (fehlt: r' $T/out && [ -z \"\$(ls -A $G3)\" ]"
chmod o+r "$INST/dbtools-lib.sh"; chmod o-r "$INST/conf/db_template.conf"
STUB_ID_U=0 DBTOOLS_GLOBAL_BIN="$G3" "$INST/install.sh" --global >$T/out 2>&1; rc=$?
ok "global: Vorlage nicht lesbar für andere -> Abbruch" "[ $rc -ne 0 ] && grep -qF 'db_template.conf (fehlt: r' $T/out"
chmod o+r "$INST/conf/db_template.conf"
STUB_ID_U=0 DBTOOLS_GLOBAL_BIN="$G3" "$INST/install.sh" --global >$T/out 2>&1
ok "global: nach Korrektur der Rechte läuft es durch" "[ \"\$(ls $G3 | wc -l)\" -eq 7 ]"

# --- Kombinationen ---
for args in "--global --path" "--global $T/x" "--path --global"; do
    STUB_ID_U=0 "$INST/install.sh" $args >$T/out 2>&1; rc=$?
    ok "global: '$args' nicht kombinierbar -> Fehler" "[ $rc -ne 0 ] && grep -q 'nicht mit --path oder einem Zielordner kombinieren' $T/out && [ ! -e $T/x ]"
done
"$INST/install.sh" --unbekannt >$T/out 2>&1; rc=$?
ok "install: unbekannte Option -> Fehler" "[ $rc -ne 0 ] && grep -q 'Unbekannte Option' $T/out"

# --- Lokaler Lauf bleibt wie bisher (Option --path nach dem Zielordner ist neu erlaubt) ---
( HOME="$H" "$INST/install.sh" "$T/lb" --path ) >$T/out 2>&1; rc=$?
ok "install lokal: Zielordner vor --path, db-init-config verlinkt" "[ $rc -eq 0 ] && [ -L $T/lb/db-init-config ] && grep -q 'export PATH' $H/.bashrc"
rm -rf "$T"; exit $PASSFAIL
