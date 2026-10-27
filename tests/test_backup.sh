source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
B="$T/backups"
conf() { printf 'BACKUP_ENVS="%s"\nBACKUP_DIR="%s"\n' "$1" "$2" > "$T/tools/dbtools.conf"; }
run() { ( cd "$T/elsewhere" && "$T/tools/backupAll.sh" </dev/null >"$T/stdout" 2>"$T/stderr" ); }

# --- exportDB.sh --no-encrypt / --out ---
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test --no-encrypt --out "$T/o1" </dev/null >"$T/out" 2>&1 ); rc=$?
ok "--no-encrypt --out: keine Rueckfrage, unverschluesselter Dump im Zielordner" "[ $rc -eq 0 ] && ls $T/o1/proj-test-*.sql.gz >/dev/null 2>&1 && ! grep -q verschl $T/out"
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test --no-encrypt --out rel </dev/null >/dev/null 2>&1 )
ok "--out relativ zum aktuellen Ordner" "ls $T/elsewhere/rel/proj-test-*.sql.gz >/dev/null 2>&1"
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test --out >"$T/out" 2>&1 ); rc=$?
ok "--out ohne Wert: Fehler" "[ $rc -ne 0 ] && grep -q 'Fehler' $T/out"

# --- Erfolg: alle Umgebungen, still, Exit 0 ---
conf "test other" "$B"; run; rc=$?
ok "Erfolg: Exit 0, beide Dumps in BACKUP_DIR" "[ $rc -eq 0 ] && ls $B/proj-test-*.sql.gz >/dev/null 2>&1 && ls $B/proj-other-*.sql.gz >/dev/null 2>&1"
ok "Erfolg: keine Ausgabe auf stdout/stderr" "[ ! -s $T/stdout ] && [ ! -s $T/stderr ]"
ok "Erfolg: nichts im DUMP_DIR" "[ ! -e $T/sql-dumps ]"
rm -rf "$B"

# --- ein Export schlaegt fehl, die anderen laufen weiter ---
conf "other test" "$B"; STUB_DUMP_FAIL_DB=n2 run; rc=$?
ok "Teilfehler: Exit 1, andere Umgebung trotzdem gesichert" "[ $rc -eq 1 ] && ls $B/proj-test-*.sql.gz >/dev/null 2>&1 && ! ls $B/proj-other-* >/dev/null 2>&1"
ok "Teilfehler: stderr nennt 1 von 2 und die Umgebung, stdout leer" "grep -q '1 von 2' $T/stderr && grep -q 'other' $T/stderr && [ ! -s $T/stdout ]"
rm -rf "$B"

# --- unbekannte Umgebung zaehlt als Fehler ---
conf "gibtsnicht test" "$B"; run; rc=$?
ok "unbekannte Umgebung: Exit 1, Rest wird gesichert, Meldung" "[ $rc -eq 1 ] && ls $B/proj-test-*.sql.gz >/dev/null 2>&1 && grep -q 'gibtsnicht' $T/stderr"
rm -rf "$B"

# --- alles schlaegt fehl ---
conf "test other" "$B"; STUB_DUMP_FAIL=1 run; rc=$?
ok "alles fehlgeschlagen: Exit 1, '2 von 2'" "[ $rc -eq 1 ] && grep -q '2 von 2' $T/stderr"
rm -rf "$B"

# --- BACKUP_DIR relativ zum Skript-Ordner, Fallback auf DUMP_DIR ---
conf "test" "bk-rel"; run
ok "relatives BACKUP_DIR relativ zum Skript-Ordner" "ls $T/tools/bk-rel/proj-test-*.sql.gz >/dev/null 2>&1"
rm -rf "$T/tools/bk-rel"
printf 'BACKUP_ENVS="test"\n' > "$T/tools/dbtools.conf"; run; rc=$?
ok "ohne BACKUP_DIR: Fallback auf DUMP_DIR" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-test-*.sql.gz >/dev/null 2>&1"

# --- keine Umgebungen konfiguriert ---
rm -f "$T/tools/dbtools.conf"; run; rc=$?
ok "ohne BACKUP_ENVS: Exit 1 mit Fehlermeldung" "[ $rc -eq 1 ] && grep -q 'BACKUP_ENVS' $T/stderr"
rm -rf "$T"; exit $PASSFAIL
