#!/usr/bin/env bash
# Re-vendors the C/Migemo subset from the pinned release.
#
# Reads the tag from Sources/CMigemo/VERSION, downloads that release
# tarball, and refreshes the vendored sources, public header, runtime
# tables, and license check below. Run by
# .github/workflows/vendor-cmigemo.yml on version-pin pull requests;
# run by hand the same way for the first vendoring.
#
# The upstream LICENSE text must match the notice appended to LICENSE.
# Any drift fails the script so a human reviews the new terms first.
set -euo pipefail

cd "$(dirname "$0")/.."

version="$(tr -d '[:space:]' < Sources/CMigemo/VERSION)"
case "$version" in
v[0-9]*.[0-9]*.[0-9]*) ;;
*)
    echo "unexpected version pin: $version" >&2
    exit 1
    ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -sSL --max-time 120 \
    "https://github.com/koron/cmigemo/archive/refs/tags/${version}.tar.gz" \
    -o "$work/cmigemo.tar.gz"
tar -xzf "$work/cmigemo.tar.gz" -C "$work"
src="$work/cmigemo-${version#v}"

if [ ! -d "$src/src" ]; then
    echo "missing src in $version tarball" >&2
    exit 1
fi

dst="Sources/CMigemo"
# Files owned by this repository, not upstream: keep across refreshes.
keep_c="migemo_utf8.c"
keep_h="migemo_utf8.h"
[ -f "$dst/$keep_c" ] && cp "$dst/$keep_c" "$work/keep.c"
[ -f "$dst/include/$keep_h" ] && cp "$dst/include/$keep_h" "$work/keep.h"
mkdir -p "$dst/include" "$dst/tables"
rm -f "$dst"/*.c "$dst"/*.h "$dst"/tables/*.dat
for stale in "$dst"/include/*.h; do
    case "$(basename "$stale")" in
    "$keep_h" | migemo.h) ;;
    *) rm -f "$stale" ;;
    esac
done
for name in charset filename migemo mtree romaji rxgen strbuf stree trie wordlist; do
    cp "$src/src/${name}.c" "$dst/"
done
for name in charset common filename migemo_struct mtree romaji rxgen strbuf stree trie wordlist; do
    cp "$src/src/${name}.h" "$dst/"
done
major="${version#v}"
major="${major%%.*}"
rest="${version#v*.}"
minor="${rest%%.*}"
patch="${rest##*.}"
sed -e "s/@PROJECT_VERSION@/${version#v}/" \
    -e "s/@PROJECT_VERSION_MAJOR@/${major}/" \
    -e "s/@PROJECT_VERSION_MINOR@/${minor}/" \
    -e "s/@PROJECT_VERSION_PATCH@/${patch}/" \
    -e "s/@PROJECT_VERSION_PRERELEASE@//" \
    "$src/include/migemo.h.in" > "$dst/include/migemo.h"
for name in roma2hira hira2kata han2zen zen2han; do
    cp "$src/dict/${name}.dat" "$dst/tables/"
done
[ -f "$work/keep.c" ] && cp "$work/keep.c" "$dst/$keep_c"
[ -f "$work/keep.h" ] && cp "$work/keep.h" "$dst/include/$keep_h"

if ! diff -q "$src/LICENSE" <(sed -n '/^Copyright (c) 2003/,$p' LICENSE) > /dev/null; then
    echo "upstream LICENSE drifted; review the new terms by hand" >&2
    exit 1
fi

echo "vendored ${version}"
