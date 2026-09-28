#!/usr/bin/env bash
# Assembles Lanterna.app from a built binary.
#
# Shared by scripts/package-app.sh (DMG path) and the nix derivation: both
# ship the same bundle layout, so the steps live here instead of twice.
# Takes the release binary, the short X.Y.Z version for the bundle, and the
# destination .app path. Fails when the icon artwork or kana tables are
# missing; a generic icon never ships.
set -euo pipefail

binary="${1:?usage: assemble-app.sh <binary> <short-version> <out-app>}"
short="${2:?usage: assemble-app.sh <binary> <short-version> <out-app>}"
app="${3:?usage: assemble-app.sh <binary> <short-version> <out-app>}"

cd "$(dirname "$0")/.."

if [[ $(lipo -archs "$binary") != "arm64" ]]; then
    echo "assemble-app: expected arm64-only binary" >&2
    exit 1
fi

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
        echo "assemble-app: missing $tables_src/$table" >&2
        exit 1
    fi
    cp "$tables_src/$table" "$app/Contents/Resources/tables/"
done

iconset="Assets/Lanterna.iconset"
for size in 16 32 128 256 512; do
    if [[ ! -f "$iconset/icon_${size}x${size}.png" ]]; then
        echo "assemble-app: missing $iconset/icon_${size}x${size}.png" >&2
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
echo "assemble-app: $app"
