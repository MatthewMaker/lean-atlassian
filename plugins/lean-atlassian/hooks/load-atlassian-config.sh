#!/usr/bin/env bash
#
# SessionStart hook for the lean-atlassian plugin.
#
# Loads the user's Atlassian cloud_id / site_url and injects them into the
# session as additionalContext, so /jira, /confluence, and the
# atlassian-mediation skill can use the cloud_id directly and never call
# getAccessibleAtlassianResources.
#
# Why a hook rather than a `!`...`` injection in the command/skill: the
# command-bash permission checker hard-rejects any injected command that
# contains shell expansion ("Contains expansion"), so `$CLAUDE_CONFIG_DIR`
# cannot be referenced there. A plugin hook runs as a real shell with the full
# environment, so it can resolve the user's actual (possibly non-default)
# config directory.
#
# The settings file is resolved by the first-match cascade in lib.sh: project
# `.claude/` before the global config dir, and the current filename before the
# legacy `private-atlassian.local.md` within each tier.
#
# It also injects at most one one-time offer per session (see "One-time offers"
# below) when $CLAUDE_PLUGIN_DATA is available to remember what was offered.
#
# Emitting `{}` (no additionalContext) when nothing is configured keeps the
# hook silent; the commands/skill then fall back to a one-time MCP lookup.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

# Nothing configured anywhere → stay silent and let the MCP fallback handle it.
if ! resolve_settings; then
    echo '{}'
    exit 0
fi
file="$settings_file"
src="$settings_src"

# Read one YAML frontmatter field. Only the block between the opening and
# closing `---` is searched, so field-like lines in the body (the .example
# file's sample block) never stand in for a missing field. A quoted value runs
# to its last matching quote; an unquoted one ends at ` #`. Either way a
# trailing comment is dropped. Returns empty (never errors) when the key is
# absent or the file has no frontmatter.
read_field() {
    awk -v key="$1" '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
        /^---[[:space:]]*$/ { exit }
        index($0, key ":") == 1 {
            v = substr($0, length(key) + 2)
            sub(/^[[:space:]]+/, "", v)
            q = substr(v, 1, 1)
            if (q == "\"" || q == "\047") {
                v = substr(v, 2)
                sub(q "[[:space:]]*(#.*)?$", "", v)
            } else {
                sub(/[[:space:]]+#.*$/, "", v)
                sub(/[[:space:]]+$/, "", v)
            }
            print v
            exit
        }
    ' "$file" 2>/dev/null
}

cloud_id="$(read_field cloud_id)"
site_url="$(read_field site_url)"
# Optional scalars — broadly useful and cheap, so inject them too when present.
# account_id saves an atlassianUserInfo call (assignment, "my issues");
# project_key saves a listJiraProjects call (default project scope).
account_id="$(read_field account_id)"
project_key="$(read_field project_key)"

# Treat the unedited example placeholder (or an empty value) as "not configured".
if [[ -z "$cloud_id" || "$cloud_id" == "your-cloud-id-here" ]]; then
    echo '{}'
    exit 0
fi

# Minimal JSON-string escaping for embedded values: backslash first, then quote.
json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
cloud_id="$(json_escape "$cloud_id")"
site_url="$(json_escape "$site_url")"
account_id="$(json_escape "$account_id")"
project_key="$(json_escape "$project_key")"
src="$(json_escape "$src")"

# additionalContext is a single JSON string; the literal \n sequences below
# render as newlines in the injected context.
ctx="## Atlassian settings (lean-atlassian plugin)\n\n"
ctx+="Use these for every Atlassian MCP call. The cloud_id is already known — do NOT call getAccessibleAtlassianResources.\n"
ctx+="- cloud_id: ${cloud_id}\n"
ctx+="- site_url: ${site_url}\n"
# Only surface the optional identifiers that are actually configured.
[[ -n "$account_id" ]] && ctx+="- account_id: ${account_id} (your Jira accountId — use for assignment; do NOT call atlassianUserInfo)\n"
[[ -n "$project_key" ]] && ctx+="- project_key: ${project_key} (default Jira project for searches and new issues)\n"
ctx+="\n(loaded from ${src})"

# --- One-time offers ---------------------------------------------------------
#
# Three offers, at most one per session, each made at most once — the marker is
# written when the offer is injected, so a declined offer doesn't come back:
#
#   copy     only the global file exists and the session is in a git repo:
#            offer to copy it into this repo's .claude/ (once per repo)
#   add      the resolved file has no `## Auto-approved operations` section:
#            offer to add one (once per file)
#   confirm  a project file's approval list isn't confirmed, so
#            approve-listed-operations.sh is ignoring it: offer to confirm it
#            (once per file per set of operations)
#
# Without $CLAUDE_PLUGIN_DATA nothing can be remembered, so nothing is offered.

data="${CLAUDE_PLUGIN_DATA:-}"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"

# True (and recorded) the first time KEY is offered; false every time after.
offer_once() {
    local marker
    [[ -n "$data" ]] || return 1
    marker="$data/offers/$(printf '%s' "$1" | sha256)"
    [[ -e "$marker" ]] && return 1
    mkdir -p "$data/offers" 2>/dev/null && printf '%s\n' "$1" > "$marker" 2>/dev/null
}

# The command Claude runs to record a confirmed list, paths single-quoted.
trust_cmd() {
    printf "'%s' '%s' '%s'" "$here/trust-approval-list.sh" "$1" "$data"
}

suggested="addOrEditJiraIssueWorklog, createJiraIssueLink, createConfluenceComment"
offer=""
proj_file="$proj/.claude/lean-atlassian.local.md"

if [[ "$settings_tier" == global && -e "$proj/.git" && ! "$proj" -ef "$HOME" ]] \
    && offer_once "copy:$proj"; then
    offer+="Your Atlassian settings come from the global file ${settings_file}, and this git repository has none of its own. "
    offer+="At a natural pause early in this session (never mid-task), ask once with AskUserQuestion whether to copy it into this repository as ${proj_file}. "
    offer+="Copy, don't move: leave the global file in place for other repositories. "
    offer+="Before copying, check \`git check-ignore -q .claude/lean-atlassian.local.md\`; if the file would not be ignored, offer to add \`.claude/*.local.md\` to .git/info/exclude, because the people cache must never be committed. "
    if ! has_approval_section "$settings_file"; then
        offer+="The file has no \`## Auto-approved operations\` section; offer to add one to the copy, suggesting ${suggested} and letting the user trim or extend it. "
    fi
    offer+="A copied list is a project list, which the approval hook ignores until confirmed: after copying, show the user the exact operations listed and, only on an explicit yes, run: $(trust_cmd "$proj_file")"
elif ! has_approval_section "$settings_file" && offer_once "add:$settings_file"; then
    offer+="The settings file ${settings_file} has no \`## Auto-approved operations\` section, so every Atlassian executeRead/executeWrite call prompts. "
    offer+="At a natural pause early in this session (never mid-task), ask once with AskUserQuestion whether to add one, suggesting ${suggested} and letting the user trim or extend it. Write only the operations the user approves. "
    if [[ "$settings_tier" == project ]]; then
        offer+="This is a project file, so the hook ignores its list until confirmed: after writing it, show the user the exact operations listed and, only on an explicit yes, run: $(trust_cmd "$settings_file")"
    fi
elif [[ "$settings_tier" == project && -n "$(approval_list "$settings_file")" ]] \
    && ! is_trusted "$settings_file" "$data" \
    && offer_once "confirm:$settings_file:$(list_hash "$settings_file")"; then
    ops="$(approval_list "$settings_file" | sort -u | paste -sd, - | sed 's/,/, /g')"
    offer+="The project settings file ${settings_file} lists Auto-approved operations that the user has not confirmed, so the approval hook is ignoring them: ${ops}. "
    offer+="At a natural pause early in this session (never mid-task), ask once with AskUserQuestion whether to trust exactly this list, noting that a repository can commit this file. "
    offer+="Only on an explicit yes, run: $(trust_cmd "$settings_file")"
fi

if [[ -n "$offer" ]]; then
    ctx+="\n\n## One-time offer (lean-atlassian)\n\n$(json_escape "$offer")\n\n"
    ctx+="If the user declines, do nothing more: this offer will not repeat."
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
exit 0
