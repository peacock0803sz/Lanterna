#!/usr/bin/env bash
# Stamps Sources/Lanterna/Support/StampedVersion.swift with the `git describe`
# string of this checkout, so every build names the binary at hand.
#
# Two modes. The default refuses anything but exactly `vX.Y.Z` on a clean
# tree: the release path (package-app.sh) keeps that gate, and a build that
# cannot name its release does not happen there. `--dev` writes whatever
# `git describe` says instead — distance past the tag, dirty flag and all —
# so a development build shows where it really comes from. The on-screen
# window shows the full string verbatim; the short X.Y.Z is derived in Swift
# (VersionDescriptor) where the rules stay testable.
#
# The file is rewritten only when the string changed, so stamping leaves a
# settled tree alone.
set -euo pipefail

cd "$(dirname "$0")/.."

dev=0
if [[ ${1:-} == "--dev" ]]; then
    dev=1
fi

describe=$(git describe --tags --dirty --always 2>/dev/null) || {
    echo "generate-version: git describe failed; is this a git checkout?" >&2
    exit 1
}

if [[ $dev -eq 0 && ! $describe =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "generate-version: refusing \"$describe\"; need exactly vX.Y.Z on a clean tree" >&2
    exit 1
fi

target="Sources/Lanterna/Support/StampedVersion.swift"
current=""
if [[ -f $target ]]; then
    current=$(sed -n 's/.*static let describe = "\(.*\)"/\1/p' "$target" | head -n 1)
fi
if [[ $current == "$describe" ]]; then
    echo "generate-version: already stamped $describe"
    exit 0
fi

cat > "$target" <<EOF
/// Stamped by scripts/generate-version.sh at build time. Do not edit.
enum StampedVersion {
    /// The raw \`git describe\` string of the checkout this binary came from.
    static let describe = "$describe"
}
EOF

echo "generate-version: stamped $describe"
