source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
printf 'SSH_HOST="srv"\n' > "$T/tools/remote_srv.conf"
printf 'SSH_HOST="srv2"\nREMOTE_DUMP_DIR="%s/abs/dumps"\nREMOTE_PATCH_DIR="meine-patches"\n' "$T" > "$T/tools/remote_srv2.conf"
D="$T/sql-dumps"; P="$T/sql-patches"; R="$T/remote"; mkdir -p "$D" "$P"
S="$T/tools/sendDB.sh"; F="$T/tools/fetchDB.sh"
echo a > "$D/proj-test-2026-01-01.sql.gz"; touch -d '2026-01-01' "$D/proj-test-2026-01-01.sql.gz"
echo b > "$D/proj-other-2026-01-02.sql.gz"; touch -d '2026-01-02' "$D/proj-other-2026-01-02.sql.gz"
echo c > "$D/proj-test-2026-01-03.sql.gz.gpg"; touch -d '2026-01-03' "$D/proj-test-2026-01-03.sql.gz.gpg"
echo p > "$P/fix.sql"; echo q > "$P/fix2.sql.gz"; echo x > "$P/geheim.sql.gz.gpg"
touch -d '2026-01-05' "$P/fix.sql"; touch -d '2026-01-04' "$P/fix2.sql.gz"

# --- send: Liste, Enter = neueste, Standard-Zielordner relativ zum Server-Home ---
printf '\ny\n' | "$S" srv >$T/out 2>&1; rc=$?
ok "send: Enter waehlt neueste, Datei im Standardordner, verschluesselt unveraendert" "[ $rc -eq 0 ] && [ \"\$(cat $R/sql-dumps/proj-test-2026-01-03.sql.gz.gpg)\" = c ] && [ ! -e $R/sql-dumps/proj-test-2026-01-03.sql.gz.gpg.part ]"
ok "send: Liste neueste zuerst" "grep -q '1) proj-test-2026-01-03' $T/out && grep -q '3) proj-test-2026-01-01' $T/out"

# --- send: Nummer, Abbruch bei n, vorhandene Datei nie ueberschreiben ---
printf '3\nn\n' | "$S" srv >$T/out 2>&1; rc=$?
ok "send: n bricht ab, nichts kopiert" "[ $rc -ne 0 ] && [ ! -e $R/sql-dumps/proj-test-2026-01-01.sql.gz ]"
printf '3\ny\n' | "$S" srv >$T/out 2>&1; rc=$?
ok "send: Nummer 3" "[ $rc -eq 0 ] && [ \"\$(cat $R/sql-dumps/proj-test-2026-01-01.sql.gz)\" = a ]"
echo geaendert > "$R/sql-dumps/proj-test-2026-01-01.sql.gz"
echo y | "$S" srv proj-test-2026-01-01.sql.gz >$T/out 2>&1; rc=$?
ok "send: existiert schon -> Abbruch, Server-Datei unveraendert" "[ $rc -ne 0 ] && grep -q 'existiert auf dem Server schon' $T/out && [ \"\$(cat $R/sql-dumps/proj-test-2026-01-01.sql.gz)\" = geaendert ]"

# --- send: Filter, direkte Datei, Fehler ---
printf '\ny\n' | "$S" srv --env other >$T/out 2>&1; rc=$?
ok "send --env: nur Dumps mit PREFIX der Umgebung" "[ $rc -eq 0 ] && grep -q '1) proj-other-2026-01-02' $T/out && ! grep -q 'proj-test' $T/out && [ -e $R/sql-dumps/proj-other-2026-01-02.sql.gz ]"
echo y | "$S" --env=test srv >$T/out 2>&1
ok "send --env=name und Option vor Server" "grep -q '1) proj-test-2026-01-03' $T/out"
"$S" srv --env nix </dev/null >$T/out 2>&1; rc=$?
ok "send --env unbekannt -> Fehler" "[ $rc -ne 0 ] && grep -q 'unbekannt' $T/out"
"$S" srv x.sql.gz --env test </dev/null >$T/out 2>&1; rc=$?
ok "send --env mit Dateiname -> Fehler" "[ $rc -ne 0 ] && grep -q 'passt nicht zu einem angegebenen Dateinamen' $T/out"
"$S" srv --patch --env test </dev/null >$T/out 2>&1; rc=$?
ok "send --env mit --patch -> Fehler" "[ $rc -ne 0 ] && grep -q 'nur für Dumps' $T/out"
"$S" srv --foo </dev/null >$T/out 2>&1; rc=$?
ok "send: unbekannte Option -> Fehler" "[ $rc -ne 0 ] && grep -q \"Unbekannte Option '--foo'\" $T/out"
"$S" nirgends </dev/null >$T/out 2>&1; rc=$?
ok "send: unbekannter Server -> Fehler" "[ $rc -ne 0 ] && grep -q 'remote_nirgends.conf' $T/out"
"$S" >$T/out 2>&1; rc=$?
ok "send: ohne Server -> Hilfe" "[ $rc -ne 0 ] && grep -q 'Nutzung' $T/out"
( cd "$T/elsewhere" && echo z > ext.sql.gz && echo y | "$S" srv ext.sql.gz >$T/out 2>&1 ); rc=$?
ok "send: Datei aus fremdem Ordner per Pfad/Name" "[ $rc -eq 0 ] && [ \"\$(cat $R/sql-dumps/ext.sql.gz)\" = z ]"
echo y | "$S" srv fix.sql >$T/out 2>&1; rc=$?
ok "send: Patch-Name ohne --patch wird im Dump-Ordner nicht gefunden" "[ $rc -ne 0 ] && grep -q 'nicht gefunden' $T/out"
echo y | "$S" srv "$P/fix.sql" >$T/out 2>&1; rc=$?
ok "send: .sql ohne --patch ist kein Dump -> Fehler, nichts kopiert" "[ $rc -ne 0 ] && grep -q 'kein Dump' $T/out && [ ! -e $R/sql-dumps/fix.sql ]"

# --- send --patch ---
printf '1\ny\n' | "$S" srv --patch >$T/out 2>&1; rc=$?
ok "send --patch: Liste ohne verschluesselte, Ziel sql-patches" "[ $rc -eq 0 ] && ! grep -q geheim $T/out && grep -q 'fix' $T/out && ls $R/sql-patches/fix*.sql* >/dev/null 2>&1"
echo y | "$S" srv fix.sql --patch >$T/out 2>&1; rc=$?
ok "send --patch: Patch existiert schon (aus der Liste kopiert) -> Abbruch" "[ $rc -ne 0 ] && grep -q 'existiert auf dem Server schon' $T/out"
echo y | "$S" srv geheim.sql.gz.gpg --patch >$T/out 2>&1; rc=$?
ok "send --patch: verschluesselter Patch abgelehnt" "[ $rc -ne 0 ] && grep -q 'keine Patch-Datei' $T/out"

# --- send: eigene Server-Ordner aus der Config, Verbindungsfehler, scp-Fehler ---
echo y | "$S" srv2 proj-test-2026-01-01.sql.gz >$T/out 2>&1; rc=$?
ok "send: absoluter REMOTE_DUMP_DIR" "[ $rc -eq 0 ] && [ -e $T/abs/dumps/proj-test-2026-01-01.sql.gz ]"
echo y | "$S" srv2 fix.sql --patch >$T/out 2>&1; rc=$?
ok "send --patch: eigener REMOTE_PATCH_DIR" "[ $rc -eq 0 ] && [ -e $R/meine-patches/fix.sql ]"
echo y | STUB_SSH_FAIL=1 "$S" srv proj-test-2026-01-01.sql.gz >$T/out 2>&1; rc=$?
ok "send: ssh-Fehler -> Abbruch mit Meldung" "[ $rc -ne 0 ] && grep -q 'Verbindung' $T/out"
rm -rf "$R/sql-dumps"
echo y | STUB_SCP_FAIL=1 "$S" srv proj-test-2026-01-01.sql.gz >$T/out 2>&1; rc=$?
ok "send: scp-Fehler -> Abbruch, keine .part-Reste" "[ $rc -ne 0 ] && grep -q 'Kopieren fehlgeschlagen' $T/out && [ -z \"\$(ls $R/sql-dumps 2>/dev/null)\" ]"

# --- fetch ---
rm -rf "$D" "$R"; mkdir -p "$D" "$R/sql-dumps" "$R/sql-patches"
echo r1 > "$R/sql-dumps/proj-test-2026-02-01.sql.gz"; touch -d '2026-02-01' "$R/sql-dumps/proj-test-2026-02-01.sql.gz"
echo r2 > "$R/sql-dumps/proj-other-2026-02-02.sql.gz.gpg"; touch -d '2026-02-02' "$R/sql-dumps/proj-other-2026-02-02.sql.gz.gpg"
echo r3 > "$R/sql-dumps/notiz.txt"
echo rp > "$R/sql-patches/rfix.sql"
printf '\ny\n' | "$F" srv >$T/out 2>&1; rc=$?
ok "fetch: Enter = neueste, nur Dumps gelistet, lokal abgelegt" "[ $rc -eq 0 ] && ! grep -q notiz $T/out && grep -q '1) proj-other-2026-02-02' $T/out && [ \"\$(cat $D/proj-other-2026-02-02.sql.gz.gpg)\" = r2 ]"
echo y | "$F" srv proj-test-2026-02-01.sql.gz >$T/out 2>&1; rc=$?
ok "fetch: Dateiname direkt" "[ $rc -eq 0 ] && [ \"\$(cat $D/proj-test-2026-02-01.sql.gz)\" = r1 ]"
echo y | "$F" srv proj-test-2026-02-01.sql.gz >$T/out 2>&1; rc=$?
ok "fetch: lokal vorhanden -> Abbruch" "[ $rc -ne 0 ] && grep -q 'existiert lokal schon' $T/out"
rm -f "$D"/*
printf '\ny\n' | "$F" srv --env test >$T/out 2>&1
ok "fetch --env: gefilterte Liste" "grep -q '1) proj-test-2026-02-01' $T/out && ! grep -q 'proj-other' $T/out && [ -e $D/proj-test-2026-02-01.sql.gz ]"
printf '\ny\n' | "$F" srv --patch >$T/out 2>&1; rc=$?
ok "fetch --patch: landet im lokalen Patch-Ordner (wird angelegt)" "[ $rc -eq 0 ] && [ \"\$(cat $P/rfix.sql)\" = rp ]"
echo y | "$F" srv ../etc/passwd >$T/out 2>&1; rc=$?
ok "fetch: Pfad im Dateinamen abgelehnt" "[ $rc -ne 0 ] && grep -q 'nur den Dateinamen' $T/out"
echo y | "$F" srv nicht-da.sql.gz >$T/out 2>&1; rc=$?
ok "fetch: Datei fehlt auf dem Server -> Abbruch, keine .part-Reste" "[ $rc -ne 0 ] && [ -z \"\$(ls $D/*.part 2>/dev/null)\" ]"
rm -rf "$R/sql-dumps"
"$F" srv </dev/null >$T/out 2>&1; rc=$?
ok "fetch: Ordner fehlt auf dem Server -> Meldung" "[ $rc -ne 0 ] && grep -q 'nicht lesbar' $T/out"
STUB_SSH_FAIL=1 "$F" srv </dev/null >$T/out 2>&1; rc=$?
ok "fetch: ssh-Fehler -> Abbruch" "[ $rc -ne 0 ] && grep -q 'nicht lesbar' $T/out"
rm -rf "$T"; exit $PASSFAIL
