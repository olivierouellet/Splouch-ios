#!/bin/sh
# Releases the version on main, then moves main to the next one.
#
#   scripts/release.sh            # release HEAD
#   scripts/release.sh --dry-run  # say what it would do, change nothing
#
# Run it once the build on HEAD is the one sent to the App Store. It
#   1. checks that HEAD is main, clean, in step with GitHub, green on every
#      check (Xcode Cloud's archive included), and that its version is not
#      tagged yet;
#   2. tags HEAD v<version>, two-digit month (2026.9.0 -> v2026.09.0);
#   3. moves MARKETING_VERSION to the next version, the next patch in the same
#      month or <year>.<month>.0 in a new one, as "[Build] Version <next>";
#   4. pushes the tag and that commit together, and opens a draft GitHub
#      release for the notes.
#
# main is then never on a released version, so the next push archives the next
# version instead of one App Store Connect has closed.
set -eu

DRY_RUN=false
case "${1-}" in
  "") ;;
  --dry-run) DRY_RUN=true ;;
  *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 2 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PBXPROJ=App/Splouch.xcodeproj/project.pbxproj

fail() { echo "$*" >&2; exit 1; }

[ "$(git branch --show-current)" = main ] || fail "Not on main."
[ -z "$(git status --porcelain)" ] || fail "Uncommitted changes: commit or stash them first."
git fetch --quiet --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
  fail "main is not in step with origin/main: pull or push first."
SHA=$(git rev-parse HEAD)

# Both build configurations carry the version; they must agree.
VERSION=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);$/\1/p' "$PBXPROJ" | sort -u)
[ "$(echo "$VERSION" | wc -l | tr -d ' ')" = 1 ] || fail "MARKETING_VERSION differs between configurations: $VERSION"
echo "$VERSION" | grep -Eq '^[0-9]{4}\.[0-9]{1,2}\.[0-9]+$' || fail "MARKETING_VERSION is not year.month.patch: $VERSION"

TAG=$(echo "$VERSION" | awk -F. '{ printf "v%d.%02d.%d", $1, $2, $3 }')
NEXT=$(echo "$VERSION" | awk -F. -v year="$(date +%Y)" -v month="$(date +%m)" '{
  if ($1 == year && $2 + 0 == month + 0) printf "%d.%d.%d", $1, $2, $3 + 1
  else printf "%d.%d.0", year, month
}')

if git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null; then
  fail "$TAG already exists: $VERSION is released. Bump MARKETING_VERSION instead."
fi

# Every check on HEAD, GitHub's and Xcode Cloud's, finished and passed.
CHECKS=$(gh api --paginate "repos/{owner}/{repo}/commits/$SHA/check-runs" \
  -q '.check_runs[] | "\(.status) \(.conclusion) \(.name)"')
[ -n "$CHECKS" ] || fail "No checks on $(git rev-parse --short HEAD) yet: wait for CI and Xcode Cloud."
NOT_GREEN=$(echo "$CHECKS" | grep -Ev '^completed (success|skipped|neutral) ' || true)
[ -z "$NOT_GREEN" ] || fail "Not every check on $(git rev-parse --short HEAD) passed:
$NOT_GREEN"

echo "Release $VERSION: tag $TAG on $(git log -1 --format='%h %s')"
echo "Then main moves to $NEXT: \"[Build] Version $NEXT\""
if $DRY_RUN; then
  echo "Dry run: nothing changed."
  exit 0
fi

git tag -a "$TAG" -m "Version $VERSION"

sed "s/^\([[:space:]]*MARKETING_VERSION = \)$VERSION;$/\1$NEXT;/" "$PBXPROJ" >"$PBXPROJ.tmp"
mv "$PBXPROJ.tmp" "$PBXPROJ"
[ "$(grep -c "MARKETING_VERSION = $NEXT;" "$PBXPROJ")" = 2 ] || fail "Could not set MARKETING_VERSION to $NEXT in $PBXPROJ."
git commit --quiet -m "[Build] Version $NEXT" -- "$PBXPROJ"

# One push for both, so main never has the tag without the bump.
git push --quiet --atomic origin main "refs/tags/$TAG"

gh release create "$TAG" --verify-tag --draft --generate-notes --title "$TAG" >/dev/null ||
  echo "Pushed, but the draft release failed: create it on GitHub from $TAG." >&2
echo "Released $TAG; main is now $NEXT."
echo "Edit and publish the draft: $(gh browse --no-browser --releases 2>/dev/null || echo 'the Releases page on GitHub')"
