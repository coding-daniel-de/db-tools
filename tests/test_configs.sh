source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
# setup() legt db_test und db_other im Root ab (Uebergang). Hier zusaetzlich conf/ und Server.
C="$T/tools/conf"; mkdir -p "$C"
X="$T/tools"
printf 'DB_HOST="hconf"\nDB_USER="u"\nDB_PASS="geheim123"\nDB_NAME="nconf"\nPREFIX="proj-conf"\n' > "$C/db_nurconf.conf"
# dieselbe Umgebung in conf/ und im Root: conf/ gewinnt
printf 'DB_HOST="hneu"\nDB_USER="u"\nDB_PASS="geheim123"\nDB_NAME="nneu"\nPREFIX="proj-neu"\n' > "$C/db_beide.conf"
printf 'DB_HOST="halt"\nDB_USER="u"\nDB_PASS="geheim123"\nDB_NAME="nalt"\nPREFIX="proj-alt"\n' > "$X/db_beide.conf"
printf 'DB_HOST="h"\nDB_USER="u"\n' > "$C/db_kaputt.conf"
cp "$REPO/conf/db_template.conf" "$C/"; cp "$REPO/conf/remote_template.conf" "$C/"
printf 'SSH_HOST="srv-conf"\n' > "$C/remote_srv.conf"
printf 'SSH_HOST="srv-root"\n' > "$X/remote_rootsrv.conf"
printf 'REMOTE_DUMP_DIR="x"\n' > "$C/remote_leer.conf"
mkdir -p "$T/sql-dumps"

# --- conf/ und Root-Fallback beim Laden ---
( cd "$T/elsewhere" && "$X/exportDB.sh" nurconf --no-encrypt </dev/null >"$T/out" 2>&1 ); rc=$?
ok "Export: Config nur in conf/ wird gefunden" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-conf-*.sql.gz >/dev/null 2>&1"
( cd "$T/elsewhere" && "$X/exportDB.sh" test --no-encrypt </dev/null >"$T/out" 2>&1 ); rc=$?
ok "Export: Config nur im Root wird gefunden (Uebergang)" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-test-*.sql.gz >/dev/null 2>&1"
( cd "$T/elsewhere" && "$X/exportDB.sh" beide --no-encrypt </dev/null >"$T/out" 2>&1 ); rc=$?
ok "Export: in beiden Orten gewinnt conf/" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-neu-*.sql.gz >/dev/null 2>&1 && ! ls $T/sql-dumps/proj-alt-* >/dev/null 2>&1"
( cd "$T/elsewhere" && "$X/exportDB.sh" gibtsnicht --no-encrypt </dev/null >"$T/out" 2>&1 ); rc=$?
ok "Export: unbekannt -> Fehler nennt beide Suchorte" "[ $rc -ne 0 ] && grep -q \"$C\" $T/out"
( cd "$T/elsewhere" && "$X/importDB.sh" nurconf --from beide --latest </dev/null >"$T/out" 2>&1 ); rc=$?
ok "Import: Ziel aus conf/, --from aus conf/ (Praefix proj-neu)" "[ $rc -eq 0 ]"
echo 'DUMP_DIR="/nirgendwo"' > "$C/dbtools.conf"
( cd "$T/elsewhere" && "$X/importDB.sh" nurconf </dev/null >"$T/out" 2>&1 )
ok "dbtools.conf in conf/ wird gelesen" "grep -q '/nirgendwo' $T/out"
echo 'DUMP_DIR="/woanders"' > "$X/dbtools.conf"
( cd "$T/elsewhere" && "$X/importDB.sh" nurconf </dev/null >"$T/out" 2>&1 )
ok "dbtools.conf in beiden Orten: conf/ gewinnt" "grep -q '/nirgendwo' $T/out && ! grep -q '/woanders' $T/out"
rm -f "$C/dbtools.conf" "$X/dbtools.conf"
( cd "$T/elsewhere" && "$X/sendDB.sh" srv </dev/null >"$T/out" 2>&1 < <(printf '\ny\n') )
ok "Send: Server aus conf/ gefunden" "! grep -q 'nicht gefunden' $T/out"
( cd "$T/elsewhere" && "$X/sendDB.sh" rootsrv </dev/null >"$T/out" 2>&1 )
ok "Send: Server im Root gefunden (Uebergang)" "! grep -q 'nicht gefunden' $T/out"

# --- --configs je Befehl ---
for cmd in exportDB importDB; do
    ( cd "$T/elsewhere" && "$X/$cmd.sh" --configs </dev/null >"$T/out" 2>&1 ); rc=$?
    ok "$cmd --configs: Exit 0, nur Datenbank-Umgebungen" "[ $rc -eq 0 ] && grep -q '^nurconf ' $T/out && grep -q '^test ' $T/out && ! grep -q 'srv' $T/out"
    ok "$cmd --configs: Ziel mit Host, Name und Praefix, kein Passwort" "grep -q 'hconf/nconf, Präfix proj-conf' $T/out && ! grep -q 'geheim123' $T/out && ! grep -q 'DB_PASS' $T/out"
    ok "$cmd --configs: verwendeter Pfad (conf/ gewinnt), Root-Datei als doppelt/veraltet" "grep -q '^beide .*hneu/nneu.*$C/db_beide.conf' $T/out && grep -q 'doppelt/veraltet: $X/db_beide.conf' $T/out"
    ok "$cmd --configs: Root-Config mit Root-Pfad" "grep -q '^test .*$X/db_test.conf' $T/out"
    ok "$cmd --configs: unvollstaendige Config mit Hinweis statt Daten" "grep -q '^kaputt ' $T/out && grep -q 'Hinweis: unvollständig, es fehlt: DB_NAME PREFIX' $T/out"
    ok "$cmd --configs: Vorlage nicht gelistet" "! grep -q '^template' $T/out"
    ( cd "$T/elsewhere" && "$X/$cmd.sh" </dev/null >"$T/out" 2>&1 ); rc=$?
    ok "$cmd ohne Parameter: Hilfe (Exit 1) plus Tabelle" "[ $rc -eq 1 ] && grep -q 'Nutzung' $T/out && grep -q '^nurconf ' $T/out"
done
( cd "$T/elsewhere" && "$X/exportDB.sh" --configs test </dev/null >"$T/out" 2>&1 ); rc=$?
ok "export --configs mit weiterem Parameter: nur Tabelle, kein Export, Exit 0" "[ $rc -eq 0 ] && ! ls $T/sql-dumps/proj-test-*-*.sql.gz.1 >/dev/null 2>&1 && grep -q '^nurconf ' $T/out"
( cd "$T/elsewhere" && "$X/importDB.sh" ddev --configs </dev/null >"$T/out" 2>&1 ); rc=$?
ok "import ddev --configs: reserviertes Wort kollidiert nicht" "[ $rc -eq 0 ] && grep -q '^nurconf ' $T/out"
for cmd in sendDB fetchDB; do
    ( cd "$T/elsewhere" && "$X/$cmd.sh" --configs </dev/null >"$T/out" 2>&1 ); rc=$?
    ok "$cmd --configs: Exit 0, nur Server, Pfade, conf/ vor Root" "[ $rc -eq 0 ] && grep -q \"^srv .*SSH: srv-conf .*$C/remote_srv.conf\" $T/out && grep -q \"^rootsrv .*SSH: srv-root .*$X/remote_rootsrv.conf\" $T/out && ! grep -q 'nurconf' $T/out"
    ok "$cmd --configs: unvollstaendiger Server mit Hinweis" "grep -q '^leer ' $T/out && grep -q 'Hinweis: unvollständig, es fehlt: SSH_HOST' $T/out"
    ( cd "$T/elsewhere" && "$X/$cmd.sh" </dev/null >"$T/out" 2>&1 ); rc=$?
    ok "$cmd ohne Parameter: Hilfe (Exit 1) plus Servertabelle" "[ $rc -eq 1 ] && grep -q 'Nutzung' $T/out && grep -q '^srv ' $T/out"
done

# --- db-configs ---
( cd "$T/elsewhere" && "$X/configsDB.sh" </dev/null >"$T/out" 2>&1 ); rc=$?
ok "db-configs: Exit 0" "[ $rc -eq 0 ]"
ok "db-configs: Header" "grep -q '^Name .*Art' $T/out"
ok "db-configs: nurconf" "grep -q '^nurconf .*Datenbank-Umgebung' $T/out"
ok "db-configs: srv" "grep -q '^srv .*Server' $T/out"
ok "db-configs: kein Passwort" "! grep -q 'geheim123' $T/out"
( cd "$T/elsewhere" && "$X/configsDB.sh" --quatsch </dev/null >"$T/out" 2>&1 ); rc=$?
ok "db-configs: unbekannte Option -> Fehler" "[ $rc -ne 0 ] && grep -q 'Fehler' $T/out"
T2=$(mktemp -d); mkdir -p "$T2"; cp "$X/configsDB.sh" "$X/dbtools-lib.sh" "$T2/"
"$T2/configsDB.sh" >"$T/out" 2>&1
ok "db-configs ohne Configs: freundlicher Hinweis auf die Vorlage" "grep -q 'Keine Configs gefunden' $T/out"
rm -rf "$T2"

# --- backupAll findet Umgebungen in conf/ ---
printf 'BACKUP_ENVS="nurconf beide"\nBACKUP_DIR="%s/bk"\n' "$T" > "$C/dbtools.conf"
( cd "$T/elsewhere" && "$X/backupAll.sh" </dev/null >"$T/out" 2>&1 ); rc=$?
ok "backupAll: Umgebungen und dbtools.conf aus conf/" "[ $rc -eq 0 ] && ls $T/bk/proj-conf-*.sql.gz >/dev/null 2>&1 && ls $T/bk/proj-neu-*.sql.gz >/dev/null 2>&1"

# --- Installer: Completion idempotent ---
H="$T/home"; mkdir -p "$H"; : > "$H/.bashrc"
( HOME="$H" "$REPO/install.sh" --path "$H/bin" ) >"$T/out" 2>&1; rc=$?
ok "install --path: Completion in bashrc eingetragen" "[ $rc -eq 0 ] && grep -qF 'source \"$REPO/dbtools-completion.sh\"' $H/.bashrc"
( HOME="$H" "$REPO/install.sh" --path "$H/bin" ) >"$T/out" 2>&1
ok "install: zweiter Lauf traegt Completion nicht doppelt ein" "[ \"\$(grep -cF 'dbtools-completion.sh' $H/.bashrc)\" -eq 1 ]"
H2="$T/home2"; mkdir -p "$H2"; : > "$H2/.bashrc"
( HOME="$H2" "$REPO/install.sh" "$H2/bin" </dev/null ) >"$T/out" 2>&1
ok "install: ohne Terminal und ohne --path keine Completion, aber Hinweis" "! grep -q 'dbtools-completion' $H2/.bashrc && grep -q 'Tab-Vervollständigung nicht eingetragen' $T/out"

# --- Completion-Funktion ---
comp() { # comp <befehl> <wort>...: letztes Wort ist die Eingabe am Cursor (Aufruf im leeren Ordner)
    cd "$T/elsewhere" && bash -c '
        source "$1/dbtools-completion.sh"; shift
        cmd="$1"; shift
        COMP_WORDS=("$cmd" "$@"); COMP_CWORD=$#
        case "$cmd" in
            db-export) _dbtools_complete_export ;; db-import) _dbtools_complete_import ;;
            db-decrypt) _dbtools_complete_decrypt ;; *) _dbtools_complete_transfer ;;
        esac
        printf "%s\n" "${COMPREPLY[@]}" | sort | tr "\n" " "' _ "$X" "$@"
}
ok "Completion db-import: Umgebungen plus ddev und decrypt, keine Server, keine Vorlage" "[ \"\$(comp db-import '')\" = 'beide ddev decrypt kaputt nurconf other test ' ]" 
ok "Completion db-import mit Praefix" "[ \"\$(comp db-import 'n')\" = 'nurconf ' ]"
ok "Completion db-export: ddev, aber nicht decrypt" "[ \"\$(comp db-export 'd')\" = 'ddev ' ]"
ok "Completion db-send: nur Server" "[ \"\$(comp db-send '')\" = 'leer rootsrv srv ' ] && [ \"\$(comp db-fetch 's')\" = 'srv ' ]"
ok "Completion db-import --from: Umgebungen ohne reservierte Woerter" "[ \"\$(comp db-import update --from 'n')\" = 'nurconf ' ] && [ \"\$(comp db-import update --from '')\" = 'beide kaputt nurconf other test ' ]"
ok "Completion db-send --env: Datenbank-Umgebungen" "[ \"\$(comp db-send srv --env 'b')\" = 'beide ' ]"
ok "Completion: Position 2 nach Umgebung bietet keine Umgebungen" "[ -z \"\$(comp db-import test n | tr -d ' ')\" ]"
ok "Completion: Option nach --from zaehlt nicht als Position" "[ \"\$(comp db-import --from dev 'n')\" = 'nurconf ' ]"
ok "Completion Optionen" "[ \"\$(comp db-send srv -- )\" = '--configs --env --patch ' ]"
rm -rf "$T"; exit $PASSFAIL
