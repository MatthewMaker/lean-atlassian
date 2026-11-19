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
    settings_text "$file" | awk -v key="$1" '
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
    '
}

cloud_id="$(read_field cloud_id)"
site_url="$(read_field site_url)"
# Optional scalars — broadly useful and cheap, so inject them too when present.
# account_id saves an atlassianUserInfo call (assignment, "my issues");
# project_key saves a listJiraProjects call (default project scope).
account_id="$(read_field account_id)"
project_key="$(read_field project_key)"
# link_issue_keys asks for every Jira key in a reply to be a browse link.
link_issue_keys="$(read_field link_issue_keys)"

# Print the `- key: value` bullets of the body section `## Current sprint`, as
# `key=value` lines, skipping fenced code (the .example file's sample). Claude
# keeps this section up to date; it's the one body section injected, because
# it's a single line and it goes stale on a known date.
read_sprint() {
    settings_text "$file" | awk '
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        /^## / { in_s = ($0 ~ /^## Current sprint/); next }
        in_s && /^[[:space:]]*- [A-Za-z]+:/ {
            sub(/^[[:space:]]*- /, "")
            k = $0; sub(/:.*/, "", k)
            v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
            gsub(/`/, "", v)
            print tolower(k) "=" v
        }
    '
}

# Describe the cached sprint for the injected context: the id while it's
# current, a refresh instruction once its end has passed (or the section is
# unusable), nothing when there's no section. `ends` is Jira's endDate, a UTC
# timestamp compared in UTC, or a bare date compared with the local date.
sprint_line() {
    local line k v board="" name="" id="" ends="" now refresh
    while IFS= read -r line; do
        k="${line%%=*}" v="${line#*=}"
        case "$k" in
            board) board="$v" ;; sprint) name="$v" ;; id) id="$v" ;; ends) ends="$v" ;;
        esac
    done < <(read_sprint)
    [[ -n "$board$name$id$ends" ]] || return 0

    refresh="before moving an issue into a sprint, look up the active one with executeRead name getJiraBoardSprintData, inputs {boardId: \"${board:-<board id>}\", includeIssues: false}, responseFields [\"resolvedSprint\"], and rewrite the Current sprint section of ${settings_src} with its id, name and endDate."
    if [[ "$ends" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} ]]; then
        now="$(date -u +%Y-%m-%dT%H:%M:%S)"
        ends="${ends:0:19}"
    elif [[ "$ends" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        now="$(date +%Y-%m-%d)"
    else
        printf '%s' "- current sprint: the cached sprint is unreadable; ${refresh}"
        return 0
    fi
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        printf '%s' "- current sprint: the cached sprint has no numeric id; ${refresh}"
    elif [[ "$now" > "$ends" ]]; then
        printf '%s' "- current sprint: expired (${name:-id $id} ended ${ends}); ${refresh}"
    else
        printf '%s' "- current sprint: ${name:-unnamed}, id ${id} (board ${board:-unknown}, ends ${ends}). Use the id as transitionJiraIssue's sprintId; createJiraIssue takes assignToSprint: \"active\"."
    fi
}

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
# Escaped whole: the name and dates come from a file Claude writes.
sprint="$(json_escape "$(sprint_line)")"

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
[[ -n "$sprint" ]] && ctx+="${sprint}\n"
# Spelled-out case match rather than ${var,,}: macOS ships bash 3.2.
if [[ -n "$site_url" ]] && [[ "$link_issue_keys" == [Tt][Rr][Uu][Ee] || "$link_issue_keys" == [Yy][Ee][Ss] || "$link_issue_keys" == 1 ]]; then
    ctx+="\nWrite every Jira issue key in a reply as a Markdown link, e.g. [PROJ-123](${site_url%/}/browse/PROJ-123), in tables and lists too. Text meant to be pasted elsewhere (code blocks, commit messages, chat drafts, files on disk) keeps its destination's conventions.\n"
fi
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
#   copy     only the global file exists and the session is in a git repo's
#            main checkout: offer to copy it into that checkout's .claude/
#            (once per repository). Not offered in a linked worktree: a copy
#            there is read by that worktree only and removed with it.
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

# True when the session is in a linked worktree (one made by `git worktree
# add`, including every worktree of a bare repository): its own git directory
# differs from the repository's common one. False when git can't say.
in_linked_worktree() {
    local own
    own="$(git -C "$proj" rev-parse --absolute-git-dir 2>/dev/null)" \
        && own="$(cd "$own" && pwd -P)" \
        && [[ "$own" != "$(repo_id)" ]]
}

suggested="addOrEditJiraIssueWorklog, createJiraIssueLink, createConfluenceComment"
offer=""
proj_file="$proj/.claude/lean-atlassian.local.md"

if [[ "$settings_tier" == global && -e "$proj/.git" && ! "$proj" -ef "$HOME" ]] \
    && ! in_linked_worktree && offer_once "copy:$(repo_id)" "copy:$proj"; then
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
