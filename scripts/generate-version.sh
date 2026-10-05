#!/usr/bin/env bash
# Stamps Sources/Lanterna/Support/StampedVersion.swift with the `git describe`
# string of this checkout, so every build names the binary at hand.
#
# Two stamping modes. The default refuses anything but exactly `vX.Y.Z` on a
# clean tree: the release path (package-app.sh) keeps that gate, and a build
# that cannot name its release does not happen there. `--dev` writes whatever
# `git describe` says instead — distance past the tag, dirty flag and all —
# so a development build shows where it really comes from. The on-screen
# window shows the full string verbatim; the short X.Y.Z is derived in Swift
# (VersionDescriptor) where the rules stay testable.
#
# The file is rewritten only when the string changed, so stamping leaves a
# settled tree alone.
#
# The checked-in file holds the placeholder "dev", and a clean filter keeps
# the stamp out of git's view: `--clean` is that filter, turning any stamped
# file back into the placeholder, and `--install-filter` registers it in this
# clone's git config (the devshell does this on entry). Without the filter the
# stamp shows as a modification, and `--dirty` then marks every later stamp.
set -euo pipefail

cd "$(dirname "$0")/.."

target="Sources/Lanterna/Support/StampedVersion.swift"
kind_target="Sources/Lanterna/Support/StampedBuildKind.swift"
filter_command="bash scripts/generate-version.sh --clean"

case ${1:-} in
--clean)
    exec sed -E -e 's/(static let describe = ").*(")/\1dev\2/' -e 's/(static let kind = ").*(")/\1main\2/'
    ;;
--install-filter)
    if [[ $(git config --get filter.stamped-version.clean || true) != "$filter_command" ]]; then
        git config filter.stamped-version.clean "$filter_command"
        echo "generate-version: installed the stamped-version clean filter"
    fi
    exit 0
    ;;
--dev)
    dev=1
    ;;
*)
    dev=0
    ;;
esac

# Git trusts a size mismatch between the index and the file without running
# the filter, and a stamp is never as long as the placeholder, so the entries
# are refreshed after stamping. Only with the filter in place: without it this
# would stage the stamps themselves.
refresh_index() {
    if [[ $(git config --get filter.stamped-version.clean || true) == "$filter_command" ]]; then
        for stamped in "$target" "$kind_target"; do
            if [[ $(git check-attr filter -- "$stamped") == *": stamped-version" ]] &&
                git ls-files --error-unmatch -- "$stamped" >/dev/null 2>&1; then
                git update-index -- "$stamped"
            fi
        done
    fi
}

describe=$(git describe --tags --dirty --always 2>/dev/null) || {
    echo "generate-version: git describe failed; is this a git checkout?" >&2
    exit 1
}

if [[ $dev -eq 0 && ! $describe =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    echo "generate-version: refusing \"$describe\"; need exactly vX.Y.Z on a clean tree" >&2
    exit 1
fi

current=""
current_kind=""
if [[ -f $target ]]; then
    current=$(sed -n 's/.*static let describe = "\(.*\)"/\1/p' "$target" | head -n 1)
fi
if [[ -f $kind_target ]]; then
    current_kind=$(sed -n 's/.*static let kind = "\(.*\)"/\1/p' "$kind_target" | head -n 1)
fi
if [[ $dev -eq 1 ]]; then
    kind="main"
else
    kind="stable"
fi
if [[ $current == "$describe" && $current_kind == "$kind" ]]; then
    refresh_index
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
cat > "$kind_target" <<EOF
/// Stamped by scripts/generate-version.sh at build time. Do not edit.
enum StampedBuildKind {
  /// Which configuration slot this binary belongs to: "stable" for the
  /// packaged release, "main" for development builds.
  static let kind = "$kind"
}
EOF
refresh_index

echo "generate-version: stamped $describe"
