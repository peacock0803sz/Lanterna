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
if [[ $(lipo -archs "$binary") != "arm64" ]]; then
    echo "package-app: expected arm64-only binary" >&2
    exit 1
fi

app="build/Lanterna.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Lanterna"

# Ship the kana tables as plain resources. The SPM resource bundle
# itself is not packaged: its BNDL format is rejected by codesign on
# some toolchains ("bundle format unrecognized" in the release job),
# while flat files under Contents/Resources join the main signature.
# Tables come from the vendored sources directly: the built bundle's
# location next to the binary differs per toolchain, but the sources
# are the single source of truth.
tables_src="Sources/CMigemo/tables"
mkdir -p "$app/Contents/Resources/tables"
for table in roma2hira.dat hira2kata.dat han2zen.dat zen2han.dat; do
    if [[ ! -f "$tables_src/$table" ]]; then
        echo "package-app: missing $tables_src/$table" >&2
        exit 1
    fi
    cp "$tables_src/$table" "$app/Contents/Resources/tables/"
done

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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Lanterna</string>
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

codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

dmg="build/Lanterna-${short}.dmg"
rm -f "$dmg"
hdiutil create -volname "Lanterna" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null
echo "package-app: $dmg"
