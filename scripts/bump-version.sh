#!/usr/bin/env bash
# Commits the version declaration for a release.
#
# Usage: bash scripts/bump-version.sh <X.Y.Z>   (no v prefix)
#
# The generated file must be committed before the release tag is cut,
# because package-app.sh refuses a tag whose committed Version.swift
# differs from a fresh generation. This script performs exactly that
# handshake (temporary tag, generate, delete the tag, commit) so the
# release operation cannot forget it. Tagging and pushing stay manual.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:?usage: bump-version.sh <X.Y.Z>}"
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "bump-version: refusing \"$version\"; need exactly X.Y.Z (no v prefix)" >&2
    exit 1
fi
tag="v$version"

if [[ -n $(git status --short) ]]; then
    echo "bump-version: working tree is not clean" >&2
    git status --short >&2
    exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "bump-version: local tag \"$tag\" already exists" >&2
    exit 1
fi
if git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/$tag$"; then
    echo "bump-version: remote tag \"$tag\" already exists" >&2
    exit 1
fi

git tag "$tag" # temporary, for generation only
bash scripts/generate-version.sh >/dev/null
git tag -d "$tag" >/dev/null
git add Sources/Lanterna/Support/Version.swift
git commit -m ":bookmark: Set version to $tag"

echo "bump-version: committed $tag. Tag it after merging: git tag $tag"
