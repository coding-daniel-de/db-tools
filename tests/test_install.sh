source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
B="$T/bin"

# --- Anlegen, Ordner wird bei Bedarf erstellt ---
mkdir -p "$T/h0"; : > "$T/h0/.bashrc"
( cd "$T/elsewhere" && HOME="$T/h0" "$REPO/install.sh" "$B" </dev/null ) >$T/out 2>&1; rc=$?
ok "install: Exit 0, sechs Symlinks mit absolutem Ziel" "[ $rc -eq 0 ] && [ \"\$(readlink $B/db-export)\" = '$REPO/exportDB.sh' ] && [ \"\$(readlink $B/db-import)\" = '$REPO/importDB.sh' ] && [ \"\$(readlink $B/db-decrypt)\" = '$REPO/decryptDB.sh' ] && [ \"\$(readlink $B/db-send)\" = '$REPO/sendDB.sh' ] && [ \"\$(readlink $B/db-fetch)\" = '$REPO/fetchDB.sh' ] && [ \"\$(readlink $B/db-configs)\" = '$REPO/configsDB.sh' ]"
ok "install: kein Symlink fuer backupAll" "[ ! -e $B/backupAll.sh ] && ! ls $B | grep -qi backup"
ok "install: PATH-Hinweis, wenn Zielordner nicht im PATH" "grep -q 'liegt nicht im PATH' $T/out && grep -q 'export PATH=\"$B:' $T/out"

# --- --path: Eintrag in die bashrc, idempotent ---
H="$T/home"; mkdir -p "$H"; : > "$H/.bashrc"
( HOME="$H" "$REPO/install.sh" --path "$H/bin" ) >$T/out 2>&1; rc=$?
ok "install --path: bashrc-Eintrag mit \$HOME" "[ $rc -eq 0 ] && grep -qxF 'export PATH=\"\$HOME/bin:\$PATH\"' $H/.bashrc"
( HOME="$H" "$REPO/install.sh" --path "$H/bin" ) >$T/out 2>&1
ok "install --path: zweiter Lauf traegt nicht doppelt ein" "[ \"\$(grep -c '^export PATH' $H/.bashrc)\" -eq 1 ]"
H2="$T/home2"; mkdir -p "$H2"; : > "$H2/.bashrc"
( HOME="$H2" "$REPO/install.sh" "$H2/bin" </dev/null ) >$T/out 2>&1
ok "install: ohne Terminal und ohne --path bleibt bashrc unveraendert" "[ ! -s $H2/.bashrc ] && grep -q 'liegt nicht im PATH' $T/out"

# --- Wiederholbar ---
( "$REPO/install.sh" "$B" ) >$T/out 2>&1; rc=$?
ok "install: zweiter Lauf ok, nichts zu tun" "[ $rc -eq 0 ] && [ \"\$(grep -c 'Schon vorhanden' $T/out)\" -eq 6 ]"

# --- Zielordner im PATH: kein Hinweis ---
( PATH="$B:$PATH" "$REPO/install.sh" "$B" ) >$T/out 2>&1
ok "install: kein PATH-Hinweis, wenn Zielordner im PATH" "! grep -q 'PATH' $T/out"

# --- Konflikte: nichts ueberschreiben, nichts halb installieren ---
B2="$T/bin2"; mkdir -p "$B2"; echo fremd > "$B2/db-import"
( "$REPO/install.sh" "$B2" ) >$T/out 2>&1; rc=$?
ok "install: fremde Datei -> Abbruch, Datei unveraendert, nichts angelegt" "[ $rc -ne 0 ] && [ \"\$(cat $B2/db-import)\" = fremd ] && [ ! -e $B2/db-export ] && grep -q 'db-import' $T/out"
B3="$T/bin3"; mkdir -p "$B3"; ln -s /bin/true "$B3/db-export"
( "$REPO/install.sh" "$B3" ) >$T/out 2>&1; rc=$?
ok "install: Symlink woandershin -> Abbruch, unveraendert" "[ $rc -ne 0 ] && [ \"\$(readlink $B3/db-export)\" = /bin/true ] && [ ! -e $B3/db-import ]"

# --- Aufruf ueber Symlink findet Lib und Config ---
mkdir -p "$T/symbin"
for n in exportDB:db-export importDB:db-import decryptDB:db-decrypt backupAll:backupAll sendDB:db-send fetchDB:db-fetch configsDB:db-configs; do ln -s "$T/tools/${n%%:*}.sh" "$T/symbin/${n##*:}"; done
( cd "$T/elsewhere" && "$T/symbin/db-export" test --no-encrypt ) >$T/out 2>&1; rc=$?
ok "Export per Symlink: Config und Lib gefunden" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-test-*.sql.gz >/dev/null 2>&1"
( cd "$T/elsewhere" && "$T/symbin/db-import" </dev/null ) >$T/out 2>&1
ok "Import per Symlink: Lib gefunden" "! grep -q 'dbtools-lib.sh' $T/out"
( cd "$T/elsewhere" && "$T/symbin/db-decrypt" </dev/null ) >$T/out 2>&1
ok "Decrypt per Symlink: Lib gefunden" "! grep -q 'dbtools-lib.sh' $T/out"
( cd "$T/elsewhere" && "$T/symbin/backupAll" ) >$T/out 2>&1
ok "backupAll per Symlink: Lib gefunden" "! grep -q 'dbtools-lib.sh' $T/out"
rm -rf "$T"; exit $PASSFAIL
