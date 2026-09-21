source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"
run() { ( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test ); }
# unverschluesselt (N und Enter)
echo n | run >/dev/null 2>&1
ok "N: unverschluesselte .sql.gz" "ls $D/proj-test-*.sql.gz >/dev/null 2>&1 && ! ls $D/*.gpg >/dev/null 2>&1"
F=$(ls $D/proj-test-*.sql.gz); ok "N: Inhalt ohne Sandbox-Zeile" "! gunzip -c $F | grep -q sandbox && gunzip -c $F | grep -q 'CREATE TABLE'"
rm -f $D/*
# verschluesselt
printf 'y\ngeheim\ngeheim\n' | run >/dev/null 2>&1; rc=$?
ok "y: .sql.gz.gpg erzeugt, Exit 0" "[ $rc -eq 0 ] && ls $D/proj-test-*.sql.gz.gpg >/dev/null 2>&1"
F=$(ls $D/*.gpg)
ok "y: entschluesselbar mit Passwort" "printf geheim | gpg --batch -q --pinentry-mode loopback --passphrase-fd 0 -d $F 2>/dev/null | gunzip | grep -q 'CREATE TABLE'"
ok "y: falsches Passwort scheitert" "! printf falsch | gpg --batch -q --pinentry-mode loopback --passphrase-fd 0 -d $F >/dev/null 2>&1"
rm -f $D/*
# Passwoerter ungleich
printf 'y\na\nb\n' | run >$T/out 2>&1; rc=$?
ok "ungleiche Passwoerter: Abbruch, keine Datei" "[ $rc -ne 0 ] && ! ls $D/proj-test-* >/dev/null 2>&1"
# leeres Passwort
printf 'y\n\n\n' | run >$T/out 2>&1; rc=$?
ok "leeres Passwort: Abbruch, keine Datei" "[ $rc -ne 0 ] && ! ls $D/proj-test-* >/dev/null 2>&1"
# mysqldump-Fehler unverschluesselt
printf 'n\n' | STUB_DUMP_FAIL=1 run >$T/out 2>&1; rc=$?
ok "Dump-Fehler unverschluesselt: Exit 1, Datei geloescht, keine Erfolgsmeldung" "[ $rc -eq 1 ] && ! ls $D/proj-test-* >/dev/null 2>&1 && ! grep -q 'Erfolgreich' $T/out"
printf 'y\ngeheim\ngeheim\n' | STUB_DUMP_FAIL=1 run >$T/out 2>&1; rc=$?
ok "Dump-Fehler verschluesselt: Exit 1, Datei geloescht" "[ $rc -eq 1 ] && ! ls $D/proj-test-* >/dev/null 2>&1 && ! grep -q 'Erfolgreich' $T/out"
# Passwort nicht in ps/Ausgabe
ok "Passwort nicht in Ausgabe" "! grep -q geheim $T/out"
rm -rf "$T"; exit $PASSFAIL
