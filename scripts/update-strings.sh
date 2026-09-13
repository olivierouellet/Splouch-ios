#!/bin/zsh
# Regenerates the built-in string snapshot (app.md T-10) from a running server.
#
#   scripts/update-strings.sh https://splouch.ca
#
# Fetches GET /locales (kept verbatim as Resources/i18n/locales.json, the
# offline floor of the language menu — app.md T-08), then GET /i18n/{lang} for
# each language, written verbatim to Resources/i18n/<lang>.json. Run it before a
# release and whenever the server's shared/locales/ changes. Never edit the
# files by hand: the server is the source, this is a captured floor.
set -euo pipefail
BASE=${1:?usage: update-strings.sh <server base url>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/Sources/SplouchCore/Resources/i18n
BASE=${BASE%/}
mkdir -p "$OUT"

curl -sfS "$BASE/locales" -o "$OUT/locales.json.new"
codes=$(python3 -c 'import json,sys; print(" ".join(sorted(e["code"] for e in json.load(open(sys.argv[1])))))' "$OUT/locales.json.new")
[[ -n "$codes" ]] || { rm -f "$OUT/locales.json.new"; echo "no locales from $BASE" >&2; exit 1 }

rm -f "$OUT"/*.json(N)
mv "$OUT/locales.json.new" "$OUT/locales.json"
for code in ${=codes}; do
    curl -sfS "$BASE/i18n/$code" -o "$OUT/$code.json"
    python3 -c "import json; json.load(open('$OUT/$code.json'))"   # must be JSON
done
echo "wrote $OUT for: $codes (from $BASE on $(date -u +%Y-%m-%dT%H:%MZ))"
