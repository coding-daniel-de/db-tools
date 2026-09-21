#!/bin/bash

# Kurzform für "importDB.sh decrypt": Dump nur entschlüsseln (und mit --gunzip entpacken).
# Nutzung: ./decryptDB.sh [quell-umgebung | dateiname | list] [--gunzip]

# Ordner des Skripts über den echten Pfad ermitteln (auch wenn es per Symlink aufgerufen wird)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

exec "${SCRIPT_DIR}/importDB.sh" decrypt "$@"
