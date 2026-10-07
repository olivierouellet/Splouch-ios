#!/bin/sh
# Captures the screenshots in Screenshots/: every screen, in English, French and
# Spanish, light and dark, on the App Store sizes (6.9" and 6.3" iPhone, 13" iPad).
#
#   scripts/screenshots.sh [server] [meet-name]
#   LANGS=es scripts/screenshots.sh     # recapture one language only
#   DEVICES=iphone-6.3 scripts/screenshots.sh   # or one size only
#
# Every screen comes from the live server (default https://splouch.org): the
# picker lists its meets with their images, and the meet screens open the meet
# named by the second argument (default Dolphins, one of the test meets the
# server replays around the clock, so its board is mid-race and its results
# and schedule carry real names and times).
#
# Needs a Debug build (it reads SPLOUCH_SERVER / SPLOUCH_MEET / SPLOUCH_TAB):
#   xcodebuild -project App/Splouch.xcodeproj -scheme Splouch \
#     -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
#
# Language and appearance are set by writing the app's own stored preferences
# (`splouch.preferences`, see Preferences.swift) before each launch, and the
# device language with -AppleLanguages so native strings follow.
set -eu

SERVER=${1:-https://splouch.org}
MEET_NAME=${2:-Dolphins}
MEET=$(curl -fsS "$SERVER/meets" | python3 -c 'import json, sys
print(next(m["id"] for m in json.load(sys.stdin)["meets"] if m["name"] == sys.argv[1]))' "$MEET_NAME")
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/.build/xcode/Build/Products/Debug-iphonesimulator/Splouch.app"
OUT="$ROOT/Screenshots"
BUNDLE=app.splouch.ios
WAIT=${WAIT:-8}
LANGS=${LANGS:-en fr es}
DEVICES=${DEVICES:-iphone-6.9 iphone-6.3 ipad-13}

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
      prefs=$(printf '{"language":"%s","labelStyle":"long","appearance":"%s","savedServers":[],"introSeen":true}' "$lang" "$theme" | xxd -p | tr -d '\n')
      i=1
      for screen in picker scoreboard results schedule; do
        xcrun simctl terminate "$D" "$BUNDLE" 2>/dev/null || true
        xcrun simctl spawn "$D" defaults write "$BUNDLE" splouch.preferences -data "$prefs"
        if [ "$screen" = picker ]; then
          SIMCTL_CHILD_SPLOUCH_SERVER=$SERVER \
            xcrun simctl launch "$D" "$BUNDLE" -AppleLanguages "($lang)" -AppleLocale "${lang}_CA" >/dev/null
        else
          SIMCTL_CHILD_SPLOUCH_SERVER=$SERVER SIMCTL_CHILD_SPLOUCH_MEET=$MEET SIMCTL_CHILD_SPLOUCH_TAB=$screen \
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

for dev in $DEVICES; do
  case $dev in
    iphone-6.9) capture "iPhone 17 Pro Max" "$dev" ;;
    iphone-6.3) capture "iPhone 17 Pro" "$dev" ;;
    ipad-13) capture "iPad Pro 13-inch (M5)" "$dev" ;;
  esac
done

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
  for dev in iphone-6.9 iphone-6.3 ipad-13; do
    [ -d "$OUT/$dev/$lang/dark" ] || continue
    mkdir -p "$STORE/$listing/$dev"
    cp "$OUT/$dev/$lang/dark/"*.png "$STORE/$listing/$dev/"
  done
done
