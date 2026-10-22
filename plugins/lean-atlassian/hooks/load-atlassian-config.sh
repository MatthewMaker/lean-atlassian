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
#
# The same script also runs as the SubagentStart hook for the
# atlassian-researcher agent, with the event name as its only argument:
# subagents don't receive the main session's injected context. A subagent gets
# the settings alone — no skill pointer (it has no Skill tool) and no offers.

event="${1:-SessionStart}"

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

# Print the hook's JSON for $event with CTX as additionalContext.
emit() {
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$1"
}

# additionalContext is a single JSON string; the literal \n sequences below
# render as newlines in the injected context.
ctx="## Atlassian settings (lean-atlassian plugin)\n\n"
ctx+="Use these for every Atlassian MCP call. The cloud_id is already known — do NOT call getAccessibleAtlassianResources.\n"
ctx+="- cloud_id: ${cloud_id}\n"
ctx+="- site_url: ${site_url}\n"
# Only surface the optional identifiers that are actually configured.
[[ -n "$account_id" ]] && ctx+="- account_id: ${account_id} (your Jira accountId — use for assignment; do NOT call atlassianUserInfo)\n"
[[ -n "$project_key" ]] && ctx+="- project_key: ${project_key} (default Jira project for searches and new issues)\n"
# The skill's description can be dropped from the skill listing when many
# skills are installed, so name it here, with the rules that matter most if it
# never loads.
if [[ "$event" == SessionStart ]]; then
    ctx+="\nBefore any Atlassian MCP call, load the lean-atlassian:atlassian-mediation skill. Until it is loaded: reply with digests, never raw JSON; pass fields and maxResults to searchJiraIssuesUsingJql; pass content_format: markdown to getConfluenceContent.\n"
fi
ctx+="\n(loaded from ${src})"

# Offers are for the user's own session; a subagent never makes one.
if [[ "$event" != SessionStart ]]; then
    emit "$ctx"
    exit 0
fi

# --- One-time offers ---------------------------------------------------------
#
# Two offers, at most one per session, each made at most once — the marker is
# written when the offer is injected, so a declined offer doesn't come back:
#
#   copy     only the global file exists and the session is in a git repo:
#            offer to copy it into this repo's .claude/ (once per repository,
#            shared by all its worktrees)
#   add      the resolved file has no `## Auto-approved operations` section:
#            offer to add one (once per file)
#
# Without $CLAUDE_PLUGIN_DATA nothing can be remembered, so nothing is offered.

data="${CLAUDE_PLUGIN_DATA:-}"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"

# True (and recorded under KEY) the first time KEY is offered; false every
# time after. Any further arguments are older keys for the same offer: a
# marker under one of them also counts as offered, and is recorded under KEY
# too, so the next check finds it there.
offer_once() {
    local key marker first=""
    [[ -n "$data" ]] || return 1
    for key; do
        marker="$data/offers/$(printf '%s' "$key" | sha256)"
        first="${first:-$marker}"
        if [[ -e "$marker" ]]; then
            [[ "$marker" == "$first" ]] || printf '%s\n' "$1" > "$first" 2>/dev/null
            return 1
        fi
    done
    mkdir -p "$data/offers" 2>/dev/null && printf '%s\n' "$1" > "$first" 2>/dev/null
}

# The repository the session is in, as its git common directory: every
# worktree of one repository shares it. Falls back to the project path when
# git can't say (not installed, or a .git that isn't a repository).
repo_id() {
    local common
    common="$(git -C "$proj" rev-parse --git-common-dir 2>/dev/null)" \
        && (cd "$proj" && cd "$common" && pwd -P) 2>/dev/null \
        || printf '%s' "$proj"
}

suggested="addOrEditJiraIssueWorklog, createJiraIssueLink, createConfluenceComment"
offer=""
proj_file="$proj/.claude/lean-atlassian.local.md"

if [[ "$settings_tier" == global && -e "$proj/.git" && ! "$proj" -ef "$HOME" ]] \
    && offer_once "copy:$(repo_id)" "copy:$proj"; then
    offer+="Your Atlassian settings come from the global file ${settings_file}, and this git repository has none of its own. "
    offer+="At a natural pause early in this session (never mid-task), ask once with AskUserQuestion whether to copy it into this repository as ${proj_file}. "
    offer+="Copy, don't move: leave the global file in place for other repositories. "
    offer+="Before copying, check \`git check-ignore -q .claude/lean-atlassian.local.md\`; if the file would not be ignored, offer to add \`.claude/*.local.md\` to .git/info/exclude, because the people cache must never be committed. "
    if ! has_approval_section "$settings_file"; then
        offer+="The file has no \`## Auto-approved operations\` section; offer to add one to the copy, suggesting ${suggested} and letting the user trim or extend it. Write only the operations the user approves."
    fi
elif ! has_approval_section "$settings_file" && offer_once "add:$settings_file"; then
    offer+="The settings file ${settings_file} has no \`## Auto-approved operations\` section, so every Atlassian executeRead/executeWrite call prompts. "
    offer+="At a natural pause early in this session (never mid-task), ask once with AskUserQuestion whether to add one, suggesting ${suggested} and letting the user trim or extend it. Write only the operations the user approves."
fi

if [[ -n "$offer" ]]; then
    ctx+="\n\n## One-time offer (lean-atlassian)\n\n$(json_escape "$offer")\n\n"
    ctx+="If the user declines, do nothing more: this offer will not repeat."
fi

emit "$ctx"
exit 0
