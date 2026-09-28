#!/usr/bin/env bash
# Assembles Lanterna.app, then a DMG holding it.
#
# The release gate comes first: HEAD must sit exactly on a `vX.Y.Z` tag with
# a clean tree. The version is then regenerated from the tag and applied, so
# the bundle and the on-screen display always name the tagged release. The
# checked-in stamp is only a placeholder; the tag is the single source of
# truth.
#
# Icon artwork comes from Assets/Lanterna.iconset, a tracked copy of the
# provided materials. A missing size fails the run; a generic icon never ships.
set -euo pipefail

cd "$(dirname "$0")/.."

tag=$(git describe --tags --exact-match 2>/dev/null) || {
    echo "package-app: HEAD is not exactly on a release tag" >&2
    exit 1
}
if [[ ! $tag =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "package-app: refusing tag \"$tag\"; need exactly vX.Y.Z" >&2
    exit 1
fi
short="${BASH_REMATCH[1]}"

if [[ -n $(git status --short) ]]; then
    echo "package-app: working tree is not clean" >&2
    git status --short >&2
    exit 1
fi

# Restamp from the tag: the bundle and the on-screen display always name
# this tag, regardless of what the checked-in stamp says.
bash scripts/generate-version.sh >/dev/null

swift build --triple arm64-apple-macosx26.0 --configuration release
binary="$(swift build --triple arm64-apple-macosx26.0 --configuration release --show-bin-path)/Lanterna"

# Bundle assembly lives in assemble-app.sh, shared with the nix derivation
# so both paths ship the same layout.
app="build/Lanterna.app"
bash scripts/assemble-app.sh "$binary" "$short" "$app"

dmg="build/Lanterna-${short}.dmg"
rm -f "$dmg"
hdiutil create -volname "Lanterna" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null
echo "package-app: $dmg"
