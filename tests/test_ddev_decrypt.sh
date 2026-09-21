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


# --- decrypt als reservierter Name ---
touch "$T/tools/db_decrypt.conf"
reset; printf 'geheim\n' | imp decrypt other >$T/out 2>&1; rc=$?
ok "db_decrypt.conf vorhanden: Abbruch mit Meldung, nichts erzeugt" "[ $rc -ne 0 ] && grep -q \"'decrypt' ist ein reservierter Name für das Entschlüsseln von Dumps\" $T/out && grep -q 'db_decrypt.conf' $T/out && [ -z \"\$(ls $T/elsewhere/proj-* 2>/dev/null)\" ]"
rm "$T/tools/db_decrypt.conf"

# --- decrypt: Ergebnis im aktuellen Ordner ---
E="$T/elsewhere"
clean() { find "$E" -mindepth 1 -delete; rm -f "$T/out"; }
same() { [ "$(gunzip -c "$1")" = "$(printf -- "$CONTENT")" ]; }

clean; printf 'geheim\n' | imp decrypt other >$T/out 2>&1; rc=$?
ok "decrypt Quell-Umgebung: .gpg entfernt, gz gueltig, Inhalt gleich" "[ $rc -eq 0 ] && gunzip -t $E/proj-other-2026-02-01-10Uhr.sql.gz && same $E/proj-other-2026-02-01-10Uhr.sql.gz"
ok "decrypt ohne --gunzip: Hinweis auf zless/zgrep und Zielpfad" "grep -q 'Entschlüsselt nach: ./proj-other-2026-02-01-10Uhr.sql.gz' $T/out && grep -q 'zless' $T/out && grep -q 'zgrep' $T/out"
ok "decrypt: Ergebnis nur fuer den Besitzer lesbar, keine Reste" "[ \"\$(stat -c %a $E/proj-other-2026-02-01-10Uhr.sql.gz)\" = 600 ] && [ \"\$(ls $E | wc -l)\" = 1 ] && ! ls -A $D | grep -q 'sql\$'"
ok "decrypt ruft weder mysql noch ddev auf, Passwort nicht in Ausgabe" "[ ! -e $T/mysql-in.sql ] && [ ! -e $T/ddev-in.sql ] && ! grep -q geheim $T/out"

clean; printf 'geheim\n' | imp decrypt other --gunzip >$T/out 2>&1; rc=$?
ok "decrypt --gunzip: .sql mit richtigem Inhalt, kein Hinweis" "[ $rc -eq 0 ] && [ \"\$(cat $E/proj-other-2026-02-01-10Uhr.sql)\" = \"\$(printf -- \"$CONTENT\")\" ] && [ ! -e $E/proj-other-2026-02-01-10Uhr.sql.gz ] && ! grep -q zless $T/out"

clean; printf '1\ngeheim\n' | imp decrypt >$T/out 2>&1
ok "decrypt ohne Quelle: zeigt die Liste" "grep -q 'Verfügbare Dumps' $T/out && ls $E/*.sql.gz >/dev/null 2>&1"

clean; cp $D/proj-other-2026-02-01-10Uhr.sql.gz.gpg $E/x.sql.gz.gpg; printf 'geheim\n' | imp decrypt x.sql.gz.gpg >$T/out 2>&1
ok "decrypt mit Dateiname im aktuellen Ordner" "gunzip -t $E/x.sql.gz && [ -e $E/x.sql.gz.gpg ]"
clean; printf 'geheim\n' | imp decrypt $D/proj-other-2026-02-01-10Uhr.sql.gz.gpg >$T/out 2>&1
ok "decrypt mit Dateipfad: Ergebnis im aktuellen Ordner" "gunzip -t $E/proj-other-2026-02-01-10Uhr.sql.gz"

clean; printf 'falsch\n' | imp decrypt other >$T/out 2>&1; rc=$?
ok "decrypt falsches Passwort: Abbruch, keine Datei, keine Reste" "[ $rc -ne 0 ] && grep -q 'Falsches Passwort' $T/out && [ -z \"\$(ls -A $E)\" ]"

# Zieldatei existiert: Rueckfrage vor der Passwortabfrage
clean; echo alt > $E/proj-other-2026-02-01-10Uhr.sql.gz
printf 'n\n' | imp decrypt other >$T/out 2>&1; rc=$?
ok "Zieldatei existiert, N: unveraendert, Exit 0, keine Passwortabfrage" "[ $rc -eq 0 ] && [ \"\$(cat $E/proj-other-2026-02-01-10Uhr.sql.gz)\" = alt ] && ! grep -q 'Passwort für' $T/out"
printf 'y\ngeheim\n' | imp decrypt other >$T/out 2>&1
ok "Zieldatei existiert, y: ueberschrieben" "gunzip -t $E/proj-other-2026-02-01-10Uhr.sql.gz"

# unverschluesselte Dumps
clean; printf 'y\n' | imp decrypt test >$T/out 2>&1; rc=$?
ok "unverschluesselt ohne --gunzip: Fehlermeldung, keine Datei" "[ $rc -ne 0 ] && grep -q 'nicht verschlüsselt, nichts zu tun' $T/out && grep -q -- '--gunzip' $T/out && [ -z \"\$(ls -A $E)\" ]"
clean; imp decrypt test --gunzip >$T/out 2>&1; rc=$?
ok "unverschluesselt mit --gunzip: wird entpackt (ohne Passwortabfrage)" "[ $rc -eq 0 ] && [ \"\$(cat $E/proj-test-2026-01-01-10Uhr.sql)\" = \"\$(printf -- \"$CONTENT\")\" ] && ! grep -q 'Passwort für' $T/out"
clean; printf 'CREATE TABLE plain (id int);\n' > $E/p.sql; imp decrypt p.sql --gunzip >$T/out 2>&1; rc=$?
ok ".sql mit --gunzip: nichts zu tun, Datei unveraendert" "[ $rc -ne 0 ] && grep -q 'nicht komprimiert' $T/out && grep -q 'CREATE TABLE plain' $E/p.sql"
rm -f $E/p.sql

# --- Wrapper decryptDB.sh ---
clean; ( cd $E && printf 'geheim\n' | $T/tools/decryptDB.sh other --gunzip >$T/out 2>&1 )
ok "Wrapper aus fremdem Ordner" "[ -e $E/proj-other-2026-02-01-10Uhr.sql ]"
clean; ln -s $T/tools/decryptDB.sh $T/elsewhere/dd; ( cd $E && printf 'geheim\n' | ./dd other >$T/out 2>&1 ); rc=$?
ok "Wrapper ueber Symlink aufgerufen: Skript-Ordner ueber echten Pfad" "[ $rc -eq 0 ] && [ -e $E/proj-other-2026-02-01-10Uhr.sql.gz ]"
rm -f $E/dd

# --- Optionen ---
clean; reset; printf 'geheim\ny\n' | imp test other --gunzip >$T/out 2>&1; rc=$?
ok "--gunzip beim Import: Hinweis, Import laeuft weiter" "[ $rc -eq 0 ] && grep -q 'Hinweis: --gunzip wird beim Import nicht benötigt' $T/out && grep -q 'CREATE TABLE' $T/mysql-in.sql"
reset; printf 'y\n' | imp --gunzip ddev test >$T/out 2>&1; rc=$?
ok "--gunzip vor den Parametern, ddev: Hinweis, Import laeuft" "[ $rc -eq 0 ] && grep -q 'Hinweis: --gunzip' $T/out && grep -q 'CREATE TABLE' $T/ddev-in.sql"
reset; printf 'y\n' | imp test --foo >$T/out 2>&1; rc=$?
ok "unbekannte Option: Abbruch mit Meldung, nichts importiert" "[ $rc -ne 0 ] && grep -q 'Unbekannte Option' $T/out && grep -q -- '--foo' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf 'y\n' | imp --foo test >$T/out 2>&1; rc=$?
ok "unbekannte Option vor den Parametern: Abbruch" "[ $rc -ne 0 ] && grep -q 'Unbekannte Option' $T/out && [ ! -e $T/mysql-in.sql ]"
reset; printf 'y\n' | imp --gunzip >$T/out 2>&1; rc=$?
ok "nur Option ohne Parameter: Nutzungshinweis" "[ $rc -ne 0 ] && grep -q 'Nutzung' $T/out"
clean; printf 'geheim\n' | imp --gunzip decrypt other >$T/out 2>&1
ok "Option vor den Positionsparametern (decrypt)" "[ -e $E/proj-other-2026-02-01-10Uhr.sql ]"
clean; printf 'geheim\n' | imp decrypt --gunzip other >$T/out 2>&1
ok "Option zwischen den Positionsparametern (decrypt)" "[ -e $E/proj-other-2026-02-01-10Uhr.sql ]"

rm -rf "$T"; exit $PASSFAIL
