source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"; mkdir -p $D
mk_plain() { printf -- '-- x\nCREATE TABLE t (id int);\n' | gzip > "$D/$1"; }
mk_gpg() { printf -- '-- x\nCREATE TABLE t (id int);\n' | gzip | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c --cipher-algo AES256 -o "$D/$1"; }
imp() { ( cd "$T/elsewhere" && "$T/tools/importDB.sh" "$@" ); }
reset() { rm -f "$T/mysql-in.sql" "$T/out"; }

# Suche: neuester gewinnt, auch wenn verschluesselt
mk_plain proj-test-2026-01-01-10Uhr.sql.gz; sleep 1.1; mk_gpg proj-test-2026-01-02-10Uhr.sql.gz.gpg
reset; printf 'geheim\ny\n' | imp test >$T/out 2>&1
ok "neuester (gpg) gewinnt, Import ok" "grep -q 'Verwende Dump: .*\.gpg' $T/out && grep -q 'CREATE TABLE' $T/mysql-in.sql && grep -q 'Erfolgreich importiert' $T/out"
sleep 1.1; mk_plain proj-test-2026-01-03-10Uhr.sql.gz
reset; printf 'y\n' | imp test >$T/out 2>&1
ok "neuester (plain) gewinnt, ohne Passwortabfrage" "grep -q 'Verwende Dump: .*10Uhr.sql.gz\$' $T/out && ! grep -qi 'passwort' $T/out && grep -q 'CREATE TABLE' $T/mysql-in.sql"
# Quell-Umgebung
mk_gpg proj-other-2026-02-01-10Uhr.sql.gz.gpg
reset; printf 'geheim\ny\n' | imp test other >$T/out 2>&1
ok "Quell-Umgebung findet .gpg" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
# falsches Passwort: Abbruch vor Sicherheitsabfrage, DB unberuehrt
reset; printf 'falsch\ny\n' | imp test other >$T/out 2>&1; rc=$?
ok "falsches Passwort: Exit !=0, keine Sicherheitsabfrage, mysql nicht aufgerufen" "[ $rc -ne 0 ] && ! grep -q 'absolut sicher' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf '\ny\n' | imp test other >$T/out 2>&1; rc=$?
ok "leeres Passwort: Abbruch" "[ $rc -ne 0 ] && [ ! -e $T/mysql-in.sql ]"
# Passwort richtig, N bei Sicherheitsabfrage
reset; printf 'geheim\nn\n' | imp test other >$T/out 2>&1
ok "richtiges Passwort, N: kein Import" "grep -q 'abgebrochen' $T/out && [ ! -e $T/mysql-in.sql ]"
# explizite Datei
cp $D/proj-other-2026-02-01-10Uhr.sql.gz.gpg $T/elsewhere/x.sql.gz.gpg
reset; printf 'geheim\ny\n' | imp test x.sql.gz.gpg >$T/out 2>&1
ok "explizite .sql.gz.gpg Datei" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
# .sql plain
printf 'CREATE TABLE plain (id int);\n' > $T/elsewhere/p.sql
reset; printf 'y\n' | imp test p.sql >$T/out 2>&1
ok ".sql direkt" "grep -q 'CREATE TABLE plain' $T/mysql-in.sql"
# list zeigt alle drei Endungen, sortiert, waehlt gpg
printf 'x' > $D/z.sql; sleep 1.1; mk_gpg newest.sql.gz.gpg
reset; printf '1\ngeheim\ny\n' | imp test list >$T/out 2>&1
ok "list: neuester (gpg) = 1, alle Endungen gelistet" "grep -q '1) newest.sql.gz.gpg' $T/out && grep -q 'z.sql\$' $T/out && grep -q 'proj-test-2026-01-03-10Uhr.sql.gz\$' $T/out && grep -q 'CREATE TABLE' $T/mysql-in.sql"
reset; printf '99\n' | imp test list >$T/out 2>&1; rc=$?
ok "list: ungueltige Nummer bricht ab" "[ $rc -ne 0 ] && [ ! -e $T/mysql-in.sql ]"
# mysql-Fehler / gzip-Fehler duerfen nicht als Erfolg durchgehen
reset; printf 'geheim\ny\n' | STUB_MYSQL_FAIL=1 imp test other >$T/out 2>&1
ok "mysql-Fehler: keine Erfolgsmeldung" "! grep -q 'Erfolgreich importiert' $T/out && grep -q 'Fehler: Beim Import' $T/out"
# defekter Inhalt hinter richtigem Passwort (kein gzip in der Huelle) wird vor Import abgelehnt
printf 'kein gzip\n' | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c -o $D/bad.sql.gz.gpg
reset; printf 'geheim\ny\n' | imp test $D/bad.sql.gz.gpg >$T/out 2>&1; rc=$?
ok "kein gzip in Huelle: Abbruch vor Import" "[ $rc -ne 0 ] && [ ! -e $T/mysql-in.sql ]"
# abgeschnittene gzip-Datei im gpg: gunzip-Fehler wird erkannt
printf -- 'CREATE TABLE t (id int);\n' | gzip | head -c 20 | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c -o $D/trunc.sql.gz.gpg
reset; printf 'geheim\ny\n' | imp test $D/trunc.sql.gz.gpg >$T/out 2>&1
ok "abgeschnittener gzip-Inhalt: kein Erfolg gemeldet" "! grep -q 'Erfolgreich importiert' $T/out"
ok "Passwort nicht in Ausgabe" "! grep -q 'geheim' $T/out"
rm -rf "$T"; exit $PASSFAIL
