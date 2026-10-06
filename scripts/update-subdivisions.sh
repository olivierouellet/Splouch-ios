#!/bin/zsh
# Keeps the bundled state/province names (app.md P-01, P-21) a verbatim copy of the
# server repo's shared/regions/subdivisions.json, the one file every client names
# subdivisions from. Never edit the copy by hand: edit the server repo's, then run this.
#
#   scripts/update-subdivisions.sh                  # from the server repo on GitHub
#   scripts/update-subdivisions.sh ../Splouch       # from a local checkout
#   scripts/update-subdivisions.sh --check          # what CI runs; writes nothing
#
# --check exits 1 when the copy differs, so the apps cannot quietly name a province
# the server repo has renamed, or miss one it has added.
set -euo pipefail
CHECK=0
if [[ ${1:-} == --check ]]; then CHECK=1; shift; fi
SRC=${1:-https://raw.githubusercontent.com/olivierouellet/Splouch/master}
SRC=${SRC%/}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/Sources/SplouchCore/Resources/subdivisions.json
REL=shared/regions/subdivisions.json

NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT
if [[ $SRC == http://* || $SRC == https://* ]]; then
    curl -sfS --retry 3 --retry-delay 5 --retry-all-errors "$SRC/$REL" -o "$NEW"
else
    cp "$SRC/$REL" "$NEW"
fi
python3 -c 'import json,sys; json.load(open(sys.argv[1]))["countries"]' "$NEW"   # must be the table

if (( CHECK )); then
    if cmp -s "$OUT" "$NEW"; then
        echo "subdivisions match $SRC/$REL"
        exit 0
    fi
    echo "::error::$OUT is out of date with $SRC/$REL" >&2
    diff -u "$OUT" "$NEW" >&2 || true
    echo "Run scripts/update-subdivisions.sh and commit the result." >&2
    exit 1
fi

cp "$NEW" "$OUT"
echo "wrote $OUT from $SRC/$REL"
