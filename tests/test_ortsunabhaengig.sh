source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
# Default-Dumpverzeichnis: <tools>/../sql-dumps, Start aus fremdem Ordner
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test </dev/null >/dev/null 2>&1 )
ok "export fremder Ordner, Default-Dir" "ls $T/sql-dumps/proj-test-*.sql.gz >/dev/null 2>&1"
( cd "$T/elsewhere" && echo y | "$T/tools/importDB.sh" test >/dev/null 2>&1 )
ok "import fremder Ordner, Default-Dir" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
# relativer DUMP_DIR relativ zum Skript-Ordner
echo 'DUMP_DIR="dumps-rel"' > "$T/tools/dbtools.conf"
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test </dev/null >/dev/null 2>&1 )
ok "relativer DUMP_DIR relativ zum Skript-Ordner" "ls $T/tools/dumps-rel/proj-test-*.sql.gz >/dev/null 2>&1"
# absoluter DUMP_DIR
echo "DUMP_DIR=\"$T/abs\"" > "$T/tools/dbtools.conf"
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" test </dev/null >/dev/null 2>&1 )
ok "absoluter DUMP_DIR unveraendert" "ls $T/abs/proj-test-*.sql.gz >/dev/null 2>&1"
rm -f "$T/mysql-in.sql"
( cd "$T/elsewhere" && echo y | "$T/tools/importDB.sh" test >/dev/null 2>&1 )
ok "import nutzt selben DUMP_DIR" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
# Quell-Umgebung, Dateiname relativ zum aktuellen Ordner
( cd "$T/elsewhere" && "$T/tools/exportDB.sh" other </dev/null >/dev/null 2>&1 )
rm -f "$T/mysql-in.sql"
( cd "$T/elsewhere" && echo y | "$T/tools/importDB.sh" test other >/dev/null 2>&1 )
ok "Quell-Umgebung aus fremdem Ordner" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
cp "$T"/abs/proj-other-*.sql.gz "$T/elsewhere/local.sql.gz"
rm -f "$T/mysql-in.sql"
( cd "$T/elsewhere" && echo y | "$T/tools/importDB.sh" test local.sql.gz >/dev/null 2>&1 )
ok "Dateiname relativ zum aktuellen Ordner" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
# Start aus Skript-Ordner
rm -f "$T/mysql-in.sql"
( cd "$T/tools" && echo y | ./importDB.sh test >/dev/null 2>&1 )
ok "Start aus Skript-Ordner" "grep -q 'CREATE TABLE' $T/mysql-in.sql"
rm -rf "$T"; exit $PASSFAIL
