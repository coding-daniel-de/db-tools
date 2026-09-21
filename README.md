# db-tools

Kleine Shell-Skripte zum Exportieren und Importieren von MySQL/MariaDB-Datenbanken über verschiedene Umgebungen hinweg (z. B. dev, update, live).

## Einrichtung

Für jede Umgebung eine eigene Konfigurationsdatei anlegen, basierend auf `db_template.conf`:

```
cp db_template.conf db_dev.conf
```

Danach `db_dev.conf` mit den passenden Zugangsdaten füllen:

```
DB_HOST=""
DB_USER=""
DB_PASS=""
DB_NAME=""
PREFIX="project-dev"
```

Dateien nach dem Muster `db_*.conf` (außer `db_template.conf`) werden von Git ignoriert, damit keine echten Zugangsdaten versehentlich veröffentlicht werden.

Optional kann das Dump-Verzeichnis (Standard: `../sql-dumps`, gilt für Export und Import gleichermaßen) über eine globale Konfigurationsdatei angepasst werden, basierend auf `dbtools.conf.example`:

```
cp dbtools.conf.example dbtools.conf
```

```
DUMP_DIR="../sql-dumps"
```

`dbtools.conf` wird ebenfalls von Git ignoriert. Tilde (`~`) wird von Bash in Anführungszeichen nicht aufgelöst, stattdessen `$HOME` verwenden, z. B. `DUMP_DIR="$HOME/sqldumps"`.

## Nutzung

### Export

```
./exportDB.sh dev
```

Erstellt einen komprimierten Dump im Dump-Verzeichnis (siehe oben).

#### Verschlüsselung

Vor dem Export fragt das Skript "Dump verschlüsseln? (y/N)". Bei `y` wird zweimal ein Passwort abgefragt und der Dump mit `gpg` symmetrisch (AES256, nur Passwort, kein Schlüssel) verschlüsselt. Die Datei bekommt die Endung `.gpg`, z. B. `project-dev-2026-09-20-14Uhr.sql.gz.gpg`.

Der Import erkennt verschlüsselte Dumps an der Endung `.gpg` und fragt das Passwort automatisch ab. Das Passwort wird vor der Sicherheitsabfrage geprüft, bei einem falschen Passwort bricht der Import ab, bevor die Datenbank angefasst wird. Das Passwort wird nie als Kommandozeilenargument übergeben (sonst wäre es per `ps` sichtbar).

`gpg` muss auf dem System installiert sein (ab GnuPG 2.1, wegen `--pinentry-mode loopback`). Für unverschlüsselte Dumps wird es nicht benötigt.

### Import

```
./importDB.sh dev
```

Importiert den neuesten Dump der Zielumgebung. Optional kann eine konkrete Datei oder eine Quell-Umgebung angegeben werden:

```
./importDB.sh update dev
```

Importiert den neuesten `dev`-Dump in die `update`-Umgebung (Zugangsdaten bleiben die der Zielumgebung).

Alternativ kann mit `list` eine nach Datum sortierte Auswahl aller Dumps im Dump-Verzeichnis angezeigt werden (neuester zuerst, Nummer 1):

```
./importDB.sh update list
```

Vor jedem Import erfolgt eine Sicherheitsabfrage, da die Zieldatenbank überschrieben wird.

#### Parameter im Überblick

```
./importDB.sh <wohin> [woher] [--gunzip]
```

| Parameter | Bedeutung |
| --- | --- |
| 1. Parameter (wohin) | Ziel-Umgebung (`db_<name>.conf`) oder ein reservierter Name: `ddev` oder `decrypt` |
| 2. Parameter (woher) | Nichts: neuester Dump der Ziel-Umgebung (bei `ddev` und `decrypt` stattdessen die Liste). Sonst eine Quell-Umgebung, ein Dateiname (`.sql`, `.sql.gz`, `.sql.gz.gpg`) oder `list` |
| `--gunzip` | Nur bei `decrypt`: zusätzlich entpacken. Beim normalen Import nur ein Hinweis, weil dort immer automatisch entpackt wird |

Optionen mit `--` dürfen an beliebiger Stelle stehen. Unbekannte Optionen brechen das Skript ab.

#### Import in ein DDEV-Projekt

`ddev` ist ein fester, eingebauter Name für den Import in ein lokales DDEV-Projekt. Es braucht keine Konfigurationsdatei. Das Skript muss im Ordner des DDEV-Projekts ausgeführt werden (`ddev` erkennt das Projekt am aktuellen Ordner), der Pfad zum Skript ist beliebig:

```
cd ~/projekte/mein-ddev-projekt
~/scripts/db-tools/importDB.sh ddev dev
~/scripts/db-tools/importDB.sh ddev list
~/scripts/db-tools/importDB.sh ddev dump.sql.gz
```

Ohne zweiten Parameter wird die Liste aller Dumps gezeigt, weil es keinen eigenen PREFIX gibt. Der Dump wird per Pipe an `ddev import-db` übergeben, verschlüsselte und komprimierte Dumps landen dabei nie unverschlüsselt oder entpackt auf der Platte. Existiert eine Datei `db_ddev.conf`, bricht das Skript ab, weil sie ignoriert würde.

#### Dumps entschlüsseln

Mit `decrypt` (oder der Kurzform `decryptDB.sh`) wird ein Dump nur entschlüsselt, ohne ihn zu importieren. Das Ergebnis landet im aktuellen Ordner:

```
./decryptDB.sh list              # dump.sql.gz.gpg wird zu dump.sql.gz
./decryptDB.sh list --gunzip     # zusätzlich entpackt: dump.sql
./decryptDB.sh dev --gunzip
./decryptDB.sh pfad/dump.sql.gz.gpg
```

`./decryptDB.sh ...` ist gleichbedeutend mit `./importDB.sh decrypt ...`. Die Quelle ist eine Quell-Umgebung, ein Dateiname oder `list` (ohne Angabe wird `list` gezeigt). Existiert die Zieldatei schon, wird vor dem Überschreiben nachgefragt. Ein nicht verschlüsselter Dump wird ohne `--gunzip` mit einer Meldung abgelehnt, mit `--gunzip` wird er nur entpackt (ist er gar nicht komprimiert, z. B. eine `.sql`, gibt es nichts zu tun und das Skript meldet das). Die Ergebnisdatei ist nur für den Besitzer les- und schreibbar (Rechte 600), weil sie den Inhalt der Datenbank im Klartext enthält.

Standardmäßig bleibt die Datei komprimiert (`.sql.gz`), denn sie ist entpackt um ein Vielfaches größer und lässt sich direkt ansehen, ohne sie zu entpacken:

```
zless dump.sql.gz
zgrep "suchbegriff" dump.sql.gz
```

## Tests

```
tests/run.sh
```

Startet alle Tests in `tests/`. Sie brauchen keine echte Datenbank: `mysql`, `mysqldump` und `ddev` werden durch Stubs in `tests/stubs` ersetzt, gearbeitet wird in einem temporären Ordner. Benötigt werden `gpg`, `gzip`, `setsid` und `pgrep`. Ein Test schickt Signale an eine Prozessgruppe, deshalb nicht in einer Umgebung ohne Prozesssteuerung ausführen.

## Offene Punkte

- **Verschlüsselter Export nur interaktiv:** Die Rückfrage "Dump verschlüsseln?" und die Passwortabfrage brauchen ein Terminal, ein Einsatz per Cron ist derzeit nicht möglich. Vorschlag für die Automatisierung: ein Schlüsselwort `encrypt`, das die y/N-Rückfrage überspringt, plus eine Passwortquelle ohne Tastatur, z. B. `DB_DUMP_PASSFILE` in `dbtools.conf` (Datei mit Rechten 600), deren Inhalt per `--passphrase-file` an gpg übergeben wird.
- **Abbruch des Exports:** Der Aufräum-Trap im Export greift sofort bei Ctrl+C. Ein gezieltes `kill <pid>` nur auf das Skript (ohne Prozessgruppe) wirkt erst nach dem Ende des Dumps. Ein geschlossenes Terminal (SIGHUP) wird nicht behandelt.
- **Export aus DDEV:** Er geschieht über `ddev export-db` und ist nicht Teil dieser Tools.
