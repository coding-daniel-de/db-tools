source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"
run() { ( cd "$T/elsewhere" && "$T/tools/exportDB.sh" ddev "$@" ); }
reset() { rm -rf "$D" "$T/ddev-args" "$T/out" "$T/ddev-dumps" "$T/elsewhere/rel"; }

# --- Standard-Ordner, Dateiname aus Projektname ---
reset; echo n | run >$T/out 2>&1; rc=$?
F=$(ls $D/meinprojekt-ddev-*Uhr.sql.gz 2>/dev/null)
ok "ddev: <projekt>-ddev-<datum>Uhr.sql.gz im DUMP_DIR, Exit 0" "[ $rc -eq 0 ] && [ -n \"$F\" ] && [[ \"\$(basename $F)\" =~ ^meinprojekt-ddev-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}Uhr\.sql\.gz$ ]]"
ok "ddev: Inhalt aus ddev export-db" "gunzip -c $F | grep -q 'CREATE TABLE ddev_t' && [ \"\$(cat $T/ddev-args)\" = 'export-db --gzip' ]"
ok "ddev: Befehl wird angezeigt" "grep -q \"^Befehl: ddev export-db --gzip > '$D/meinprojekt-ddev-\" $T/out && grep -q 'Erfolgreich exportiert' $T/out"

# --- DDEV_DUMP_DIR aus dbtools.conf ---
reset; echo "DDEV_DUMP_DIR=\"$T/ddev-dumps\"" > "$T/tools/dbtools.conf"
echo n | run >$T/out 2>&1
ok "DDEV_DUMP_DIR gesetzt: Dump landet dort" "ls $T/ddev-dumps/meinprojekt-ddev-*.sql.gz >/dev/null 2>&1 && [ ! -e $D ]"
echo 'DDEV_DUMP_DIR="ddev-rel"' > "$T/tools/dbtools.conf"
reset; echo n | run >/dev/null 2>&1
ok "relativer DDEV_DUMP_DIR relativ zum Skript-Ordner" "ls $T/tools/ddev-rel/meinprojekt-ddev-*.sql.gz >/dev/null 2>&1"
rm -rf "$T/tools/dbtools.conf" "$T/tools/ddev-rel"

# --- alternativer Ordner als 2. Parameter ---
reset; echo n | run "$T/ddev-dumps/" >/dev/null 2>&1
ok "2. Parameter absolut: Dump dort" "ls $T/ddev-dumps/meinprojekt-ddev-*.sql.gz >/dev/null 2>&1 && [ ! -e $D ]"
reset; echo n | run rel >/dev/null 2>&1
ok "2. Parameter relativ zum aktuellen Ordner" "ls $T/elsewhere/rel/meinprojekt-ddev-*.sql.gz >/dev/null 2>&1"

# --- Verschluesselung ---
reset; printf 'y\ngeheim\ngeheim\n' | run >$T/out 2>&1; rc=$?
F=$(ls $D/meinprojekt-ddev-*.sql.gz.gpg 2>/dev/null)
ok "ddev verschluesselt: .sql.gz.gpg, entschluesselbar" "[ $rc -eq 0 ] && [ -n \"$F\" ] && printf geheim | gpg --batch -q --pinentry-mode loopback --passphrase-fd 0 -d $F 2>/dev/null | gunzip | grep -q 'CREATE TABLE ddev_t'"
ok "ddev verschluesselt: Befehl mit gpg angezeigt, Passwort nicht in Ausgabe" "grep -q '^Befehl: ddev export-db --gzip | gpg --symmetric' $T/out && ! grep -q geheim $T/out"

# --- --dry-run ---
reset; echo n | run --dry-run >$T/out 2>&1; rc=$?
ok "--dry-run: nur Befehl, nichts ausgefuehrt" "[ $rc -eq 0 ] && grep -q \"^mkdir -p '$D' && ddev export-db --gzip > '$D/meinprojekt-ddev-\" $T/out && [ ! -e $D ] && [ \"\$(cat $T/ddev-args)\" = 'describe -j' ]"
reset; mkdir -p "$T/ddev-dumps"; echo y | run --dry-run "$T/ddev-dumps" >$T/out 2>&1
ok "--dry-run verschluesselt: gpg-Befehl, kein mkdir bei vorhandenem Ordner, keine Passwortabfrage" "grep -q \"^ddev export-db --gzip | gpg --symmetric --cipher-algo AES256 --compress-algo none -o '$T/ddev-dumps/meinprojekt-ddev-.*\.sql\.gz\.gpg'$\" $T/out && ! grep -q Passwort $T/out && [ -z \"\$(ls $T/ddev-dumps)\" ]"
ok "--dry-run: angezeigter Befehl ist ausfuehrbar" "( cd $T/elsewhere && eval \"\$(tail -n 1 $T/out | sed 's/| gpg.*/> x.sql.gz/')\" ) && gunzip -c $T/elsewhere/x.sql.gz | grep -q ddev_t"
rm -f $T/elsewhere/x.sql.gz

# --- Fehlerfaelle ---
reset; echo n | STUB_DDEV_NAME= run >$T/out 2>&1; rc=$?
ok "kein DDEV-Projekt: Abbruch vor der Verschluesselungsfrage" "[ $rc -ne 0 ] && grep -q 'kein DDEV-Projekt' $T/out && ! grep -q 'verschlüsseln' $T/out && [ ! -e $D ]"
reset; echo n | STUB_DDEV_FAIL=1 run >$T/out 2>&1; rc=$?
ok "ddev export-db scheitert: Exit 1, Datei geloescht" "[ $rc -eq 1 ] && [ -z \"\$(ls $D 2>/dev/null)\" ] && ! grep -q 'Erfolgreich' $T/out"
touch "$T/tools/db_ddev.conf"
reset; echo n | run >$T/out 2>&1; rc=$?
ok "db_ddev.conf vorhanden: Abbruch" "[ $rc -ne 0 ] && grep -q \"'ddev' ist ein reservierter Name\" $T/out && [ ! -e $D ]"
rm "$T/tools/db_ddev.conf"
reset; ( cd "$T/elsewhere" && echo n | "$T/tools/exportDB.sh" test --dry-run ) >$T/out 2>&1; rc=$?
ok "--dry-run bei normaler Umgebung: Fehler" "[ $rc -ne 0 ] && grep -q 'nur bei ddev' $T/out"
reset; ( cd "$T/elsewhere" && echo n | "$T/tools/exportDB.sh" ddev --foo ) >$T/out 2>&1; rc=$?
ok "unbekannte Option: Fehler" "[ $rc -ne 0 ] && grep -q 'Unbekannte Option' $T/out"
rm -rf "$T"; exit $PASSFAIL
