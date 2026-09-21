source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
D="$T/sql-dumps"; mkdir -p $D
# PATH ohne gpg: Symlinks auf alles ausser gpg*
NOGPG="$T/nogpg"; mkdir -p "$NOGPG"
for f in /usr/bin/*; do case "$(basename $f)" in gpg*|dirmngr) ;; *) ln -s "$f" "$NOGPG/$(basename $f)";; esac; done
ok "dbtools-lib.sh existiert und ist nicht ausfuehrbar" "[ -f $REPO/dbtools-lib.sh ] && [ ! -x $REPO/dbtools-lib.sh ]"

# 1. Import: Exit 1 bei Fehler
printf 'CREATE TABLE t (id int);\n' | gzip > $D/proj-test-2026-01-01-10Uhr.sql.gz
( cd $T/elsewhere && echo y | STUB_MYSQL_FAIL=1 $T/tools/importDB.sh test >$T/out 2>&1 ); rc=$?
ok "Import-Fehler: Exit 1" "[ $rc -eq 1 ] && grep -q 'Fehler: Beim Import' $T/out"
( cd $T/elsewhere && echo y | $T/tools/importDB.sh test >$T/out 2>&1 ); rc=$?
ok "Import ok: Exit 0" "[ $rc -eq 0 ] && grep -q 'Erfolgreich importiert' $T/out"
( cd $T/elsewhere && echo n | $T/tools/importDB.sh test >$T/out 2>&1 ); rc=$?
ok "Import abgebrochen (N): Exit 0 wie bisher" "[ $rc -eq 0 ]"

# 3. gpg fehlt
( cd $T/elsewhere && printf 'y\nx\nx\n' | PATH="$STUBS:$NOGPG" $T/tools/exportDB.sh test >$T/out 2>&1 ); rc=$?
ok "Export ohne gpg: Meldung, Exit 1, vor Passwortabfrage" "[ $rc -eq 1 ] && grep -q 'gpg ist nicht installiert' $T/out && ! grep -q 'Passwort' $T/out && ! ls $D/*.gpg >/dev/null 2>&1"
( cd $T/elsewhere && printf 'n\n' | PATH="$STUBS:$NOGPG" $T/tools/exportDB.sh test >$T/out 2>&1 ); rc=$?
ok "Export ohne gpg, aber unverschluesselt: laeuft" "[ $rc -eq 0 ]"
printf 'x' | gpg --batch --yes -q --pinentry-mode loopback --passphrase geheim -c -o $D/proj-test-2026-02-01-10Uhr.sql.gz.gpg
( cd $T/elsewhere && printf 'geheim\ny\n' | PATH="$STUBS:$NOGPG" $T/tools/importDB.sh test >$T/out 2>&1 ); rc=$?
ok "Import .gpg ohne gpg: Meldung, Exit 1, keine Passwortabfrage" "[ $rc -eq 1 ] && grep -q 'gpg ist nicht installiert' $T/out && ! grep -q 'Falsches Passwort' $T/out && ! grep -q 'Passwort für' $T/out"
rm -f $D/*

# 2. trap: Abbruch waehrend des Dumps (ganze Prozessgruppe, wie Ctrl+C im Terminal)
for sig in INT TERM; do
  for enc in n y; do
    rm -f $D/*
    if [ $enc = y ]; then IN=$'y\ngeheim\ngeheim\n'; else IN=$'n\n'; fi
    ( cd $T/elsewhere && printf '%s' "$IN" | STUB_DUMP_SLEEP=5 setsid $T/tools/exportDB.sh test >$T/out 2>&1 ) &
    sleep 1.5
    pid=$(pgrep -f "$T/tools/exportDB.sh test" | head -n1)
    [ -n "$pid" ] && kill -$sig -- -$pid 2>/dev/null
    wait
    sleep 0.3
    ok "Abbruch $sig (enc=$enc): Teildatei geloescht, Meldung, kein Erfolg" "[ -n '$pid' ] && ! ls $D/proj-test-* >/dev/null 2>&1 && grep -q 'abgebrochen' $T/out && ! grep -q 'Erfolgreich' $T/out"
  done
done
rm -rf "$T"; exit $PASSFAIL
