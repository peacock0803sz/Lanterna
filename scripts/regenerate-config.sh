#!/usr/bin/env bash
# Regenerates config artifacts from ConfigSchema.pkl.
#
# Outputs: config/schema-snapshot.json (the schema's rendered defaults) and
# config/config-schema.json (the JSON Schema document). When either changes,
# update AppConfiguration.swift to match, so the three (schema, types,
# scaffold) stay as one. CI runs --check.
#
# First run canonicalizes both files; commit the result.
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:---write}"
snapshot="config/schema-snapshot.json"
schema_doc="config/config-schema.json"
tmp_snapshot="${TMPDIR:-/tmp}/lanterna-schema-$$"
tmp_schema="${TMPDIR:-/tmp}/lanterna-jsonschema-$$"
trap 'rm -f "$tmp_snapshot" "$tmp_schema"' EXIT

pkl eval --format json config/ConfigSchema.pkl > "$tmp_snapshot"
pkl eval --format json config/GenJsonSchema.pkl > "$tmp_schema"

if [ "$mode" = "--check" ]; then
    if [ ! -f "$snapshot" ] || [ ! -f "$schema_doc" ]; then
        echo "missing generated files; run scripts/regenerate-config.sh" >&2
        exit 1
    fi
    diff -u "$snapshot" "$tmp_snapshot"
    diff -u "$schema_doc" "$tmp_schema"
else
    mkdir -p config
    cp "$tmp_snapshot" "$snapshot"
    cp "$tmp_schema" "$schema_doc"
fi
