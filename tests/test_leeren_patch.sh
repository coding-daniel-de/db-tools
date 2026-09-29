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
# --- --patch mit .sql.gz, .gpg und Dump-Hinweis ---
reset; printf 'y\n' | imp test p.sql.gz --patch >$T/out 2>&1; rc=$?
ok "--patch mit .sql.gz: entpackt angezeigt und ausgefuehrt" "[ $rc -eq 0 ] && grep -q '(1 Zeilen)' $T/out && grep -qx 'UPDATE pages SET title = 1;' $T/out && [ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE pages SET title = 1;' ]"
cp $T/elsewhere/p.sql.gz $T/elsewhere/getarnt.sql
reset; printf 'y\n' | imp test getarnt.sql --patch >$T/out 2>&1; rc=$?
ok "--patch: gzip-Inhalt mit Endung .sql wird entpackt angezeigt und ausgefuehrt" "[ $rc -eq 0 ] && grep -qx 'UPDATE pages SET title = 1;' $T/out && [ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE pages SET title = 1;' ]"
mk_gpg_at $T/elsewhere/p.sql.gz.gpg 'UPDATE pages SET title = 1;\n'
reset; printf 'geheim\ny\n' | imp test p.sql.gz.gpg --patch >$T/out 2>&1; rc=$?
ok "--patch mit .sql.gz.gpg: Abbruch mit Hinweis auf decryptDB.sh, keine Passwortabfrage" "[ $rc -ne 0 ] && grep -q 'decryptDB.sh' $T/out && [ ! -e $T/mysql-in.sql ] && ! grep -qi 'passwort' $T/out"
reset; printf '1\ny\n' | imp test other --patch >$T/out 2>&1; rc=$?
ok "--patch mit Quell-Umgebung: Abbruch" "[ $rc -ne 0 ] && grep -q -- '--patch braucht' $T/out && [ ! -e $T/mysql-in.sql ]"
rm -f $T/elsewhere/p.sql.gz; reset; printf 'geheim\n' | imp decrypt p.sql.gz.gpg --patch >$T/out 2>&1; rc=$?
ok "--patch bei decrypt: Abbruch" "[ $rc -ne 0 ] && grep -q 'nur beim Import' $T/out && [ ! -e $T/elsewhere/p.sql.gz ]"
for KOPF in '-- MariaDB dump 10.19  Distrib 10.11.6-MariaDB' '-- MySQL dump 10.13  Distrib 8.0.36'; do
    printf -- '/*M!999999\\- enable the sandbox mode */\n%s\n--\nDROP TABLE IF EXISTS `tt_content`;\n' "$KOPF" > $T/elsewhere/einzeltabelle.sql
    reset; printf 'y\n' | imp test einzeltabelle.sql --patch >$T/out 2>&1; rc=$?
    ok "--patch mit mysqldump-Datei ($(echo "$KOPF" | cut -d" " -f2)): Hinweis, aber ausgefuehrt" "[ $rc -eq 0 ] && grep -q 'ist ein mysqldump' $T/out && grep -q 'nur die darin enthaltenen Tabellen' $T/out && grep -q 'DROP TABLE' $T/mysql-in.sql"
done
reset; printf 'y\n' | imp test p.sql --patch >$T/out 2>&1
ok "--patch mit normaler Datei: kein Dump-Hinweis" "! grep -q 'mysqldump' $T/out"

# --- --patch mit Liste aus dem Patch-Ordner ---
P="$T/sql-patches"
reset; printf '1\ny\n' | imp test list --patch >$T/out 2>&1; rc=$?
ok "list --patch ohne Patch-Ordner: Abbruch mit Meldung" "[ $rc -ne 0 ] && grep -q \"Keine Patch-Dateien in '.*sql-patches'\" $T/out && [ ! -e $T/mysql-in.sql ]"
mkdir -p $P
reset; printf '1\ny\n' | imp test list --patch >$T/out 2>&1; rc=$?
ok "list --patch mit leerem Patch-Ordner: Abbruch mit Meldung" "[ $rc -ne 0 ] && grep -q 'Keine Patch-Dateien' $T/out"
printf 'UPDATE alt SET a = 1;\n' > $P/01_alt.sql
sleep 1.1; printf 'UPDATE gz SET a = 1;\n' | gzip > $P/02_gz.sql.gz
mk_gpg_at $P/03_geheim.sql.gz.gpg 'UPDATE geheim SET a = 1;\n'
sleep 1.1; printf 'UPDATE neu SET a = 1;\n' > $P/04_neu.sql
touch $P/notiz.txt
reset; printf '2\ny\n' | imp test list --patch >$T/out 2>&1; rc=$?
ok "list --patch: zeigt .sql und .sql.gz aus dem Patch-Ordner, neueste zuerst" "grep -q 'Verfügbare Patch-Dateien in' $T/out && grep -q '1) 04_neu.sql\$' $T/out && grep -q '2) 02_gz.sql.gz\$' $T/out && grep -q '3) 01_alt.sql\$' $T/out"
ok "list --patch: keine .gpg, keine Dumps, keine anderen Dateien" "! grep -q '03_geheim' $T/out && ! grep -q 'proj-test' $T/out && ! grep -q 'notiz' $T/out"
ok "list --patch: Auswahl 2 fuehrt den entpackten Inhalt aus" "[ $rc -eq 0 ] && [ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE gz SET a = 1;' ]"
reset; printf '1\ny\n' | imp test --patch >$T/out 2>&1
ok "--patch ohne 2. Parameter: zeigt die Patch-Liste" "grep -q 'Verfügbare Patch-Dateien' $T/out && [ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE neu SET a = 1;' ]"
mkdir -p $P/ordner.sql; touch $P/ordner.sql/drin.sql
reset; printf '1\ny\n' | imp test list --patch >$T/out 2>&1
ok "list --patch: Unterordner mit .sql-Endung wird weder aufgeklappt noch angeboten" "! grep -q 'drin.sql' $T/out && ! grep -q 'ordner.sql' $T/out"
rm -rf $P/ordner.sql
reset; printf '9\n' | imp test list --patch >$T/out 2>&1; rc=$?
ok "list --patch: ungueltige Nummer bricht ab" "[ $rc -ne 0 ] && [ ! -e $T/mysql-in.sql ]"
mkdir -p $T/eigene-patches; printf 'UPDATE eigen SET a = 1;\n' > $T/eigene-patches/x.sql
printf 'PATCH_DIR="../eigene-patches"\n' > $T/tools/dbtools.conf
reset; printf '1\ny\n' | imp test list --patch >$T/out 2>&1
ok "PATCH_DIR aus dbtools.conf, relativ zum Skript-Ordner" "grep -q '1) x.sql\$' $T/out && [ \"\$(cat $T/mysql-in.sql)\" = 'UPDATE eigen SET a = 1;' ]"
rm $T/tools/dbtools.conf
reset; printf '1\ny\n' | imp test list >$T/out 2>&1
ok "list ohne --patch: weiterhin Dump-Liste" "grep -q 'Verfügbare Dumps' $T/out && ! grep -q '04_neu' $T/out"

# --- DDEV ---
reset; printf '1\ny\n' | imp ddev list --patch >$T/out 2>&1; rc=$?
ok "ddev list --patch: Patch-Liste, import-db --no-drop" "[ $rc -eq 0 ] && grep -q 'Verfügbare Patch-Dateien' $T/out && [ \"\$(cat $T/ddev-args)\" = 'import-db --no-drop' ] && [ \"\$(cat $T/ddev-in.sql)\" = 'UPDATE neu SET a = 1;' ]"
reset; printf 'y\n' | imp ddev p.sql --patch >$T/out 2>&1; rc=$?
ok "ddev --patch: import-db --no-drop, kein DROP" "[ $rc -eq 0 ] && [ \"\$(cat $T/ddev-args)\" = 'import-db --no-drop' ] && ! grep -q DROP $T/ddev-in.sql && grep -q 'AUSGEFÜHRT' $T/out"
reset; printf 'y\n' | imp ddev test >$T/out 2>&1
ok "ddev voll: import-db ohne --no-drop, keine eigenen DROPs, mysql nicht aufgerufen" "[ \"\$(cat $T/ddev-args)\" = 'import-db' ] && ! grep -q DROP $T/ddev-in.sql && grep -q 'GELEERT' $T/out && [ ! -e $T/mysql-in.sql ]"
rm -rf "$T"; exit $PASSFAIL
