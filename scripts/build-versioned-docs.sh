#!/usr/bin/env bash
#
# Build versioned docs for a single Cloudflare Pages production deploy.
#
# Layout produced in docs/dist/:
#   /               stable content (built with DOCS_BASE=/, DOCS_REF=<stable-tag>)
#   /main/          main snapshot (DOCS_BASE=/main/, DOCS_REF=main)
#   /vX.Y.Z/        one dir per eligible tag (DOCS_BASE=/<tag>/, DOCS_REF=<tag>)
#   versions.json   {"stable":"<stable-tag>","versions":["vA.B.C",...,"main"]}
#
# Overlay means: each version build copies that ref's docs/src/content and
# docs/public over the current docs/ tree, so every version builds with the
# current toolchain and chrome. The working tree content is restored on exit.
#
# Usage:
#   bash scripts/build-versioned-docs.sh [--only <csv>] [--versions-json-out <path>]
#
# Flags:
#   --only <csv>               build only these tags (stable root and main are
#                              always built); for local verification.
#   --versions-json-out <path> write versions.json content to <path> without
#                              building anything, then exit 0.
#
# Runs with the repo root as cwd and handles the docs/ tree itself. Exits
# non-zero when any version build fails.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ONLY=""
VERSIONS_JSON_OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      ONLY="${2:?--only requires a comma-separated tag list}"
      shift 2
      ;;
    --versions-json-out)
      VERSIONS_JSON_OUT="${2:?--versions-json-out requires a path}"
      shift 2
      ;;
    --help|-h)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

git fetch origin stable main --tags

# Resolve the stable version label: exact tag when stable points at a release,
# otherwise the newest ancestor tag (e.g. manual push one commit past a tag).
if STABLE_TAG="$(git describe --tags --exact-match origin/stable 2>/dev/null)"; then
  :
else
  STABLE_TAG="$(git describe --tags --abbrev=0 origin/stable)"
fi
echo "stable ref: origin/stable -> ${STABLE_TAG}"

# Enumerate tags that contain docs; older tags (pre-v0.4.1) have no docs/
# tree and are skipped instead of failing the whole deploy.
ELIGIBLE_TAGS=()
while IFS= read -r tag; do
  [[ -n "$tag" ]] || continue
  if git cat-file -e "${tag}:docs/package.json" 2>/dev/null; then
    ELIGIBLE_TAGS+=("$tag")
  else
    echo "skipping tag without docs: ${tag}"
  fi
done < <(git tag --sort=version:refname)

if [[ ${#ELIGIBLE_TAGS[@]} -eq 0 ]]; then
  echo "error: no tags with docs found" >&2
  exit 1
fi

# Tags to build per version: everything eligible, or the --only subset.
BUILD_TAGS=()
if [[ -n "$ONLY" ]]; then
  IFS=',' read -r -a ONLY_TAGS <<< "$ONLY"
  for tag in "${ONLY_TAGS[@]}"; do
    found=0
    for eligible in "${ELIGIBLE_TAGS[@]}"; do
      if [[ "$tag" == "$eligible" ]]; then
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      echo "error: --only tag has no docs or does not exist: ${tag}" >&2
      exit 1
    fi
    BUILD_TAGS+=("$tag")
  done
else
  BUILD_TAGS=("${ELIGIBLE_TAGS[@]}")
fi

# versions.json always describes the full eligible set (plus main), even for
# --only subset builds, so the version selector links stay complete.
VERSIONS_JSON="{\"stable\":\"${STABLE_TAG}\",\"versions\":["
sep=""
for tag in "${ELIGIBLE_TAGS[@]}"; do
  VERSIONS_JSON+="${sep}\"${tag}\""
  sep=","
done
VERSIONS_JSON+="${sep}\"main\"]}"

if [[ -n "$VERSIONS_JSON_OUT" ]]; then
  printf '%s\n' "$VERSIONS_JSON" > "$VERSIONS_JSON_OUT"
  echo "wrote versions list to ${VERSIONS_JSON_OUT} (no build)"
  exit 0
fi

echo "versions: ${VERSIONS_JSON}"

# Back up the current content dirs so the overlay builds leave the working
# tree exactly as it was, on success and on failure.
BACKUP_DIR="$(mktemp -d)"
STAGING_DIR="$(mktemp -d)"
cp -a docs/src/content "${BACKUP_DIR}/content"
cp -a docs/public "${BACKUP_DIR}/public"
cleanup() {
  rm -rf docs/src/content docs/public
  cp -a "${BACKUP_DIR}/content" docs/src/content
  cp -a "${BACKUP_DIR}/public" docs/public
  rm -rf "$BACKUP_DIR" "$STAGING_DIR"
}
trap cleanup EXIT

build_one() {
  local git_ref="$1"  # ref whose content dirs are overlaid (origin/stable, origin/main, tag)
  local docs_ref="$2" # DOCS_REF value (stable tag, main, tag)
  local docs_base="$3" # DOCS_BASE value (/, /main/, /<tag>/)
  local dest_name="$4" # staging subdir (root, main, <tag>)
  echo "building ref=${git_ref} DOCS_BASE=${docs_base} DOCS_REF=${docs_ref} DOCS_VERSIONS_JSON=${VERSIONS_JSON}"
  rm -rf docs/src/content docs/public
  git archive "$git_ref" -- docs/src/content docs/public | tar -x -C .
  rm -rf docs/dist
  export DOCS_BASE="$docs_base"
  export DOCS_REF="$docs_ref"
  export DOCS_VERSIONS_JSON="$VERSIONS_JSON"
  if ! pnpm --dir docs build; then
    echo "error: docs build failed for ref ${git_ref} (DOCS_REF=${docs_ref})" >&2
    exit 1
  fi
  rm -rf "${STAGING_DIR:?}/${dest_name:?}"
  mv docs/dist "${STAGING_DIR}/${dest_name}"
}

# Stable site at root.
build_one "origin/stable" "$STABLE_TAG" "/" "root"

# Main snapshot.
build_one "origin/main" "main" "/main/" "main"

# Per-tag version dirs.
for tag in "${BUILD_TAGS[@]}"; do
  build_one "$tag" "$tag" "/${tag}/" "$tag"
done

# Assemble the final dist layout.
rm -rf docs/dist
mv "${STAGING_DIR}/root" docs/dist
mkdir -p docs/dist/main
rm -rf docs/dist/main
mv "${STAGING_DIR}/main" docs/dist/main
for tag in "${BUILD_TAGS[@]}"; do
  rm -rf "docs/dist/${tag}"
  mv "${STAGING_DIR}/${tag}" "docs/dist/${tag}"
done
printf '%s\n' "$VERSIONS_JSON" > docs/dist/versions.json
echo "versioned docs ready in docs/dist"
