#!/bin/bash
# Führt alle Tests in tests/ aus. Braucht gpg, setsid und pgrep, aber keine echte Datenbank.
# Nutzung: tests/run.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for tool in gpg setsid pgrep gzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Fehler: '$tool' wird für die Tests benötigt!"
        exit 1
    fi
done

FAILED=0
for test in "$DIR"/test_*.sh; do
    echo "=== $(basename "$test")"
    # gzip/gpg-Fehlerausgaben aus absichtlich kaputten Dumps sind erwartet und werden ausgeblendet
    OUTPUT=$(bash "$test" 2>&1)
    echo "$OUTPUT" | grep -E '^(PASS|FAIL):'
    if echo "$OUTPUT" | grep -q '^FAIL:'; then
        FAILED=1
    fi
done

if [ "$FAILED" -eq 0 ]; then
    echo "Alle Tests bestanden."
else
    echo "Es gab fehlgeschlagene Tests."
    exit 1
fi
