source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
B="$T/bin"

# --- Anlegen, Ordner wird bei Bedarf erstellt ---
( cd "$T/elsewhere" && "$REPO/install.sh" "$B" ) >$T/out 2>&1; rc=$?
ok "install: Exit 0, drei Symlinks mit absolutem Ziel" "[ $rc -eq 0 ] && [ \"\$(readlink $B/db-export)\" = '$REPO/exportDB.sh' ] && [ \"\$(readlink $B/db-import)\" = '$REPO/importDB.sh' ] && [ \"\$(readlink $B/db-decrypt)\" = '$REPO/decryptDB.sh' ]"
ok "install: kein Symlink fuer backupAll" "[ ! -e $B/backupAll.sh ] && ! ls $B | grep -qi backup"
ok "install: PATH-Hinweis, wenn Zielordner nicht im PATH" "grep -q 'liegt nicht im PATH' $T/out && grep -q 'export PATH=\"$B:' $T/out"

# --- Wiederholbar ---
( "$REPO/install.sh" "$B" ) >$T/out 2>&1; rc=$?
ok "install: zweiter Lauf ok, nichts zu tun" "[ $rc -eq 0 ] && [ \"\$(grep -c 'Schon vorhanden' $T/out)\" -eq 3 ]"

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
for n in exportDB:db-export importDB:db-import decryptDB:db-decrypt backupAll:backupAll; do ln -s "$T/tools/${n%%:*}.sh" "$T/symbin/${n##*:}"; done
( cd "$T/elsewhere" && "$T/symbin/db-export" test --no-encrypt ) >$T/out 2>&1; rc=$?
ok "Export per Symlink: Config und Lib gefunden" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-test-*.sql.gz >/dev/null 2>&1"
( cd "$T/elsewhere" && "$T/symbin/db-import" </dev/null ) >$T/out 2>&1
ok "Import per Symlink: Lib gefunden" "! grep -q 'dbtools-lib.sh' $T/out"
( cd "$T/elsewhere" && "$T/symbin/db-decrypt" </dev/null ) >$T/out 2>&1
ok "Decrypt per Symlink: Lib gefunden" "! grep -q 'dbtools-lib.sh' $T/out"
( cd "$T/elsewhere" && "$T/symbin/backupAll" ) >$T/out 2>&1
ok "backupAll per Symlink: Lib gefunden" "! grep -q 'dbtools-lib.sh' $T/out"
rm -rf "$T"; exit $PASSFAIL
