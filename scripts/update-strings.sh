#!/bin/zsh
# Regenerates the built-in string snapshot (app.md T-10) from a running server.
#
#   scripts/update-strings.sh https://splouch.ca
#   scripts/update-strings.sh --check https://splouch.ca     # what CI runs
#
# Fetches GET /locales (kept verbatim as Resources/i18n/locales.json, the
# offline floor of the language menu — app.md T-08), then GET /i18n/{lang} for
# each language, written verbatim to Resources/i18n/<lang>.json. Run it before a
# release and whenever the server's shared/locales/ changes. Never edit the
# files by hand: the server is the source, this is a captured floor.
#
# --check writes nothing: it captures, compares with the committed snapshot and
# exits 1 with the keys that differ. CI runs it so a snapshot cannot quietly ship
# English where the server now has a word.
set -euo pipefail
CHECK=0
if [[ ${1:-} == --check ]]; then CHECK=1; shift; fi
BASE=${1:?usage: update-strings.sh [--check] <server base url>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/Sources/SplouchCore/Resources/i18n
BASE=${BASE%/}

# Captured into a scratch directory first, either way: a fetch that fails halfway
# must not leave the snapshot half old and half new.
NEW=$(mktemp -d)
trap 'rm -rf "$NEW"' EXIT

curl -sfS "$BASE/locales" -o "$NEW/locales.json"
codes=$(python3 -c 'import json,sys; print(" ".join(sorted(e["code"] for e in json.load(open(sys.argv[1])))))' "$NEW/locales.json")
[[ -n "$codes" ]] || { echo "no locales from $BASE" >&2; exit 1 }
for code in ${=codes}; do
    curl -sfS "$BASE/i18n/$code" -o "$NEW/$code.json"
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$NEW/$code.json"   # must be JSON
done

if (( CHECK )); then
    # What CI runs. Byte for byte, because the files are written verbatim and the
    # server serialises with sorted keys, so any difference is a real one.
    if diff -r "$OUT" "$NEW" >/dev/null; then
        echo "snapshot matches $BASE for: $codes"
        exit 0
    fi
    echo "::error::the strings snapshot in $OUT is out of date with $BASE" >&2
    python3 - "$OUT" "$NEW" <<'PY' >&2
import json, os, sys
old, new = sys.argv[1], sys.argv[2]
def flat(d, p=""):
    out = {}
    for k, v in d.items():
        if isinstance(v, dict):
            out.update(flat(v, f"{p}{k}."))
        else:
            out[f"{p}{k}"] = v
    return out
for name in sorted(set(os.listdir(old)) | set(os.listdir(new))):
    if not name.endswith(".json") or name == "locales.json":
        continue
    a = flat(json.load(open(os.path.join(old, name)))) if os.path.exists(os.path.join(old, name)) else {}
    b = flat(json.load(open(os.path.join(new, name)))) if os.path.exists(os.path.join(new, name)) else {}
    for k in sorted(set(a) | set(b)):
        if a.get(k) != b.get(k):
            print(f"  {name} {k}: {a.get(k)!r} -> {b.get(k)!r}")
PY
    diff -q "$OUT/locales.json" "$NEW/locales.json" >/dev/null || echo "  locales.json differs" >&2
    echo "Run scripts/update-strings.sh $BASE and commit the result." >&2
    exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.json(N)
cp "$NEW"/*.json "$OUT"/
echo "wrote $OUT for: $codes (from $BASE on $(date -u +%Y-%m-%dT%H:%MZ))"
