#!/bin/zsh
# Regenerates the built-in string snapshot (app.md T-10) from a running server.
#
#   scripts/update-strings.sh https://splouch.ca
#
# Fetches GET /locales, then GET /i18n/{lang} for each language, and writes each
# body verbatim to Sources/SplouchCore/Resources/i18n/<lang>.json. Run it before
# a release and whenever the server's shared/locales/ changes. Never edit the
# files by hand: the server is the source, this is a captured floor.
set -euo pipefail
BASE=${1:?usage: update-strings.sh <server base url>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/Sources/SplouchCore/Resources/i18n
BASE=${BASE%/}
mkdir -p "$OUT"

codes=$(curl -sfS "$BASE/locales" | python3 -c 'import json,sys; print(" ".join(sorted(e["code"] for e in json.load(sys.stdin))))')
[[ -n "$codes" ]] || { echo "no locales from $BASE" >&2; exit 1 }

rm -f "$OUT"/*.json(N)
for code in ${=codes}; do
    curl -sfS "$BASE/i18n/$code" -o "$OUT/$code.json"
    python3 -c "import json; json.load(open('$OUT/$code.json'))"   # must be JSON
done
echo "wrote $OUT for: $codes (from $BASE on $(date -u +%Y-%m-%dT%H:%MZ))"
