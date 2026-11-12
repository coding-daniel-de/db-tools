source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
setup
# Installation mit conf/ (Vorlagen) im Wegwerf-Ordner, HOME ist $T
mkdir -p "$T/tools/conf"
cp "$REPO/conf/"* "$T/tools/conf/"
U="$T/db-tools-conf"
INIT="$T/tools/initConfigDB.sh"
perm() { stat -c %a "$1"; }

# --- ohne Parameter: Ordner 700 und die drei Vorlagen ---
"$INIT" >$T/out 2>&1; rc=$?
ok "init: Exit 0, Ordner mit 700" "[ $rc -eq 0 ] && [ -d $U ] && [ \"\$(perm $U)\" = 700 ]"
ok "init: die drei Vorlagen kopiert und gemeldet" "[ -f $U/db_template.conf ] && [ -f $U/remote_template.conf ] && [ -f $U/dbtools.conf.example ] && [ \"\$(grep -c '^Angelegt' $T/out)\" -eq 4 ]"
ok "init: keine echte Config angelegt" "[ -z \"\$(ls $U/db_*.conf | grep -v template)\" ]"

# --- zweiter Aufruf ändert nichts ---
echo "# eigene Aenderung" >> "$U/db_template.conf"
sum1=$(cd $U && ls -l --time-style=full-iso . | md5sum; cat * | md5sum)
"$INIT" >$T/out 2>&1; rc=$?
sum2=$(cd $U && ls -l --time-style=full-iso . | md5sum; cat * | md5sum)
ok "init: zweiter Aufruf ändert nichts, meldet 'Schon vorhanden'" "[ $rc -eq 0 ] && [ \"$sum1\" = \"$sum2\" ] && [ \"\$(grep -c 'Schon vorhanden' $T/out)\" -eq 4 ] && ! grep -q '^Angelegt' $T/out"
ok "init: vorhandene (geänderte) Vorlage nicht überschrieben" "grep -q 'eigene Aenderung' $U/db_template.conf"

# --- fehlende Vorlage wird nachgelegt, andere bleiben ---
rm "$U/remote_template.conf"
"$INIT" >$T/out 2>&1
ok "init: fehlende Vorlage nachgelegt, geänderte bleibt" "[ -f $U/remote_template.conf ] && grep -q 'eigene Aenderung' $U/db_template.conf"

# --- Name ---
"$INIT" live >$T/out 2>&1; rc=$?
ok "init <name>: db_live.conf mit 600 aus der Vorlage, Pfad genannt" "[ $rc -eq 0 ] && [ \"\$(perm $U/db_live.conf)\" = 600 ] && cmp -s $U/db_live.conf $T/tools/conf/db_template.conf && grep -qF '$U/db_live.conf' $T/out"
echo 'DB_PASS="geheim"' >> "$U/db_live.conf"
"$INIT" live >$T/out 2>&1; rc=$?
ok "init <name>: vorhandene Config -> Abbruch, Datei unverändert" "[ $rc -ne 0 ] && grep -q 'existiert bereits' $T/out && grep -q geheim $U/db_live.conf"
for bad in 'a/b' '../x' 'a b' ddev decrypt template; do
    "$INIT" "$bad" >$T/out 2>&1; rc=$?
    ok "init: Name '$bad' abgelehnt" "[ $rc -ne 0 ] && grep -q 'Fehler' $T/out && [ ! -e '$T/db_$bad.conf' ]"
done
"$INIT" a b >$T/out 2>&1; rc=$?
ok "init: zwei Namen -> Fehler" "[ $rc -ne 0 ]"
"$INIT" --gibtsnicht >$T/out 2>&1; rc=$?
ok "init: unbekannte Option -> Fehler" "[ $rc -ne 0 ] && grep -q 'Unbekannte Option' $T/out"
"$INIT" --templates neu >$T/out 2>&1; rc=$?
ok "init: --templates mit Name -> Fehler, nichts angelegt" "[ $rc -ne 0 ] && [ ! -e $U/db_neu.conf ]"

# --- --templates ---
echo 'DB_NAME="meins"' > "$U/db_privat.conf"; chmod 600 "$U/db_privat.conf"
echo "# neu in der Installation" >> "$T/tools/conf/remote_template.conf"
"$INIT" --templates >$T/out 2>&1; rc=$?
ok "init --templates: geänderte Vorlage überschrieben und gemeldet" "[ $rc -eq 0 ] && cmp -s $U/db_template.conf $T/tools/conf/db_template.conf && cmp -s $U/remote_template.conf $T/tools/conf/remote_template.conf && grep -q 'Aktualisiert.*db_template.conf' $T/out && grep -q 'Aktualisiert.*remote_template.conf' $T/out && grep -q 'Unverändert.*dbtools.conf.example' $T/out"
ok "init --templates: echte Configs unberührt" "grep -q geheim $U/db_live.conf && grep -q meins $U/db_privat.conf && [ \"\$(perm $U/db_live.conf)\" = 600 ]"
"$INIT" --templates >$T/out 2>&1
ok "init --templates: zweiter Lauf meldet nichts Aktualisiertes" "! grep -q Aktualisiert $T/out"

# --- Ordner fehlt, nur --templates ---
rm -rf "$U"
"$INIT" --templates >$T/out 2>&1; rc=$?
ok "init --templates: legt fehlenden Ordner samt Vorlagen an" "[ $rc -eq 0 ] && [ \"\$(perm $U)\" = 700 ] && [ -f $U/db_template.conf ]"

# --- Hilfe und Symlink-Aufruf ---
"$INIT" --help >$T/out 2>&1; rc=$?
ok "init --help: Exit 0 mit Nutzung" "[ $rc -eq 0 ] && grep -q '^Nutzung' $T/out"
mkdir -p "$T/symbin"; ln -s "$INIT" "$T/symbin/db-init-config"; rm -rf "$U"
( cd "$T/elsewhere" && "$T/symbin/db-init-config" ) >$T/out 2>&1; rc=$?
ok "init per Symlink: Lib und Vorlagen gefunden" "[ $rc -eq 0 ] && [ -f $U/db_template.conf ]"

# --- Die neue Config wird von den Tools gefunden ---
"$INIT" frisch >$T/out 2>&1
"$T/tools/configsDB.sh" >$T/out 2>&1
ok "init: angelegte Config erscheint in der Config-Übersicht" "grep -q frisch $T/out"
rm -rf "$T"; exit $PASSFAIL
