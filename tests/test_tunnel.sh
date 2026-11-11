source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
export STUB_SSH_LOG="$T/ssh.log" STUB_DB_ARGS="$T/db.args"
D="$T/sql-dumps"; mkdir -p "$D"
printf 'DB_HOST="egal"\nDB_USER="u"\nDB_PASS="p"\nDB_NAME="n"\nPREFIX="proj-tun"\nSSH_TUNNEL="srvalias"\n' > "$T/tools/db_tun.conf"
printf 'DB_HOST="h"\nDB_USER="u"\nDB_PASS="p"\nDB_NAME="n"\nPREFIX="proj-tun2"\nSSH_TUNNEL="srvalias"\nTUNNEL_PORT="3399"\nTUNNEL_REMOTE="db.intern:3307"\n' > "$T/tools/db_tun2.conf"
printf 'DB_HOST="h"\nDB_USER="u"\nDB_PASS="p"\nDB_NAME="n"\nPREFIX="proj-port"\nDB_PORT="3310"\n' > "$T/tools/db_port.conf"

# --- Export mit Tunnel (Standardwerte) ---
"$T/tools/exportDB.sh" tun --no-encrypt </dev/null >$T/out 2>&1; rc=$?
ok "export Tunnel: Exit 0, Dump angelegt" "[ $rc -eq 0 ] && ls $D/proj-tun-*.sql.gz >/dev/null 2>&1"
ok "export Tunnel: ssh -L mit Standardport 3307 -> 127.0.0.1:3306 ueber den Alias" "grep -q 'TUNNEL .*-L 127.0.0.1:3307:127.0.0.1:3306 srvalias' $T/ssh.log"
ok "export Tunnel: mysqldump mit 127.0.0.1 und Port 3307, DB_HOST der Config ignoriert" "grep -q 'mysqldump -h 127.0.0.1 -P 3307 ' $T/db.args"
ok "export Tunnel: Tunnel am Ende geschlossen" "grep -q 'TUNNEL-EXIT .*srvalias' $T/ssh.log && ! ls ${TMPDIR:-/tmp}/dbtools-tunnel.* >/dev/null 2>&1"

# --- eigene Werte ---
rm -f "$T/ssh.log" "$T/db.args"
"$T/tools/exportDB.sh" tun2 --no-encrypt </dev/null >$T/out 2>&1
ok "export Tunnel: TUNNEL_PORT und TUNNEL_REMOTE aus der Config" "grep -q -- '-L 127.0.0.1:3399:db.intern:3307 srvalias' $T/ssh.log && grep -q 'mysqldump -h 127.0.0.1 -P 3399 ' $T/db.args"

# --- Tunnel schlaegt fehl: kein Dump, klare Meldung, nichts zu schliessen ---
rm -f "$T/ssh.log" "$T/db.args"; rm -f $D/*
STUB_TUNNEL_FAIL=1 "$T/tools/exportDB.sh" tun --no-encrypt </dev/null >$T/out 2>&1; rc=$?
ok "export Tunnel-Fehler: Abbruch mit Meldung, kein Dump, kein mysqldump" "[ $rc -ne 0 ] && grep -q 'Tunnel.*nicht geöffnet' $T/out && ! ls $D/proj-tun-* >/dev/null 2>&1 && [ ! -e $T/db.args ]"
ok "export Tunnel-Fehler: kein Schliessen noetig" "! grep -q TUNNEL-EXIT $T/ssh.log"

# --- Ohne Tunnel: kein ssh, kein -P; mit DB_PORT: -P ohne Tunnel ---
rm -f "$T/ssh.log" "$T/db.args"
"$T/tools/exportDB.sh" test --no-encrypt </dev/null >$T/out 2>&1
ok "ohne SSH_TUNNEL: kein ssh-Aufruf, kein -P" "[ ! -e $T/ssh.log ] && grep -q 'mysqldump -h h -u u' $T/db.args"
rm -f "$T/ssh.log" "$T/db.args"
"$T/tools/exportDB.sh" port --no-encrypt </dev/null >$T/out 2>&1
ok "DB_PORT ohne Tunnel: -P, kein ssh" "[ ! -e $T/ssh.log ] && grep -q 'mysqldump -h h -P 3310 ' $T/db.args"

# --- Import mit Tunnel ---
rm -f "$T/ssh.log" "$T/db.args"
printf 'CREATE TABLE t (id int);\n' | gzip > "$D/proj-tun-2026-01-01.sql.gz"
echo y | "$T/tools/importDB.sh" tun --latest >$T/out 2>&1; rc=$?
ok "import Tunnel: Exit 0, mysql ueber 127.0.0.1:3307, Tunnel geschlossen" "[ $rc -eq 0 ] && grep -q 'mysql -h 127.0.0.1 -P 3307 ' $T/db.args && grep -q TUNNEL-EXIT $T/ssh.log"

# --- Werte einer Umgebung bleiben nicht in der naechsten haengen ---
rm -f "$T/ssh.log" "$T/db.args"
( set -e; source "$T/tools/dbtools-lib.sh"; SCRIPT_DIR="$T/tools"; load_db_conf "$T/tools/db_tun2.conf" >/dev/null; load_db_conf "$T/tools/db_test.conf"; [ -z "$SSH_TUNNEL" ] && [ -z "$TUNNEL_PORT" ] && [ ${#DB_PORT_ARGS[@]} -eq 0 ] && [ "$DB_HOST" = h ] )
ok "load_db_conf: Tunnel-Werte der vorigen Config zurueckgesetzt" "[ $? -eq 0 ]"
rm -rf "$T"; exit $PASSFAIL
