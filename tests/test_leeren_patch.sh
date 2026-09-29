source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"; mkdir -p $D
mk_plain() { printf -- '-- x\nCREATE TABLE t (id int);\n' | gzip > "$D/$1"; }
mk_gpg_at() { printf -- "$2" | gzip | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c --cipher-algo AES256 -o "$1"; }
imp() { ( cd "$T/elsewhere" && "$T/tools/importDB.sh" "$@" ); }
reset() { rm -f "$T/mysql-in.sql" "$T/mysql-queries" "$T/ddev-in.sql" "$T/ddev-args" "$T/out"; }
mk_plain proj-test-2026-01-01-10Uhr.sql.gz

# --- Voller Import leert die Ziel-DB ---
export STUB_MYSQL_TABLES='BASE TABLE\tpages\nBASE TABLE\talt_ext\nVIEW\tv_pages\nSEQUENCE\tseq1\nBASE TABLE\tmit`backtick'
reset; printf 'y\n' | imp test >$T/out 2>&1; rc=$?
ok "voller Import: Abfrage nennt Anzahl der Tabellen/Views" "[ $rc -eq 0 ] && grep -q 'Alle 5 Tabellen/Views der Datenbank \[ n \]' $T/out && grep -q 'GELÖSCHT' $T/out"
ok "voller Import: alle Objekte werden vor dem Dump geloescht" "grep -q 'DROP TABLE IF EXISTS \`alt_ext\`;' $T/mysql-in.sql && grep -q 'DROP TABLE IF EXISTS \`pages\`;' $T/mysql-in.sql && grep -q 'DROP VIEW IF EXISTS \`v_pages\`;' $T/mysql-in.sql && grep -q 'DROP SEQUENCE IF EXISTS \`seq1\`;' $T/mysql-in.sql"
ok "voller Import: Backtick im Namen wird verdoppelt" "grep -qF 'DROP TABLE IF EXISTS \`mit\`\`backtick\`;' $T/mysql-in.sql"
ok "voller Import: Reihenfolge FK-Checks aus, View vor Tabellen, Dump am Ende" "[ \"\$(sed -n 1p $T/mysql-in.sql)\" = 'SET FOREIGN_KEY_CHECKS=0;' ] && [ \"\$(sed -n 2p $T/mysql-in.sql)\" = 'DROP VIEW IF EXISTS \`v_pages\`;' ] && [ \"\$(tail -n 1 $T/mysql-in.sql)\" = 'CREATE TABLE t (id int);' ]"
reset; printf 'n\n' | imp test >$T/out 2>&1
ok "voller Import, N: nichts geloescht" "grep -q 'abgebrochen' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf 'y\n' | STUB_MYSQL_QUERY_FAIL=1 imp test >$T/out 2>&1; rc=$?
ok "Verbindungsfehler bei der Tabellenabfrage: Abbruch vor der Sicherheitsabfrage" "[ $rc -ne 0 ] && ! grep -q 'absolut sicher' $T/out && grep -q 'nicht angefasst' $T/out && [ ! -e $T/mysql-in.sql ]"
# Liste wird nach der Bestaetigung neu geholt: inzwischen entstandene Tabellen werden mit geloescht
reset; printf 'y\n' | STUB_MYSQL_TABLES_LATER='BASE TABLE\tpages\nBASE TABLE\tneu' imp test >$T/out 2>&1; rc=$?
ok "Liste nach dem y neu geholt: neue Tabelle wird geloescht" "[ $rc -eq 0 ] && grep -q 'Alle 5 Tabellen/Views' $T/out && grep -q 'DROP TABLE IF EXISTS \`neu\`;' $T/mysql-in.sql && ! grep -q 'alt_ext' $T/mysql-in.sql"
reset; printf 'y\n' | STUB_MYSQL_QUERY_FAIL_AT=2 imp test >$T/out 2>&1; rc=$?
ok "zweite Abfrage schlaegt fehl: Abbruch, nichts geloescht" "[ $rc -ne 0 ] && grep -q 'nicht angefasst' $T/out && [ ! -e $T/mysql-in.sql ]"
unset STUB_MYSQL_TABLES
reset; printf 'y\n' | imp test >$T/out 2>&1
ok "leere Ziel-DB: Hinweis statt Loeschwarnung, kein DROP" "grep -q 'ist leer' $T/out && ! grep -q DROP $T/mysql-in.sql && grep -q 'CREATE TABLE' $T/mysql-in.sql"
mk_gpg_at $D/x.sql.gz.gpg 'CREATE TABLE t (id int);\n'
reset; printf 'falsch\ny\n' | imp test $D/x.sql.gz.gpg >$T/out 2>&1; rc=$?
ok "falsches Passwort: nichts geloescht" "[ $rc -ne 0 ] && [ ! -e $T/mysql-in.sql ]"

# --- --patch ---
export STUB_MYSQL_TABLES='BASE TABLE\tpages'
printf 'UPDATE pages SET hidden = 1 WHERE uid = 42;\n' > $T/elsewhere/p.sql
reset; printf 'y\n' | imp test p.sql --patch >$T/out 2>&1; rc=$?
ok "--patch: nur die Befehle der Datei, kein DROP" "[ $rc -eq 0 ] && [ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE pages SET hidden = 1 WHERE uid = 42;' ] && grep -q 'Erfolgreich importiert' $T/out"
ok "--patch: Inhalt vor der Abfrage angezeigt, Warnung sagt AUSGEFÜHRT" "grep -q '^UPDATE pages' $T/out && grep -q 'AUSGEFÜHRT' $T/out && grep -q 'nicht geleert' $T/out && ! grep -q 'GELÖSCHT' $T/out"
reset; printf 'y\n' | imp test --patch p.sql >$T/out 2>&1
ok "--patch an beliebiger Stelle" "[ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE pages SET hidden = 1 WHERE uid = 42;' ]"
reset; printf 'n\n' | imp test p.sql --patch >$T/out 2>&1
ok "--patch, N: nichts ausgefuehrt" "grep -q 'abgebrochen' $T/out && [ ! -e $T/mysql-in.sql ]"
seq 1 50 | sed 's/^/SELECT /; s/$/;/' > $T/elsewhere/lang.sql
reset; printf 'y\n' | imp test lang.sql --patch >$T/out 2>&1
ok "--patch: lange Datei gekuerzt angezeigt, aber komplett ausgefuehrt" "grep -q '(50 Zeilen)' $T/out && grep -q '^SELECT 30;' $T/out && ! grep -q '^SELECT 31;' $T/out && grep -q 'ersten 30 von 50' $T/out && [ \"\$(wc -l < $T/mysql-in.sql)\" = 50 ]"
printf 'UPDATE pages SET bodytext = "%s";\n' "$(printf 'x%.0s' $(seq 1 500))" > $T/elsewhere/breit.sql
reset; printf 'y\n' | imp test breit.sql --patch >$T/out 2>&1
ok "--patch: lange Zeile in der Vorschau nach 200 Zeichen abgeschnitten, aber komplett ausgefuehrt" "grep -qx \"\$(head -c 200 $T/elsewhere/breit.sql)…\" $T/out && [ \"\$(cat $T/mysql-in.sql)\" = \"\$(cat $T/elsewhere/breit.sql)\" ]"
reset; printf 'y\n' | imp test p.sql --patch >$T/out 2>&1
ok "--patch: kurze Zeile ohne Kuerzungszeichen" "grep -qx 'UPDATE pages SET hidden = 1 WHERE uid = 42;' $T/out"
printf 'UPDATE pages SET title = 1;\n' | gzip > $T/elsewhere/p.sql.gz
seq 1 31 | sed 's/^/SELECT /; s/$/;/' | head -c -1 > $T/elsewhere/ohne_umbruch.sql
reset; printf 'y\n' | imp test ohne_umbruch.sql --patch >$T/out 2>&1
ok "--patch: letzte Zeile ohne Umbruch wird mitgezaehlt" "grep -q '(31 Zeilen)' $T/out && grep -q 'ersten 30 von 31' $T/out"
cp $T/elsewhere/p.sql.gz $T/elsewhere/getarnt.sql
reset; printf 'y\n' | imp test getarnt.sql --patch >$T/out 2>&1; rc=$?
ok "--patch: gzip-Inhalt mit Endung .sql wird abgelehnt" "[ $rc -ne 0 ] && grep -q 'nur .sql' $T/out && ! grep -q 'absolut sicher' $T/out && [ ! -e $T/mysql-in.sql ]"
mk_gpg_at $T/elsewhere/p.sql.gz.gpg 'UPDATE pages SET title = 1;\n'
for F in p.sql.gz p.sql.gz.gpg; do
    reset; printf 'geheim\ny\n' | imp test $F --patch >$T/out 2>&1; rc=$?
    ok "--patch mit $F: Abbruch mit Hinweis auf decryptDB.sh --gunzip" "[ $rc -ne 0 ] && grep -q 'nur .sql' $T/out && grep -q 'decryptDB.sh' $T/out && grep -q -- '--gunzip' $T/out && [ ! -e $T/mysql-in.sql ] && ! grep -qi 'passwort' $T/out"
done
for SRC in "" other list; do
    reset; printf '1\ny\n' | imp test $SRC --patch >$T/out 2>&1; rc=$?
    ok "--patch ohne Datei ('${SRC:-leer}'): Abbruch" "[ $rc -ne 0 ] && grep -q -- '--patch braucht' $T/out && [ ! -e $T/mysql-in.sql ]"
done
rm -f $T/elsewhere/p.sql.gz; reset; printf 'geheim\n' | imp decrypt p.sql.gz.gpg --patch >$T/out 2>&1; rc=$?
ok "--patch bei decrypt: Abbruch" "[ $rc -ne 0 ] && grep -q 'nur beim Import' $T/out && [ ! -e $T/elsewhere/p.sql.gz ]"

# --- DDEV ---
reset; printf 'y\n' | imp ddev p.sql --patch >$T/out 2>&1; rc=$?
ok "ddev --patch: import-db --no-drop, kein DROP" "[ $rc -eq 0 ] && [ \"\$(cat $T/ddev-args)\" = 'import-db --no-drop' ] && ! grep -q DROP $T/ddev-in.sql && grep -q 'AUSGEFÜHRT' $T/out"
reset; printf 'y\n' | imp ddev test >$T/out 2>&1
ok "ddev voll: import-db ohne --no-drop, keine eigenen DROPs, mysql nicht aufgerufen" "[ \"\$(cat $T/ddev-args)\" = 'import-db' ] && ! grep -q DROP $T/ddev-in.sql && grep -q 'GELEERT' $T/out && [ ! -e $T/mysql-in.sql ]"
rm -rf "$T"; exit $PASSFAIL
