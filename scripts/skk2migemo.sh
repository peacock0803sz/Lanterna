#!/usr/bin/env bash
# Converts an SKK dictionary into the migemo-dict format used for kanji
# readings: one tab-separated "reading + candidates" entry per line.
#
# Usage: scripts/skk2migemo.sh [SKK-JISYO.L] [migemo-dict]
#
# SKK dictionaries are EUC-JP encoded; the output is UTF-8. Entries with
# okurigana are out of scope and skipped. Annotations after ";" are
# dropped, keeping bare kanji only. Place the result at
# ~/Library/Application Support/Lanterna/migemo-dict and restart.
set -euo pipefail

input="${1:-SKK-JISYO.L}"
output="${2:-migemo-dict}"

if [ ! -f "$input" ]; then
    echo "missing input: $input" >&2
    exit 1
fi

output_dir="$(dirname "$output")"
if [ ! -d "$output_dir" ]; then
    echo "missing parent directory: $output_dir" >&2
    exit 1
fi
if [ -d "$output" ]; then
    echo "output is a directory, give a file path: $output" >&2
    exit 1
fi

iconv -f EUC-JP -t UTF-8 "$input" | awk '
!/^;/ && NF >= 2 {
    yomi = $1
    # Strip okurigana: a trailing ASCII letter on a non-ASCII key.
    if (yomi ~ /[a-zA-Z]$/ && yomi ~ /[^ -~]/) {
        yomi = substr(yomi, 1, length(yomi) - 1)
    }
    if (yomi ~ /[a-zA-Z]$/) {
        next
    }
    $1 = ""
    line = $0
    gsub(/^ +\//, "", line)
    gsub(/\/$/, "", line)
    n = split(line, cands, "/")
    out = ""
    for (i = 1; i <= n; i++) {
        split(cands[i], ann, ";")
        if (ann[1] != "") {
            out = (out == "" ? ann[1] : out "\t" ann[1])
        }
    }
    if (yomi != "" && out != "") {
        print yomi "\t" out
    }
}' > "$output"

echo "wrote $output"
