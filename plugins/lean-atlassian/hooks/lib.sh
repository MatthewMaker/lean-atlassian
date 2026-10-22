# shellcheck shell=bash
#
# Shared helpers for the lean-atlassian hooks. Sourced, never executed.
#
# Every function here fails quietly — empty output or a false return, never a
# message on stdout — because the hooks that source it must always emit valid
# JSON.

# Resolve the settings file. Cascade — first match wins, and both tiers accept
# the legacy `private-atlassian.local.md` name after the current one:
#   1. $CLAUDE_PROJECT_DIR/.claude/lean-atlassian.local.md
#   2. $CLAUDE_PROJECT_DIR/.claude/private-atlassian.local.md      (legacy)
#   3. ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lean-atlassian.local.md
#   4. ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/private-atlassian.local.md  (legacy)
#
# Sets settings_file, settings_tier (project|global) and settings_src (the
# project-relative path for a project hit, the absolute path for a global one).
# Returns false, with all three empty, when nothing is found.
#
# When the project's .claude directory IS the config directory (a session
# started in $HOME with the default config dir), the project tier is skipped so
# the user's own global file is never mistaken for a project file.
# shellcheck disable=SC2034  # settings_* are read by the sourcing hooks
resolve_settings() {
    local proj="${CLAUDE_PROJECT_DIR:-$PWD}"
    local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local name
    settings_file="" settings_tier="" settings_src=""

    if [[ ! "$proj/.claude" -ef "$cfg" ]]; then
        for name in lean-atlassian.local.md private-atlassian.local.md; do
            [[ -f "$proj/.claude/$name" ]] || continue
            settings_file="$proj/.claude/$name"
            settings_tier=project
            settings_src="project .claude/$name"
            return 0
        done
    fi
    for name in lean-atlassian.local.md private-atlassian.local.md; do
        [[ -f "$cfg/$name" ]] || continue
        settings_file="$cfg/$name"
        settings_tier=global
        settings_src="$settings_file"
        return 0
    done
    return 1
}

# Both functions below skip fenced code blocks (``` or ~~~): a heading or bullet
# inside a fence is documentation, such as the sample list in the .example
# file, and must never grant anything.

# True when FILE has an `## Auto-approved operations` heading, even an empty one.
has_approval_section() {
    awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        !fence && /^## Auto-approved operations[[:space:]]*$/ { found = 1; exit }
        END { exit !found }
    ' "$1" 2>/dev/null
}

# Print the operation names listed under `## Auto-approved operations` in FILE:
# the first word of each `- ` bullet, backticks stripped, up to the next `## `.
approval_list() {
    awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        /^## / { in_list = ($0 ~ /^## Auto-approved operations[[:space:]]*$/); next }
        in_list && /^[[:space:]]*- / {
            sub(/^[[:space:]]*- [[:space:]]*/, "")
            gsub(/`/, "")
            split($0, word, /[[:space:]]+/)
            if (word[1] != "") print word[1]
        }
    ' "$1" 2>/dev/null
}

# SHA-256 of stdin as bare hex. shasum ships with macOS, sha256sum with Linux.
sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -d' ' -f1
}

# Fingerprint of FILE's approval list. Sorted and de-duplicated, so reordering
# bullets or editing their comments keeps a confirmed list confirmed; adding or
# removing an operation does not.
list_hash() {
    approval_list "$1" | sort -u | sha256
}

# True when the user has confirmed FILE's current approval list. Confirmations
# live in DATA_DIR/trusted-lists as `<list hash><TAB><file path>` lines, written
# by trust-approval-list.sh. No data dir means nothing is confirmed.
is_trusted() {
    local file="$1" data="$2"
    [[ -n "$data" && -f "$data/trusted-lists" ]] || return 1
    grep -qxF -- "$(list_hash "$file")"$'\t'"$file" "$data/trusted-lists"
}
