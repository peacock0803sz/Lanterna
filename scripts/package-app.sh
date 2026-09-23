#!/usr/bin/env bash
# Assembles Lanterna.app, then a DMG holding it.
#
# The release gate comes first: HEAD must sit exactly on a `vX.Y.Z` tag with
# a clean tree. Regeneration is then compared rather than applied, so the
# tree stays clean throughout: a mismatch between the committed Version.swift
# and a fresh generation fails the run instead of shipping a stale version.
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

# Regenerate aside and compare: the committed file must already name this tag.
cp Sources/Lanterna/Support/Version.swift /tmp/lanterna-version-committed.swift
bash scripts/generate-version.sh >/dev/null
if ! cmp -s Sources/Lanterna/Support/Version.swift /tmp/lanterna-version-committed.swift; then
    cp /tmp/lanterna-version-committed.swift Sources/Lanterna/Support/Version.swift
    echo "package-app: regenerated version differs from the committed file" >&2
    exit 1
fi

swift build --triple arm64-apple-macosx26.0 --configuration release
binary="$(swift build --triple arm64-apple-macosx26.0 --configuration release --show-bin-path)/Lanterna"
if [[ $(lipo -archs "$binary") != "arm64" ]]; then
    echo "package-app: expected arm64-only binary" >&2
    exit 1
fi

app="build/Lanterna.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Lanterna"

iconset="Assets/Lanterna.iconset"
for size in 16 32 128 256 512; do
    if [[ ! -f "$iconset/icon_${size}x${size}.png" ]]; then
        echo "package-app: missing $iconset/icon_${size}x${size}.png" >&2
        exit 1
    fi
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Lanterna.icns"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Lanterna</string>
    <key>CFBundleIdentifier</key>
    <string>net.p3ac0ck.app.Lanterna</string>
    <key>CFBundleShortVersionString</key>
    <string>${short}</string>
    <key>CFBundleVersion</key>
    <string>${short}</string>
    <key>CFBundleIconFile</key>
    <string>Lanterna</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Lanterna lists and switches windows through accessibility information.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$app"

dmg="build/Lanterna-${short}.dmg"
rm -f "$dmg"
hdiutil create -volname "Lanterna" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null
echo "package-app: $dmg"
