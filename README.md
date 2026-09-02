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

### Import

```
./importDB.sh dev
```

Importiert den neuesten Dump der Zielumgebung. Optional kann eine konkrete Datei oder eine Quell-Umgebung angegeben werden:

```
./importDB.sh update dev
```

Importiert den neuesten `dev`-Dump in die `update`-Umgebung (Zugangsdaten bleiben die der Zielumgebung).

Vor jedem Import erfolgt eine Sicherheitsabfrage, da die Zieldatenbank überschrieben wird.
