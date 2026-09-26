#!/usr/bin/env bash
# Regenerates the schema snapshot from ConfigSchema.pkl.
#
# The snapshot is the mechanical rendering of the schema's defaults. When it
# changes, update AppConfiguration.swift and the scaffold to match, so the
# three (schema, types, scaffold) stay as one. CI runs --check.
#
# First run canonicalizes config/schema-snapshot.json; commit the result.
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:---write}"
snapshot="config/schema-snapshot.json"
tmp="${TMPDIR:-/tmp}/lanterna-schema-$$"
trap 'rm -f "$tmp"' EXIT

pkl eval --format json config/ConfigSchema.pkl > "$tmp"

if [ "$mode" = "--check" ]; then
    if [ ! -f "$snapshot" ]; then
        echo "missing $snapshot; run scripts/regenerate-config.sh" >&2
        exit 1
    fi
    diff -u "$snapshot" "$tmp"
else
    mkdir -p config
    cp "$tmp" "$snapshot"
fi
