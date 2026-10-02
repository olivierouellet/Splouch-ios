#!/bin/sh
# Archives a Release build for App Store Connect into .build/Splouch.xcarchive.
#
#   scripts/archive.sh
#
# The build number (CFBundleVersion) is the commit count on HEAD. It goes up with
# every commit, which is what App Store Connect needs on each upload, so nothing
# has to be bumped or committed. The marketing version (CFBundleShortVersionString)
# is MARKETING_VERSION in the project and follows the release tags: v2026.09.0
# means 2026.9.0. If HEAD is tagged and the two differ, this stops.
#
# Then upload from Xcode's Organizer (Window > Organizer > Distribute App).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT="$ROOT/App/Splouch.xcodeproj"
ARCHIVE="$ROOT/.build/Splouch.xcarchive"

if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = true ]; then
  echo "Shallow clone: the commit count would be wrong. Run git fetch --unshallow." >&2
  exit 1
fi
BUILD=$(git -C "$ROOT" rev-list --count HEAD)
VERSION=$(xcodebuild -project "$PROJECT" -scheme Splouch -configuration Release \
  -showBuildSettings 2>/dev/null | sed -n 's/^ *MARKETING_VERSION = //p' | head -1)

if TAG=$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null); then
  # v2026.09.0 -> 2026.9.0
  TAGGED=$(echo "${TAG#v}" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 }')
  if [ "$TAGGED" != "$VERSION" ]; then
    echo "HEAD is tagged $TAG but MARKETING_VERSION is $VERSION." >&2
    exit 1
  fi
fi

echo "Archiving Splouch $VERSION ($BUILD)"
xcodebuild archive -project "$PROJECT" -scheme Splouch -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD"
echo "$ARCHIVE"
