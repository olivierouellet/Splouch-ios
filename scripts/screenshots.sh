#!/bin/sh
# Captures the screenshots in Screenshots/: every screen, in English, French and
# Spanish, light and dark, on the two App Store sizes (6.9" iPhone, 13" iPad).
#
#   scripts/screenshots.sh [pi] [cloud]
#   LANGS=es scripts/screenshots.sh     # recapture one language only
#
# The meet screens come from a local Pi (default http://127.0.0.1:5056) playing a
# recording, so the board and results carry real names and times; start it first:
#   cd ../Splouch/server && uv run uvicorn app:app --port 5056
#   log in (score / swimming) and POST /test_play a recording that holds heat 1's
#   finish: the stock 200m_medley_2heats.serial clears the board when it ends, so
#   cut it after heat 1 (line 1889) and repeat that last line an hour later:
#     R=../Splouch/server/console_recordings/200m_medley_2heats; H=~/SplouchData/recorded/hold
#     { sed -n 1,1889p $R.serial; sed -n 1889p $R.serial | sed 's/^\[1700000178/[1700003778/'; } > $H.serial
#     cp $R.lxf $H.lxf      # then POST /test_play {"name": "hold.serial"}
#   and run this once heat 1 has finished (about 3 min in).
# The picker comes from the cloud (default https://splouch.ca), which lists meets
# with their images; a Pi opens straight into its own meet.
#
# Needs a Debug build (it reads SPLOUCH_SERVER / SPLOUCH_TAB):
#   xcodebuild -project App/Splouch.xcodeproj -scheme Splouch \
#     -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
#
# Language and appearance are set by writing the app's own stored preferences
# (`splouch.preferences`, see Preferences.swift) before each launch, and the
# device language with -AppleLanguages so native strings follow.
set -eu

PI=${1:-http://127.0.0.1:5056}
CLOUD=${2:-https://splouch.ca}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/.build/xcode/Build/Products/Debug-iphonesimulator/Splouch.app"
OUT="$ROOT/Screenshots"
BUNDLE=app.splouch.ios
WAIT=${WAIT:-8}
LANGS=${LANGS:-en fr es}

udid() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | sed 's/.*(\([0-9A-F-]*\)).*/\1/'; }

capture() { # device-name folder
  D=$(udid "$1")
  xcrun simctl boot "$D" 2>/dev/null || true
  xcrun simctl bootstatus "$D" -b >/dev/null
  xcrun simctl status_bar "$D" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl uninstall "$D" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$D" "$APP"
  for lang in $LANGS; do
    for theme in light dark; do
      xcrun simctl ui "$D" appearance "$theme"
      dir="$OUT/$2/$lang/$theme"
      mkdir -p "$dir"
      prefs=$(printf '{"language":"%s","labelStyle":"long","appearance":"%s","savedServers":[]}' "$lang" "$theme" | xxd -p | tr -d '\n')
      i=1
      for screen in picker scoreboard results schedule; do
        xcrun simctl terminate "$D" "$BUNDLE" 2>/dev/null || true
        xcrun simctl spawn "$D" defaults write "$BUNDLE" splouch.preferences -data "$prefs"
        if [ "$screen" = picker ]; then
          SIMCTL_CHILD_SPLOUCH_SERVER=$CLOUD \
            xcrun simctl launch "$D" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "${lang}_CA" >/dev/null
        else
          SIMCTL_CHILD_SPLOUCH_SERVER=$PI SIMCTL_CHILD_SPLOUCH_TAB=$screen \
            xcrun simctl launch "$D" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "${lang}_CA" >/dev/null
        fi
        sleep "$WAIT"
        xcrun simctl io "$D" screenshot --type=png "$dir/$i-$screen.png" >/dev/null 2>&1
        echo "$2/$lang/$theme/$i-$screen.png"
        i=$((i + 1))
      done
    done
  done
  xcrun simctl terminate "$D" "$BUNDLE" 2>/dev/null || true
  xcrun simctl status_bar "$D" clear
}

capture "iPhone 17 Pro Max" iphone-6.9
capture "iPad Pro 13-inch (M5)" ipad-13

# App Store Connect refuses images with an alpha channel; the simulator's PNGs
# carry one, so every capture is flattened.
uv run --quiet --with pillow python - "$OUT" <<'PY'
import sys, pathlib
from PIL import Image
for p in pathlib.Path(sys.argv[1]).rglob("*.png"):
    im = Image.open(p)
    if im.mode != "RGB":
        im.convert("RGB").save(p, optimize=True)
PY

# The App Store set: the dark captures (the app's default appearance) per
# listing language (Spanish lists as es-MX, the North American Spanish store).
# Rebuilt from every language on disk, so a LANGS=es run keeps en and fr. No
# marketing icon: App Store Connect takes it from the build's AppIcon.icon, and
# ictool only renders it pre-masked.
STORE="$OUT/AppStore"
rm -rf "$STORE"
for listing in en-CA fr-CA es-MX; do
  lang=${listing%-*}
  for dev in iphone-6.9 ipad-13; do
    [ -d "$OUT/$dev/$lang/dark" ] || continue
    mkdir -p "$STORE/$listing/$dev"
    cp "$OUT/$dev/$lang/dark/"*.png "$STORE/$listing/$dev/"
  done
done
