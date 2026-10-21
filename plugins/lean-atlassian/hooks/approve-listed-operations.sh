#!/usr/bin/env bash
#
# PreToolUse hook for the lean-atlassian plugin.
#
# The v2 Atlassian MCP server exposes most operations only through a few
# generic runners — executeRead and executeWrite — that take the operation as
# `tool_input.name`. A permission rule can only name the runner, so allowing
# executeWrite allows every write in every Atlassian product. This hook
# restores per-operation control: it approves a runner call when the operation
# is listed in the user's settings file, and otherwise stays silent so the
# normal permission flow (prompt, or a matching allow/deny rule) decides.
#
# executeDestructive is never approved, whatever the list says. The hooks.json
# matcher already excludes it; the check below holds even if the matcher is
# widened.
#
# The settings file is resolved by the same first-match cascade as the
# SessionStart hook (see lib.sh). A global file's list is the user's own and is
# honoured as is. A project file's list is honoured only once the user has
# confirmed that exact set of operations (trust-approval-list.sh), because a
# repository can commit a .claude/lean-atlassian.local.md.
#
# The list is the body section `## Auto-approved operations`, one operation
# per `- ` bullet; anything after the name (a comment) is ignored:
#
#   ## Auto-approved operations
#
#   - addOrEditJiraIssueWorklog
#   - `createJiraIssueLink` — issue-to-issue links
#
# A hook "allow" skips the prompt but never overrides deny or ask rules in
# settings, so a deny rule still wins.
#
# Like the SessionStart hook, this one fails quietly: any missing piece (no jq,
# no settings file, an unconfirmed project list, unparseable input) emits `{}`
# and leaves the decision to the normal permission flow. It never denies.

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# No decision: let the normal permission flow handle the call.
pass() {
    echo '{}'
    exit 0
}

command -v jq >/dev/null 2>&1 || pass

input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)"
op="$(jq -r '.tool_input.name // empty' <<<"$input" 2>/dev/null)"
[[ -n "$tool" && -n "$op" ]] || pass

# Only the read/write runners are eligible.
case "$tool" in
    *__executeRead|*__executeWrite) ;;
    *) pass ;;
esac

resolve_settings || pass
if [[ "$settings_tier" == project ]]; then
    is_trusted "$settings_file" "${CLAUDE_PLUGIN_DATA:-}" || pass
fi

approval_list "$settings_file" | grep -qxF -- "$op" || pass

jq -n --arg reason "lean-atlassian: $op is listed under Auto-approved operations in $settings_src" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: $reason
    }
}'
exit 0
