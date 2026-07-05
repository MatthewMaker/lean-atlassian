#!/usr/bin/env bash
#
# SessionStart hook for the private-atlassian plugin.
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
# Cascade — first match wins:
#   1. Per-project:  $CLAUDE_PROJECT_DIR/.claude/private-atlassian.local.md
#   2. Global:       ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/private-atlassian.local.md
#
# Emitting `{}` (no additionalContext) when nothing is configured keeps the
# hook silent; the commands/skill then fall back to a one-time MCP lookup.

# Resolve the project root (override tier) and config dir (global tier).
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

file=""
src=""
if [[ -f "$proj/.claude/private-atlassian.local.md" ]]; then
    file="$proj/.claude/private-atlassian.local.md"
    src="project .claude/private-atlassian.local.md"
elif [[ -f "$cfg/private-atlassian.local.md" ]]; then
    file="$cfg/private-atlassian.local.md"
    src="$cfg/private-atlassian.local.md"
fi

# Nothing configured anywhere → stay silent and let the MCP fallback handle it.
if [[ -z "$file" ]]; then
    echo '{}'
    exit 0
fi

# Read one YAML frontmatter field: strip the key, surrounding quotes, and
# trailing whitespace. Returns empty (never errors) when the key is absent.
read_field() {
    grep -m1 "^$1:" "$file" 2>/dev/null \
        | sed -E "s/^$1:[[:space:]]*//; s/[[:space:]]+$//; s/^[\"']//; s/[\"']$//"
}

cloud_id="$(read_field cloud_id)"
site_url="$(read_field site_url)"
# Optional scalars — broadly useful and cheap, so inject them too when present.
# account_id saves an atlassianUserInfo call (assignment, "my issues");
# project_key saves a getVisibleJiraProjects call (default project scope).
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
ctx="## Atlassian settings (private-atlassian plugin)\n\n"
ctx+="Use these for every Atlassian MCP call. The cloud_id is already known — do NOT call getAccessibleAtlassianResources.\n"
ctx+="- cloud_id: ${cloud_id}\n"
ctx+="- site_url: ${site_url}\n"
# Only surface the optional identifiers that are actually configured.
[[ -n "$account_id" ]] && ctx+="- account_id: ${account_id} (your Jira accountId — use for assignment; do NOT call atlassianUserInfo)\n"
[[ -n "$project_key" ]] && ctx+="- project_key: ${project_key} (default Jira project for searches and new issues)\n"
ctx+="\n(loaded from ${src})"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
exit 0
