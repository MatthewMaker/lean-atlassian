#!/usr/bin/env bash
#
# Records the user's confirmation of a project settings file's
# `## Auto-approved operations` list, so approve-listed-operations.sh starts
# honouring it.
#
# Not a hook. Claude runs it — with the absolute paths that
# load-atlassian-config.sh injects — only after the user has explicitly said
# yes to the exact list. The Bash tool's environment has no CLAUDE_PLUGIN_DATA,
# so the data directory is passed in.
#
# A confirmation covers one file and one set of operation names. Changing the
# set (adding or removing an operation) needs a fresh confirmation; reordering
# or editing comments does not. Re-confirming a file replaces its old entry.
#
# Usage: trust-approval-list.sh SETTINGS_FILE DATA_DIR

set -uo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

file="${1:-}"
data="${2:-}"
if [[ -z "$file" || -z "$data" ]]; then
    echo "usage: trust-approval-list.sh SETTINGS_FILE DATA_DIR" >&2
    exit 2
fi
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }

names="$(approval_list "$file" | sort -u)"
[[ -n "$names" ]] || { echo "no operations listed under '## Auto-approved operations' in $file" >&2; exit 1; }

mkdir -p "$data" || exit 1
store="$data/trusted-lists"
tmp="$(mktemp "$data/trusted-lists.XXXXXX")" || exit 1

# Drop this file's previous confirmation, then add the current one.
if [[ -f "$store" ]]; then
    awk -F'\t' -v f="$file" '$2 != f' "$store" > "$tmp"
fi
printf '%s\t%s\n' "$(list_hash "$file")" "$file" >> "$tmp"
mv "$tmp" "$store"

echo "Confirmed for $file:"
awk '{ print "  " $0 }' <<<"$names"
