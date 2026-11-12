# db-tools

Kleine Shell-Skripte zum Exportieren und Importieren von MySQL/MariaDB-Datenbanken über verschiedene Umgebungen hinweg (z. B. dev, update, live).

## Installation

Damit die Tools ohne Pfad aufrufbar sind, legt `install.sh` Symlinks in einem Ordner im `PATH` an:

```
./install.sh                  # nach ~/bin
./install.sh ~/.local/bin     # in einen anderen Ordner
./install.sh --path           # dazu ~/bin ohne Rückfrage in den PATH der ~/.bashrc eintragen
```

Die Befehle: `db-export` (`exportDB.sh`), `db-import` (`importDB.sh`) und `db-decrypt` (`decryptDB.sh`), `db-send` (`sendDB.sh`) und `db-fetch` (`fetchDB.sh`) sowie `db-configs` (`configsDB.sh`, Übersicht aller Configs). `backupAll.sh` bekommt keinen Symlink, es läuft per Cron mit vollem Pfad. Der Zielordner wird bei Bedarf angelegt. Liegt er nicht im `PATH`, fragt `install.sh` im Terminal, ob es den Eintrag in die `~/.bashrc` schreiben soll (mit `--path` ohne Rückfrage; der Eintrag trägt einen Marker (`# bin-path`, derselbe wie bei remote-tools) und kommt nie doppelt). Ohne Terminal und ohne `--path` zeigt es nur die passende Zeile (`~/.profile` nimmt `~/bin` und `~/.local/bin` auf Debian/Ubuntu nur auf, wenn der Ordner beim Login schon existiert). Bindet die Datei, die bash beim Login liest (`~/.bash_profile`, sonst `~/.bash_login`, sonst `~/.profile`), die `~/.bashrc` nicht ein, schlägt `install.sh` (nach Rückfrage, mit `--path` ohne) die Zeile `[ -f ~/.bashrc ] && . ~/.bashrc` dort vor, sonst fehlt der PATH-Eintrag beim SSH-Login (typisch bei einem eigenen `.bash_profile`). Die Hilfsfunktionen dafür stehen in `lib/shell-setup.sh`, laufen ohne `realpath` und ergänzen nur. Ein erneuter Aufruf ist gefahrlos; existiert am Ziel schon etwas anderes (fremde Datei, Symlink woandershin), bricht `install.sh` ab und überschreibt nichts.

**Tab-Vervollständigung:** `install.sh` trägt außerdem eine Source-Zeile für `dbtools-completion.sh` in die `~/.bashrc` ein (Rückfrage im Terminal, mit `--path` ohne; kommt nie doppelt, erkennbar am Kommentar `# db-tools: Tab-Vervollständigung`). Danach vervollständigt `db-import <TAB>` und `db-export <TAB>` die Datenbank-Umgebungen (dazu die reservierten Wörter `ddev` bzw. `ddev`/`decrypt`, nur wo das Skript sie akzeptiert), `db-send <TAB>` und `db-fetch <TAB>` die Server, `--from`/`--env` die Umgebungen und `--out` Ordner. Die Namen werden erst beim Tab-Druck gelesen, nicht beim Shell-Start.

## Einrichtung

Alle Configs liegen im Ordner `conf/` (Vorlagen: `conf/db_template.conf`, `conf/remote_template.conf`, `conf/dbtools.conf.example`). Für jede Umgebung eine eigene Konfigurationsdatei anlegen, basierend auf `db_template.conf`:

```
cp conf/db_template.conf conf/db_dev.conf
```

Danach `conf/db_dev.conf` mit den passenden Zugangsdaten füllen:

```
DB_HOST=""
DB_USER=""
DB_PASS=""
DB_NAME=""
PREFIX="project-dev"
```

**Übergang Root → `conf/`:** Configs im Root des db-tools-Ordners (`db_<name>.conf`, `remote_<name>.conf`, `dbtools.conf`) werden weiter gefunden. Gesucht wird erst in `conf/`, dann im Root; gibt es dieselbe Datei an beiden Orten, gewinnt `conf/`. Bestehende Configs müssen nicht verschoben werden, wer will, verschiebt sie von Hand (`mv db_*.conf remote_*.conf dbtools.conf conf/`). Die Übersicht (siehe unten) markiert Root-Dateien, die zusätzlich in `conf/` liegen, als doppelt/veraltet.

Dateien nach dem Muster `db_*.conf` und `remote_*.conf` (außer den `*_template.conf`) werden von Git ignoriert, damit keine echten Zugangsdaten versehentlich veröffentlicht werden.

Optional können das Dump-Verzeichnis (Standard: `$HOME/sql-dumps`, gilt für Export und Import gleichermaßen), der Ordner für DDEV-Exporte (Standard: wie das Dump-Verzeichnis) und der Patch-Ordner für `--patch` (Standard: `$HOME/sql-patches`) über eine globale Konfigurationsdatei angepasst werden, basierend auf `conf/dbtools.conf.example` (auch `dbtools.conf` liegt in `conf/`, mit Root-Fallback wie die anderen):

```
cp conf/dbtools.conf.example conf/dbtools.conf
```

```
DUMP_DIR="$HOME/sql-dumps"
PATCH_DIR="$HOME/sql-patches"
DDEV_DUMP_DIR=""
```

Relative Pfade gelten relativ zum Ordner der Skripte.

`dbtools.conf` wird ebenfalls von Git ignoriert. Tilde (`~`) wird von Bash in Anführungszeichen nicht aufgelöst, stattdessen `$HOME` verwenden, z. B. `DUMP_DIR="$HOME/sqldumps"`.

### Configs anzeigen (`--configs`, `db-configs`)

Jeder Befehl hat die Option `--configs`, die die Configs zeigt, die er annimmt, und dann mit Exit 0 endet:

```
db-export --configs     db-import --configs     Datenbank-Umgebungen (db_*.conf)
db-send --configs       db-fetch --configs      Server (remote_*.conf)
db-configs                                      beides zusammen, mit Spalte "Art"
```

Die Tabelle zeigt Name, Ziel (bei Umgebungen DB-Host/Name und Präfix, bei Servern der SSH-Alias; **nie Passwörter**) und die Datei, die tatsächlich verwendet wird. Unvollständige Configs erscheinen mit Hinweis statt Daten, Root-Dateien, die auch in `conf/` liegen, mit dem Hinweis "doppelt/veraltet". Die Vorlagen werden nicht gelistet. Ein Aufruf von `db-export`, `db-import`, `db-send` oder `db-fetch` ganz ohne Parameter zeigt zur Hilfe auch diese Tabelle. (`--configs` ist eine Option und kollidiert deshalb nicht mit den reservierten Wörtern `ddev` und `decrypt` an Position 1.)

## Nutzung

### Export

```
./exportDB.sh dev
```

Erstellt einen komprimierten Dump im Dump-Verzeichnis (siehe oben).

#### Verschlüsselung

Vor dem Export fragt das Skript "Dump verschlüsseln? (y/N)". Im Terminal genügt dafür ein Tastendruck ohne Enter (Enter allein heißt `N`), bei umgeleiteter Eingabe (Pipe) wird wie bisher eine ganze Zeile gelesen. Bei `y` wird zweimal ein Passwort abgefragt und der Dump mit `gpg` symmetrisch (AES256, nur Passwort, kein Schlüssel) verschlüsselt. Die Datei bekommt die Endung `.gpg`, z. B. `project-dev-2026-09-20-14Uhr.sql.gz.gpg`.

Der Import erkennt verschlüsselte Dumps an der Endung `.gpg` und fragt das Passwort automatisch ab. Das Passwort wird vor der Sicherheitsabfrage geprüft, bei einem falschen Passwort bricht der Import ab, bevor die Datenbank angefasst wird. Das Passwort wird nie als Kommandozeilenargument übergeben (sonst wäre es per `ps` sichtbar).

`gpg` muss auf dem System installiert sein (ab GnuPG 2.1, wegen `--pinentry-mode loopback`). Für unverschlüsselte Dumps wird es nicht benötigt.

#### Automatisches Backup (Cron)

`backupAll.sh` sichert alle Umgebungen aus `BACKUP_ENVS` (Namen der `db_<name>.conf`, durch Leerzeichen getrennt) unverschlüsselt nach `BACKUP_DIR` (ohne Angabe: `DUMP_DIR`), beides in der `dbtools.conf`:

```
BACKUP_ENVS="live dev kunde2"
BACKUP_DIR="$HOME/backups"
```

```
0 2 * * * /pfad/zu/db-tools/backupAll.sh
```

- **Still bei Erfolg:** Das Skript gibt nichts aus, es gibt kein Log. Ob gesichert wurde, zeigt der Backup-Ordner.
- **Bei Fehlern:** Meldung auf stderr ("2 von 5 fehlgeschlagen: live, kunde2" plus die Ausgabe der betroffenen Exporte) und Exit 1. Ein fehlgeschlagener Export stoppt die übrigen nicht, unvollständige Dateien werden gelöscht.
- **Benachrichtigung:** Cron wertet den Exit-Code nicht aus, sondern schickt jede Ausgabe per Mail an `MAILTO` (in der Crontab setzen, der Server braucht dafür einen funktionierenden Mailversand). Weil das Skript nur bei Fehlern etwas ausgibt, kommt auch nur dann eine Mail.

Dafür versteht `exportDB.sh` zwei Optionen, die auch einzeln nutzbar sind: `--no-encrypt` (keine Rückfrage zur Verschlüsselung) und `--out <ordner>` (Zielordner, relativ zum aktuellen Ordner, hat Vorrang vor `DUMP_DIR`).

#### Export aus einem DDEV-Projekt

`ddev` ist ein fester, eingebauter Name für den Export des lokalen DDEV-Projekts im aktuellen Ordner. Es braucht keine Konfigurationsdatei, das Skript ruft `ddev export-db` auf:

```
cd ~/projekte/mein-ddev-projekt
db-export ddev                       # in den DDEV-Dump-Ordner
db-export ddev --out ~/anderer/ordner
db-export ddev --dry-run             # Befehl nur anzeigen
```

- **Dateiname:** wie beim normalen Export, mit `<projektname>-ddev` als PREFIX, z. B. `meinprojekt-ddev-2026-10-06-14Uhr.sql.gz`. Der Name kommt vom Projekt-Ordner: Vom aktuellen Ordner wird nach oben bis zur ersten `.ddev/config.yaml` gesucht, ihr Elternordner ist der Projekt-Root (der Aufruf funktioniert also auch aus Unterordnern wie `public/`). Der DDEV-Projektname selbst wird nicht verwendet, er kann vom Ordnernamen abweichen.
- **Ziel-Ordner:** `DDEV_DUMP_DIR` aus `dbtools.conf`, ist es nicht gesetzt, `DUMP_DIR`. `--out <ordner>` hat Vorrang, relative Pfade gelten dort relativ zum aktuellen Ordner. Einen Ordner als 2. Parameter gibt es nicht (Fehler mit Hinweis auf `--out`).
- **Verschlüsselung:** dieselbe Rückfrage wie oben, der Dump geht per Pipe direkt in `gpg`.
- **Befehl:** Vor dem Export wird der ausgeführte Befehl angezeigt. Mit `--dry-run` wird nur dieser Befehl ausgegeben (inklusive `mkdir -p`, falls der Ordner fehlt), zum Kopieren oder Anpassen. Bei Verschlüsselung fragt `gpg` das Passwort dann selbst ab.

Existiert eine Datei `db_ddev.conf`, bricht das Skript ab, weil sie ignoriert würde. `--dry-run` gibt es nur bei `ddev`.

### Import

```
./importDB.sh dev
```

Zeigt eine nach Datum sortierte Liste der Dumps der Zielumgebung (neuester zuerst, Nummer 1). Enter wählt die Nummer 1, also den neuesten Dump. Die Quell-Umgebung wird mit `--from` angegeben, eine konkrete Datei als 2. Parameter:

```
./importDB.sh update --from dev
./importDB.sh update dump.sql.gz
```

Der erste Aufruf zeigt die Liste der `dev`-Dumps und importiert die Auswahl in die `update`-Umgebung (Zugangsdaten bleiben die der Zielumgebung). Die Liste ist immer auf den PREFIX der Quelle gefiltert (`--from`, sonst die Zielumgebung).

Mit `--latest` wird ohne Liste direkt der neueste Dump genommen:

```
./importDB.sh update --from dev --latest
./importDB.sh dev --latest
```

Die alte Form `./importDB.sh update dev` (Quell-Umgebung als 2. Parameter) und das Wort `list` gibt es nicht mehr. Das Skript bricht mit einem Hinweis auf `--from` bzw. die Liste ab. Ein Dateiname zusammen mit `--from` oder `--latest` wird abgelehnt.

Vor jedem Import erfolgt eine Sicherheitsabfrage, da die Zieldatenbank überschrieben wird.

Wurde der Dump automatisch gewählt (`--latest`), lautet die Abfrage `(y/N/l)`. Mit `l` (und Enter) wird die Liste der Dumps dieser Quelle gezeigt (gleicher PREFIX, neueste zuerst), nach der Auswahl kommt die Sicherheitsabfrage erneut mit dem neuen Dateinamen. Ist der gewählte Dump verschlüsselt, wird sein Passwort abgefragt und geprüft. Bestätigt wird weiterhin mit `y` und Enter, nicht mit einem einzelnen Tastendruck. Bei der Auswahl aus der Liste oder einer direkt angegebenen Datei bleibt es bei `(y/N)`.

#### Kompletter Austausch der Datenbank

Ein Import tauscht die Zieldatenbank komplett aus: Vor dem Einspielen des Dumps werden alle Tabellen, Views und Sequenzen der Zieldatenbank gelöscht. Danach entspricht sie exakt dem Stand des Dumps. Ohne das Leeren blieben Tabellen erhalten, die nur in der Zieldatenbank existieren (z. B. von einer inzwischen entfernten Extension), weil ein Dump nur die Tabellen löscht und neu anlegt, die er selbst enthält.

Die Sicherheitsabfrage nennt die Anzahl der Tabellen/Views, die gelöscht werden. Sie werden schon vor der Abfrage ermittelt, ein Verbindungsfehler bricht also ab, bevor etwas passiert. Nach der Bestätigung wird die Liste noch einmal geholt, damit auch Tabellen erfasst werden, die in der Zwischenzeit entstanden sind. Gelöscht wird dann in derselben `mysql`-Sitzung direkt vor dem Dump. Der DB-User braucht dafür kein Recht auf `DROP DATABASE`.

Bricht der Import mittendrin ab (z. B. beschädigter Dump, Verbindungsabbruch), ist die Zieldatenbank leer oder nur teilweise befüllt. Vor einem Import auf `live` deshalb vorher ein Backup ziehen.

Gespeicherte Prozeduren, Funktionen und Events werden nicht gelöscht (sie sind auch nicht Teil des Exports).

#### Einzelne SQL-Befehle ausführen (`--patch`)

Mit `--patch` werden nur die Befehle aus einer SQL-Datei ausgeführt, z. B. ein paar `UPDATE`- oder `INSERT`-Befehle. Die Datenbank wird dabei nicht geleert:

```
./importDB.sh live aenderungen.sql --patch
./importDB.sh ddev aenderungen.sql.gz --patch
./importDB.sh stage --patch
```

Erlaubt sind `.sql`- und `.sql.gz`-Dateien, direkt angegeben (von überall) oder per Liste aus dem Patch-Ordner (Standard `$HOME/sql-patches`, siehe Einrichtung). Ohne Dateiname wird diese Liste gezeigt, nach Datum sortiert (neueste zuerst). Dumps liegen in einem eigenen Ordner und können deshalb nicht versehentlich aus der Liste gewählt werden. Mit `--from` oder `--latest` (`./importDB.sh stage --from live --patch`) bricht das Skript ab, weil damit ein kompletter Dump gemeint wäre. Verschlüsselte Dateien (`.sql.gz.gpg`) werden abgelehnt, sie vorher mit `./decryptDB.sh datei.sql.gz.gpg` entschlüsseln, das Ergebnis (`.sql.gz`) geht dann.

Vor der Sicherheitsabfrage wird der (entpackte) Inhalt der Datei angezeigt: bei mehr als 30 Zeilen nur die ersten 30 plus die Gesamtzahl, Zeilen mit mehr als 200 Zeichen werden abgeschnitten (`…`). Ist die Datei ein mysqldump (erkannt am Kopf `-- MySQL dump` bzw. `-- MariaDB dump`), erscheint zusätzlich ein Hinweis: Mit `--patch` werden nur die darin enthaltenen Tabellen ersetzt, alle anderen bleiben erhalten. Das ist erlaubt, z. B. um gezielt eine einzelne Tabelle zu ersetzen. Bei DDEV wird automatisch `ddev import-db --no-drop` verwendet, weil DDEV die Datenbank sonst vorher leert. Beim ersten fehlerhaften Befehl bricht `mysql` ab, die Befehle davor bleiben ausgeführt.

#### Parameter im Überblick

Der Import folgt der Aufrufkonvention (eine Position, eine Bedeutung): Position 1 ist das Ziel, Position 2 nur ein Dateiname, die Quell-Umgebung steht in `--from`. Bewusste Abweichung: `ddev` und `decrypt` sind echte Modi und bleiben reservierte Namen an der Umgebungs-Position (eigene Optionen oder Befehle brächten Aufwand ohne Gewinn im Alltag). Bei `exportDB.sh` gilt das für `ddev` genauso.

```
./importDB.sh <wohin> [datei] [--from <quelle>] [--latest] [--gunzip] [--patch] [--configs]
```

| Parameter | Bedeutung |
| --- | --- |
| 1. Parameter (wohin) | Ziel-Umgebung (`db_<name>.conf`) oder ein reservierter Name: `ddev` oder `decrypt` |
| 2. Parameter (datei) | Nichts: Liste der Dumps (Enter = Nr. 1, der neueste). Sonst ein Dateiname (`.sql`, `.sql.gz`, `.sql.gz.gpg`) |
| `--from <quelle>` | Quell-Umgebung: Liste bzw. `--latest` beziehen sich auf deren PREFIX (Standard: PREFIX der Ziel-Umgebung; bei `ddev` und `decrypt` alle Dumps). Nicht mit Dateiname oder `--patch` |
| `--latest` | Ohne Liste direkt den neuesten Dump nehmen. Bei `ddev` und `decrypt` nur mit `--from`. Nicht mit Dateiname oder `--patch` |
| `--gunzip` | Nur bei `decrypt`: zusätzlich entpacken. Beim normalen Import nur ein Hinweis, weil dort immer automatisch entpackt wird |
| `--patch` | Nur die Befehle einer SQL-Datei ausführen, ohne die Datenbank vorher zu leeren. Nur beim Import und nur mit einer `.sql`- oder `.sql.gz`-Datei als 2. Parameter (ohne Dateiname: Liste aus dem Patch-Ordner) |

Optionen mit `--` dürfen an beliebiger Stelle stehen. Unbekannte Optionen brechen das Skript ab.

#### Import in ein DDEV-Projekt

`ddev` ist ein fester, eingebauter Name für den Import in ein lokales DDEV-Projekt. Es braucht keine Konfigurationsdatei. Das Skript muss im Ordner des DDEV-Projekts ausgeführt werden (`ddev` erkennt das Projekt am aktuellen Ordner), der Pfad zum Skript ist beliebig:

```
cd ~/projekte/mein-ddev-projekt
~/scripts/db-tools/importDB.sh ddev --from dev
~/scripts/db-tools/importDB.sh ddev
~/scripts/db-tools/importDB.sh ddev dump.sql.gz
```

Ohne Dateiname und ohne `--from` wird die Liste aller Dumps gezeigt, weil es keinen eigenen PREFIX gibt (`--latest` braucht deshalb `--from`). Der Dump wird per Pipe an `ddev import-db` übergeben, verschlüsselte und komprimierte Dumps landen dabei nie unverschlüsselt oder entpackt auf der Platte. Existiert eine Datei `db_ddev.conf`, bricht das Skript ab, weil sie ignoriert würde.

Bei `ddev` werden beide Dump-Ordner durchsucht, `DDEV_DUMP_DIR` und `DUMP_DIR`, damit auch Dumps anderer Umgebungen (`./importDB.sh ddev --from stage`) gefunden werden. Als neuester Dump zählt das Datum über beide Ordner hinweg. Die Liste (und `l` bei der Sicherheitsabfrage) ist eine gemeinsame, nach Datum sortierte Liste. Sind die Ordner verschieden, stehen oben beide Pfade und hinter jedem Eintrag der Ordnername als Label (`[00_dumps]`). Haben beide Ordner denselben Namen, wird stattdessen der volle Pfad als Label gezeigt. Sind beide Ordner gleich, wird nur einmal gesucht und es gibt kein Label. Alle anderen Ziele sehen nur `DUMP_DIR`.

#### Dumps entschlüsseln

Mit `decrypt` (oder der Kurzform `decryptDB.sh`) wird ein Dump nur entschlüsselt, ohne ihn zu importieren. Das Ergebnis landet im aktuellen Ordner:

```
./decryptDB.sh                   # Dump aus Liste wählen, dump.sql.gz.gpg wird zu dump.sql.gz
./decryptDB.sh --gunzip          # zusätzlich entpackt: dump.sql
./decryptDB.sh --from dev --latest --gunzip
./decryptDB.sh pfad/dump.sql.gz.gpg
```

`./decryptDB.sh ...` ist gleichbedeutend mit `./importDB.sh decrypt ...`. Die Quelle ist ein Dateiname oder die Liste (ohne Angabe wird sie gezeigt, mit `--from` auf eine Umgebung gefiltert, mit `--from` und `--latest` direkt der neueste Dump). Existiert die Zieldatei schon, wird vor dem Überschreiben nachgefragt. Ein nicht verschlüsselter Dump wird ohne `--gunzip` mit einer Meldung abgelehnt, mit `--gunzip` wird er nur entpackt (ist er gar nicht komprimiert, z. B. eine `.sql`, gibt es nichts zu tun und das Skript meldet das). Die Ergebnisdatei ist nur für den Besitzer les- und schreibbar (Rechte 600), weil sie den Inhalt der Datenbank im Klartext enthält.

Standardmäßig bleibt die Datei komprimiert (`.sql.gz`), denn sie ist entpackt um ein Vielfaches größer und lässt sich direkt ansehen, ohne sie zu entpacken:

```
zless dump.sql.gz
zgrep "suchbegriff" dump.sql.gz
```

## Dateien zwischen Rechner und Server (`db-send`, `db-fetch`)

Die Tools arbeiten immer lokal auf Dateien. Um einen Dump auf einen anderen Server zu bringen (und dort mit den db-tools zu importieren) oder von dort zu holen, gibt es zwei Befehle. Sie kopieren per `scp` und importieren selbst nichts.

### Einrichtung eines Servers

Pro Server eine Datei `remote_<name>.conf` in `conf/`, basierend auf `conf/remote_template.conf`:

```
cp conf/remote_template.conf conf/remote_projekt-live.conf
```

```
SSH_HOST="projekt-live"
REMOTE_DUMP_DIR="sql-dumps"
REMOTE_PATCH_DIR="sql-patches"
```

`SSH_HOST` ist ein Alias aus der `~/.ssh/config` (dort stehen Host, User, Port und Key, in der `remote_*.conf` keine Zugangsdaten). Die beiden Ordner gelten relativ zum Home des SSH-Users auf dem Server oder absolut (keine Tilde). Standard, wenn nicht gesetzt: `sql-dumps` und `sql-patches`, passend zu den Standards `$HOME/sql-dumps` und `$HOME/sql-patches` der Tools. Fehlende Ordner werden auf dem Server angelegt.

Auf dem Server selbst liegen die db-tools nach der Regel für Server unter `~/scripts/db-tools/`. Welche DB-Configs dort liegen dürfen, hängt vom Schutzbedarf ab: Die Config der eigenen Umgebung und höchstens die der weniger schützenswerten (Live darf Stage kennen, Stage nie Live).

### Aufruf

```
db-send <server> [dateiname] [--env <umgebung>] [--patch] [--configs]
db-fetch <server> [dateiname] [--env <umgebung>] [--patch] [--configs]
```

```
db-send projekt-live                       Liste der lokalen Dumps (neueste zuerst), Auswahl, kopieren
db-send projekt-live dump.sql.gz           diese Datei (Pfad oder Name im Dump-Ordner)
db-send projekt-live --env live            Liste auf den PREFIX der Umgebung live eingrenzen
db-send projekt-live --patch               Liste der Patch-Dateien
db-send projekt-live fix.sql --patch       diesen Patch kopieren
db-fetch projekt-live                      Liste der Dumps auf dem Server, Auswahl, in den lokalen Dump-Ordner holen
db-fetch projekt-live --patch              dito mit Patch-Dateien (landen im lokalen Patch-Ordner)
```

- Ohne Dateiname kommt die Liste. Bei der Nummernabfrage wählt Enter die neueste Datei (Nummer 1).
- `--env` funktioniert nur für Dumps und nur mit Liste (nicht zusammen mit einem Dateinamen und nicht mit `--patch`).
- Vor dem Kopieren zeigt das Tool Datei, Größe und Ziel und fragt per Einzeltaste (y/N).
- Eine vorhandene Datei am Ziel wird nie überschrieben, das Tool bricht mit Meldung ab.
- Kopiert wird erst nach `<name>.part` und dann umbenannt, damit nie eine halbe Datei als Dump dasteht. Verschlüsselte Dumps (`.gpg`) werden unverändert kopiert; verschlüsselte Patches nimmt der Import nicht, deshalb auch `db-send` nicht.
- Dateinamen dürfen nur A-Z a-z 0-9 . _ + - enthalten (sie gehen in scp/ssh-Pfade ein).
- Für `db-fetch` muss auf dem Server GNU `find` vorhanden sein (Dateiliste).
- Die Aufrufform folgt einer festen Konvention für neue Befehle: Jede Position hat genau eine Bedeutung (Server zuerst, dann optional die Datei), Varianten und Filter sind Optionen (`--env`, `--patch`) und keine Positionsparameter mit wechselnder Bedeutung.

## SSH-Tunnel zur Datenbank

Ist die Datenbank eines Servers nicht direkt erreichbar (MySQL lauscht nur auf `localhost` des Servers oder die Firewall sperrt Port 3306), kann jede Umgebung ihre DB über einen SSH-Tunnel ansprechen. Das Tool öffnet den Tunnel beim Start, nutzt ihn für `mysql`/`mysqldump` und schließt ihn am Ende wieder (auch bei Abbruch). Export, Import und Backup verhalten sich sonst wie gewohnt.

In der `db_<umgebung>.conf` (nicht in der `remote_*.conf`, denn der Tunnel beschreibt den Weg zu einer Datenbank, nicht zu Dateien):

```
SSH_TUNNEL="projekt-live"
TUNNEL_PORT="3307"
TUNNEL_REMOTE="127.0.0.1:3306"
```

- `SSH_TUNNEL`: SSH-Alias aus der `~/.ssh/config` (derselbe Alias wie in der `remote_*.conf` ist möglich). Ohne diese Zeile gibt es keinen Tunnel.
- `TUNNEL_PORT`: lokaler Port, Standard `3307`. Läuft schon etwas auf dem Port (z. B. ein zweiter Tunnel, DDEV), einen anderen wählen.
- `TUNNEL_REMOTE`: DB-Host und Port, **vom Server aus gesehen**. Standard `127.0.0.1:3306`.
- `DB_HOST` der Config gilt mit Tunnel nicht, das Tool verbindet sich mit `127.0.0.1:TUNNEL_PORT`. `DB_USER`, `DB_PASS` und `DB_NAME` bleiben wie sonst.
- Unabhängig vom Tunnel gibt es `DB_PORT` für eine DB auf einem anderen Port (wird als `-P` an `mysql`/`mysqldump` übergeben).

Manuell entspricht das:

```
ssh -N -L 3307:127.0.0.1:3306 projekt-live
```

Beispiel für `~/.ssh/config`:

```
Host projekt-live
    HostName server.example.org
    User deploy
    IdentityFile ~/.ssh/id_ed25519_projekt
    IdentitiesOnly yes
```

Mit einem Key mit Passphrase und `ssh-agent` wird die Passphrase einmal pro Sitzung abgefragt (`ssh-add ~/.ssh/id_ed25519_projekt`), danach laufen alle Aufrufe ohne Eingabe. Ohne Agent fragt `ssh` bei jedem Tool-Start. Das Passwort der Datenbank bleibt dabei lokal in der `db_*.conf`; ohne den SSH-Key ist es wertlos, solange die DB nicht von außen erreichbar ist. Für `backupAll.sh` per Cron geht ein Tunnel nur, wenn der Key ohne Passphrase-Abfrage nutzbar ist (Agent oder eigener, eingeschränkter Backup-Key).

## Tests

```
tests/run.sh
```

Startet alle Tests in `tests/`. Sie brauchen keine echte Datenbank: `mysql`, `mysqldump`, `ddev`, `ssh` und `scp` werden durch Stubs in `tests/stubs` ersetzt, gearbeitet wird in einem temporären Ordner. Benötigt werden `gpg`, `gzip`, `setsid` und `pgrep`. Ein Test schickt Signale an eine Prozessgruppe, deshalb nicht in einer Umgebung ohne Prozesssteuerung ausführen.

## Offene Punkte

- **Verschlüsselter Export nur interaktiv:** Die Rückfrage "Dump verschlüsseln?" und die Passwortabfrage brauchen ein Terminal, ein Einsatz per Cron ist derzeit nicht möglich. Vorschlag für die Automatisierung: ein Schlüsselwort `encrypt`, das die y/N-Rückfrage überspringt, plus eine Passwortquelle ohne Tastatur, z. B. `DB_DUMP_PASSFILE` in `dbtools.conf` (Datei mit Rechten 600), deren Inhalt per `--passphrase-file` an gpg übergeben wird.
- **Abbruch des Exports:** Der Aufräum-Trap im Export greift sofort bei Ctrl+C. Ein gezieltes `kill <pid>` nur auf das Skript (ohne Prozessgruppe) wirkt erst nach dem Ende des Dumps. Ein geschlossenes Terminal (SIGHUP) wird nicht behandelt.
