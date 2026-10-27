source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"; DD="$T/ddev-dumps"; mkdir -p "$D" "$DD"
CONTENT='-- x\nCREATE TABLE %s (id int);\n'
mk_plain() { printf -- "$CONTENT" "$2" | gzip > "$1/$3"; }
mk_gpg() { printf -- "$CONTENT" "$2" | gzip | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c --cipher-algo AES256 -o "$1/$3"; }
imp() { ( cd "$T/elsewhere" && "$T/tools/importDB.sh" "$@" ); }
reset() { rm -f "$T/mysql-in.sql" "$T/ddev-in.sql" "$T/ddev-args" "$T/out"; }

# Aeltester zuerst anlegen, Dateien mit Abstand, damit die Sortierung nach Datum eindeutig ist
mk_plain "$D" alt_test proj-test-2026-01-01-10Uhr.sql.gz; sleep 1.1
mk_gpg "$D" gpg_test proj-test-2026-01-02-10Uhr.sql.gz.gpg; sleep 1.1
mk_plain "$D" neu_test proj-test-2026-01-03-10Uhr.sql.gz; sleep 1.1
mk_plain "$D" andere proj-other-2026-01-04-10Uhr.sql.gz

# --- (y/N/l) bei gleichem Ordner ---
reset; printf 'l\n1\ny\n' | imp test >$T/out 2>&1
ok "automatisch gewaehlt: l wird angenommen (Liste erscheint)" "grep -q 'Verfügbare' $T/out && grep -q 'neu_test' $T/mysql-in.sql"
reset; printf 'l\n1\ny\n' | imp test $D/proj-test-2026-01-01-10Uhr.sql.gz >$T/out 2>&1
ok "direkte Datei: kein l, wird als Abbruch gewertet" "! grep -q 'Verfügbare' $T/out && grep -q 'abgebrochen' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf '1\nl\n1\ny\n' | imp test list >$T/out 2>&1
ok "list: kein l, wird als Abbruch gewertet" "[ ! -e $T/mysql-in.sql ] && [ \"\$(grep -c Verfügbare $T/out)\" = 1 ]"

reset; printf 'l\n3\ny\n' | imp test >$T/out 2>&1
ok "l: Liste gefiltert auf PREFIX, kein Label bei einem Ordner" "grep -q '1) proj-test-2026-01-03' $T/out && grep -q '3) proj-test-2026-01-01' $T/out && ! grep -q 'proj-other' $T/out && ! grep -q '\[sql-dumps\]' $T/out"
ok "l: Wechsel auf unverschluesselten Dump, erneute Abfrage mit neuem Namen" "grep -q 'alt_test' $T/mysql-in.sql && [ \"\$(grep -c '^ACHTUNG' $T/out)\" = 2 ] && grep -q \"proj-test-2026-01-01-10Uhr.sql.gz' befüllt\" $T/out"

reset; printf 'l\n2\ngeheim\ny\n' | imp test >$T/out 2>&1
ok "l: Wechsel auf verschluesselten Dump mit Passwortpruefung" "grep -q 'gpg_test' $T/mysql-in.sql"
reset; printf 'l\n2\nfalsch\ny\n' | imp test >$T/out 2>&1; rc=$?
ok "l: falsches Passwort: Abbruch, DB unberuehrt" "[ $rc -ne 0 ] && grep -q 'Falsches Passwort' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf 'l\n1\nn\n' | imp test >$T/out 2>&1; rc=$?
ok "l, dann N: Abbruch ohne Import, Exit 0" "[ $rc -eq 0 ] && grep -q 'abgebrochen' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf 'l\n9\ny\n' | imp test >$T/out 2>&1; rc=$?
ok "l: ungueltige Nummer bricht ab" "[ $rc -ne 0 ] && [ ! -e $T/mysql-in.sql ]"
reset; printf 'l\n2\ngeheim\nl\n3\ny\n' | imp test >$T/out 2>&1
ok "l zweimal: vom verschluesselten wieder auf unverschluesselt, Eingabereihenfolge zeigt: nur eine Passwortabfrage" "grep -q 'alt_test' $T/mysql-in.sql"
reset; printf 'L\n3\ny\n' | imp test >$T/out 2>&1
ok "grosses L geht auch" "grep -q 'alt_test' $T/mysql-in.sql"
reset; printf 'l\n3\ny\n' | imp update test >$T/out 2>&1 || true
reset; printf 'l\n1\ny\n' | imp test other >$T/out 2>&1
ok "Quell-Umgebung: l filtert auf deren PREFIX" "grep -q 'proj-other' $T/out && ! grep -q 'proj-test' $T/out && grep -q 'andere' $T/mysql-in.sql"

# --- getrennte Ordner bei ddev ---
printf 'DUMP_DIR="%s"\nDDEV_DUMP_DIR="%s"\n' "$D" "$DD" > "$T/tools/dbtools.conf"
sleep 1.1; mk_plain "$DD" ddevneu meinprojekt-ddev-2026-01-05-10Uhr.sql.gz
reset; printf '1\ny\n' | imp ddev list >$T/out 2>&1
ok "ddev list: gemeinsame Liste, Pfade beider Ordner, Labels, neuester zuerst" "grep -q \"$DD\" $T/out && grep -q \"  $D\" $T/out && grep -q '1) meinprojekt-ddev-2026-01-05-10Uhr.sql.gz *\[ddev-dumps\]' $T/out && grep -q 'proj-other-2026-01-04-10Uhr.sql.gz *\[sql-dumps\]' $T/out && grep -q 'ddevneu' $T/ddev-in.sql"
ok "ddev list: Ordner-Reihenfolge DDEV_DUMP_DIR zuerst" "[ \$(grep -n \"  $DD\" $T/out | head -1 | cut -d: -f1) -lt \$(grep -n \"  $D\$\" $T/out | head -1 | cut -d: -f1) ]"
reset; printf 'y\n' | imp ddev other >$T/out 2>&1
ok "ddev mit Quell-Umgebung findet Stage-Dump aus dem anderen Ordner" "grep -q 'Verwende Dump: $D/proj-other' $T/out && grep -q andere $T/ddev-in.sql"
sleep 1.1; mk_plain "$DD" neuerer proj-other-2026-01-09-10Uhr.sql.gz
reset; printf 'y\n' | imp ddev other >$T/out 2>&1
ok "neuester ueber beide Ordner hinweg" "grep -q 'Verwende Dump: $DD/proj-other-2026-01-09' $T/out && grep -q neuerer $T/ddev-in.sql"
reset; printf 'l\n2\ny\n' | imp ddev other >$T/out 2>&1
ok "ddev l: gefilterte Liste aus beiden Ordnern mit Label, Wechsel in den anderen Ordner" "grep -q 'proj-other-2026-01-09.*\[ddev-dumps\]' $T/out && grep -q 'proj-other-2026-01-04.*\[sql-dumps\]' $T/out && ! grep -q 'proj-test' $T/out && grep -q andere $T/ddev-in.sql"
reset; printf 'y\n' | imp test >$T/out 2>&1
ok "normales Ziel sieht die DDEV-Dumps nicht" "! grep -q 'meinprojekt' $T/out"
reset; printf '1\ny\n' | imp test list >$T/out 2>&1
ok "normales Ziel list: nur ein Ordner, kein Label" "! grep -q 'meinprojekt' $T/out && ! grep -q '\[sql-dumps\]' $T/out"

# --- gleicher Ordner (explizit gesetzt, einmal mit Slash und Umweg): keine Dubletten ---
printf 'DUMP_DIR="%s"\nDDEV_DUMP_DIR="%s/../sql-dumps/"\n' "$D" "$D" > "$T/tools/dbtools.conf"
reset; printf '1\ny\n' | imp ddev list >$T/out 2>&1
ok "ddev, gleicher Ordner: einmal gesucht, kein Label, keine Dubletten" "[ \"\$(grep -c '^  [0-9])' $T/out)\" = 4 ] && ! grep -q '\[sql-dumps\]' $T/out && grep -q \"Verfügbare Dumps in '$D'\" $T/out"

# --- gleicher Ordnername in verschiedenen Pfaden: Label = voller Pfad ---
mkdir -p "$T/a/dumps" "$T/b/dumps"
mk_plain "$T/a/dumps" ax x-ddev-2026-01-01-10Uhr.sql.gz; mk_plain "$T/b/dumps" bx y-2026-01-01-10Uhr.sql.gz
printf 'DUMP_DIR="%s"\nDDEV_DUMP_DIR="%s"\n' "$T/b/dumps" "$T/a/dumps" > "$T/tools/dbtools.conf"
reset; printf '1\ny\n' | imp ddev list >$T/out 2>&1
ok "gleicher Ordnername: voller Pfad als Label" "grep -q \"x-ddev-2026-01-01-10Uhr.sql.gz *\[$T/a/dumps\]\" $T/out && grep -q \"y-2026-01-01-10Uhr.sql.gz *\[$T/b/dumps\]\" $T/out"

# --- --patch list nutzt weiter den Patch-Ordner ---
mkdir -p "$T/sql-patches"; printf 'SELECT 1;\n' > "$T/sql-patches/p1.sql"
reset; printf '1\ny\n' | imp ddev list --patch >$T/out 2>&1
ok "--patch list: nur Patch-Ordner, kein Label, (y/N)" "grep -q 'p1.sql' $T/out && ! grep -q 'proj-' $T/out"

[ -n "$KEEP" ] && echo "T=$T" || rm -rf "$T"; exit $PASSFAIL
