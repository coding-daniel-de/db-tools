source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
# setup() setzt HOME=$T; der User-Ordner liegt also im Wegwerf-Ordner, nie im echten Home.
X="$T/tools"; U="$T/db-tools-conf"; C="$X/conf"
mkdir -p "$U" "$C" "$T/sql-dumps"
rm -f "$X/db_test.conf" "$X/db_other.conf"
mk() { printf 'DB_HOST="%s"\nDB_USER="u"\nDB_PASS="geheim123"\nDB_NAME="n"\nPREFIX="%s"\n' "$2" "$3" > "$1"; chmod 600 "$1"; }
mk "$U/db_nuruser.conf" huser proj-user
mk "$C/db_nurconf.conf" hconf proj-conf
mk "$X/db_nurroot.conf" hroot proj-root
mk "$U/db_alle.conf" huser proj-useralle
mk "$C/db_alle.conf" hconf proj-confalle
mk "$X/db_alle.conf" hroot proj-rootalle
printf 'SSH_HOST="srv-user"\n' > "$U/remote_usersrv.conf"
run() { ( cd "$T/elsewhere" && "$X/$1" "${@:2}" </dev/null >"$T/out" 2>"$T/err" ); }

# --- Suche ---
run exportDB.sh nuruser --no-encrypt; rc=$?
ok "Export: Config nur im User-Ordner" "[ $rc -eq 0 ] && ls $T/sql-dumps/proj-user-*.sql.gz >/dev/null 2>&1"
run exportDB.sh nurconf --no-encrypt
ok "Export: Config nur in conf/" "ls $T/sql-dumps/proj-conf-*.sql.gz >/dev/null 2>&1"
run exportDB.sh nurroot --no-encrypt
ok "Export: Config nur im Root" "ls $T/sql-dumps/proj-root-*.sql.gz >/dev/null 2>&1"
run exportDB.sh alle --no-encrypt
ok "Export: in allen dreien gewinnt der User-Ordner" "ls $T/sql-dumps/proj-useralle-*.sql.gz >/dev/null 2>&1 && ! ls $T/sql-dumps/proj-confalle-* $T/sql-dumps/proj-rootalle-* >/dev/null 2>&1"
run exportDB.sh gibtsnicht --no-encrypt; rc=$?
ok "Fehlermeldung nennt alle Suchorte" "[ $rc -ne 0 ] && grep -qF \"'$U'\" $T/out && grep -qF \"'$C'\" $T/out && grep -qF \"'$X'\" $T/out"
run sendDB.sh usersrv
ok "Send: Server aus dem User-Ordner gefunden" "! grep -q 'nicht gefunden' $T/out"

# --- --configs ---
run exportDB.sh --configs
ok "--configs: User-Ordner-Config mit Pfad" "grep -q \"^nuruser .*$U/db_nuruser.conf\" $T/out"
ok "--configs: verwendeter Pfad ist der User-Ordner" "grep -q \"^alle .*$U/db_alle.conf\" $T/out"
ok "--configs: ueberdeckte Dateien markiert (conf/ ueberdeckt, Root veraltet)" "grep -q \"doppelt/überdeckt: $C/db_alle.conf\" $T/out && grep -q \"doppelt/veraltet: $X/db_alle.conf\" $T/out"
ok "--configs: Config ohne Duplikat ohne Hinweis" "! grep -A1 '^nuruser ' $T/out | grep -q doppelt"
run sendDB.sh --configs
ok "send --configs: Server aus dem User-Ordner" "grep -q \"^usersrv .*$U/remote_usersrv.conf\" $T/out"

# --- Vervollstaendigung ---
names=$(cd "$T/elsewhere" && "$X/configsDB.sh" --names db | tr '\n' ' ')
ok "Namen (Completion) enthalten den User-Ordner, eindeutig" "[ '$names' = 'alle nurconf nurroot nuruser ' ]"

# --- dbtools.conf schichten ---
printf 'DUMP_DIR="/aus-root"\nPATCH_DIR="/patch-root"\nBACKUP_ENVS="alle"\n' > "$X/dbtools.conf"
printf 'DUMP_DIR="/aus-conf"\n' > "$C/dbtools.conf"
printf 'DUMP_DIR="/aus-user"\n' > "$U/dbtools.conf"
vals=$(cd "$T/elsewhere" && bash -c 'SCRIPT_DIR="$1"; source "$1/dbtools-lib.sh"; resolve_dirs; echo "$DUMP_DIR $PATCH_DIR $BACKUP_ENVS"' _ "$X")
ok "dbtools.conf geschichtet: User ueberschreibt einzelnen Wert, Rest bleibt" "[ '$vals' = '/aus-user /patch-root alle' ]"
rm -f "$X/dbtools.conf" "$C/dbtools.conf" "$U/dbtools.conf"

# --- Rechte-Warnung ---
for m in 644 640 660 604; do
    chmod $m "$U/db_nuruser.conf"; run exportDB.sh nuruser --no-encrypt
    ok "Warnung bei $m (stderr)" "grep -q 'Warnung' $T/err && grep -qF '$U/db_nuruser.conf' $T/err && ! grep -q Warnung $T/out"
done
for m in 600 400; do
    chmod $m "$U/db_nuruser.conf"; run exportDB.sh nuruser --no-encrypt
    ok "keine Warnung bei $m" "! grep -q Warnung $T/err"
done
chmod 644 "$U/db_nuruser.conf"; chmod 644 "$C/db_nurconf.conf"
run exportDB.sh nurconf --no-encrypt; rc=$?
ok "Warnung auch fuer conf/, Lauf geht weiter" "grep -q Warnung $T/err && [ $rc -eq 0 ]"
echo 'CHECK_CONF_PERMS=0' > "$U/dbtools.conf"
run exportDB.sh nuruser --no-encrypt
ok "CHECK_CONF_PERMS=0 schaltet die Warnung ab" "! grep -q Warnung $T/err"
echo 'CHECK_CONF_PERMS=0' > "$C/dbtools.conf"; rm -f "$U/dbtools.conf"
run exportDB.sh nurconf --no-encrypt
ok "CHECK_CONF_PERMS=0 in conf/ wirkt ebenfalls" "! grep -q Warnung $T/err"
rm -f "$C/dbtools.conf"
printf 'SSH_HOST="x"\n' > "$C/remote_weit.conf"; chmod 644 "$C/remote_weit.conf"
run sendDB.sh weit
ok "remote_*.conf wird nicht geprueft" "! grep -q Warnung $T/err"
once=$(bash -c 'SCRIPT_DIR="$1"; source "$1/dbtools-lib.sh"; load_db_conf "$2"; load_db_conf "$2"' _ "$X" "$U/db_nuruser.conf" 2>&1 >/dev/null | grep -c Warnung)
ok "eine Warnung pro Datei und Lauf" "[ '$once' = 1 ]"

# --- backupAll ---
chmod 600 "$U/db_nuruser.conf"
printf 'BACKUP_ENVS="nuruser"\nBACKUP_DIR="%s/bk"\n' "$T" > "$U/dbtools.conf"
( cd "$T/elsewhere" && "$X/backupAll.sh" </dev/null >"$T/out" 2>&1 ); rc=$?
ok "backupAll: Umgebung und dbtools.conf aus dem User-Ordner" "[ $rc -eq 0 ] && ls $T/bk/proj-user-*.sql.gz >/dev/null 2>&1"
chmod 644 "$U/db_nuruser.conf"
( cd "$T/elsewhere" && "$X/backupAll.sh" </dev/null >"$T/out" 2>&1 ); rc=$?
ok "backupAll: Rechte-Warnung nur im Fehlerfall sichtbar (Export laeuft sonst still)" "[ $rc -eq 0 ] && [ ! -s $T/out ]"
rm -rf "$T"; exit $PASSFAIL
