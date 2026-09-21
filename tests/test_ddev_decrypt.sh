source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"; mkdir -p $D
CONTENT='-- x\nCREATE TABLE t (id int);\n'
mk_plain() { printf -- "$CONTENT" | gzip > "$D/$1"; }
mk_gpg() { printf -- "$CONTENT" | gzip | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c --cipher-algo AES256 -o "$D/$1"; }
imp() { ( cd "$T/elsewhere" && "$T/tools/importDB.sh" "$@" ); }
reset() { rm -f "$T/mysql-in.sql" "$T/ddev-in.sql" "$T/ddev-args" "$T/out"; }

mk_plain proj-test-2026-01-01-10Uhr.sql.gz
mk_gpg proj-other-2026-02-01-10Uhr.sql.gz.gpg

# --- ddev als reservierter Ziel-Name ---
touch "$T/tools/db_ddev.conf"
reset; printf 'y\n' | imp ddev test >$T/out 2>&1; rc=$?
ok "db_ddev.conf vorhanden: Abbruch mit Meldung, nichts importiert" "[ $rc -ne 0 ] && grep -q \"'ddev' ist ein reservierter Name\" $T/out && grep -q 'db_ddev.conf' $T/out && [ ! -e $T/ddev-in.sql ] && [ ! -e $T/mysql-in.sql ]"
rm "$T/tools/db_ddev.conf"

reset; printf 'y\n' | imp ddev test >$T/out 2>&1; rc=$?
ok "ddev mit Quell-Umgebung (gz): Import ueber ddev import-db" "[ $rc -eq 0 ] && grep -q 'CREATE TABLE' $T/ddev-in.sql && [ \"\$(cat $T/ddev-args)\" = 'import-db' ] && [ ! -e $T/mysql-in.sql ] && grep -q 'Erfolgreich importiert' $T/out"
ok "ddev: Sicherheitsabfrage nennt das DDEV-Projekt im aktuellen Ordner" "grep -q 'DDEV' $T/out && grep -q \"$T/elsewhere\" $T/out"

reset; printf 'geheim\ny\n' | imp ddev other >$T/out 2>&1; rc=$?
ok "ddev mit .gpg: entschluesselt und entpackt in den Import" "[ $rc -eq 0 ] && grep -q 'CREATE TABLE' $T/ddev-in.sql"
reset; printf 'falsch\ny\n' | imp ddev other >$T/out 2>&1; rc=$?
ok "ddev mit falschem Passwort: Abbruch, ddev nicht aufgerufen" "[ $rc -ne 0 ] && ! grep -q 'absolut sicher' $T/out && [ ! -e $T/ddev-in.sql ]"
reset; printf 'geheim\nn\n' | imp ddev other >$T/out 2>&1; rc=$?
ok "ddev, N bei Sicherheitsabfrage: kein Import, Exit 0" "[ $rc -eq 0 ] && grep -q 'abgebrochen' $T/out && [ ! -e $T/ddev-in.sql ]"

printf 'CREATE TABLE plain (id int);\n' > $T/elsewhere/p.sql
reset; printf 'y\n' | imp ddev p.sql >$T/out 2>&1
ok "ddev mit .sql: Datei per stdin" "grep -q 'CREATE TABLE plain' $T/ddev-in.sql"

reset; printf 'y\n' | imp ddev $D/proj-test-2026-01-01-10Uhr.sql.gz >$T/out 2>&1
ok "ddev mit Dateipfad (gz)" "grep -q 'CREATE TABLE' $T/ddev-in.sql"

reset; printf '1\ngeheim\ny\n' | imp ddev >$T/out 2>&1
ok "ddev ohne 2. Parameter: zeigt die Dump-Liste" "grep -q 'Verfügbare Dumps' $T/out && grep -q 'CREATE TABLE' $T/ddev-in.sql"

reset; printf 'y\n' | STUB_DDEV_FAIL=1 imp ddev test >$T/out 2>&1; rc=$?
ok "ddev-Fehler: keine Erfolgsmeldung, Exit 1" "[ $rc -eq 1 ] && ! grep -q 'Erfolgreich importiert' $T/out && grep -q 'Fehler: Beim Import' $T/out"

reset; printf 'y\n' | imp test other >/dev/null 2>&1; printf 'geheim\ny\n' | imp test other >$T/out 2>&1
ok "normaler Import weiterhin ueber mysql" "grep -q 'CREATE TABLE' $T/mysql-in.sql && [ ! -e $T/ddev-in.sql ]"
ok "Passwort nicht in Ausgabe" "! grep -q 'geheim' $T/out"

rm -rf "$T"; exit $PASSFAIL
