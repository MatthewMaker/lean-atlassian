#!/usr/bin/env bash
#
# Tests the PreToolUse hook that auto-approves listed execute* operations.
#
# This hook grants permission, so the invariants worth pinning are the ones
# that keep it from approving too much: only listed operations, only the read
# and write runners (never executeDestructive), a project file's list only
# once the user has confirmed that exact set, and an exact name match. Like the
# SessionStart hook, every emission must be valid JSON, and anything it does
# not approve must come out as `{}`.
#
# Run from anywhere: tests/approve-operations.sh

set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/lean-atlassian/hooks"
HOOK="$HOOKS/approve-listed-operations.sh"
TRUST="$HOOKS/trust-approval-list.sh"
[[ -x "$HOOK" ]] || { echo "FAIL: hook not executable at $HOOK"; exit 1; }
[[ -x "$TRUST" ]] || { echo "FAIL: trust script not executable at $TRUST"; exit 1; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/proj/.claude" "$SB/cfg" "$SB/data"

failures=0
RUNNER=mcp__claude_ai_Atlassian_MCP

# Feed the hook a PreToolUse payload for one tool + operation; echo its stdout.
run_hook() {
    local tool="$1" op="$2"
    jq -nc --arg t "$tool" --arg o "$op" \
        '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {name: $o, cloudId: "x", inputs: {}}}' \
        | CLAUDE_PROJECT_DIR="$SB/proj" CLAUDE_CONFIG_DIR="$SB/cfg" CLAUDE_PLUGIN_DATA="$SB/data" "$HOOK"
}

# Write a settings file whose body lists the given bullet lines.
write_list() {
    local path="$1"; shift
    { printf -- '---\ncloud_id: "id"\n---\n\n## Auto-approved operations\n\n'
      for line in "$@"; do printf '%s\n' "$line"; done
      printf '\n## People cache (auto-maintained)\n\n- notAnOperation\n'
    } > "$path"
}

# Run the hook and check whether it approved, failing on invalid JSON.
expect() {
    local want="$1" label="$2" tool="$3" op="$4" out got
    out="$(run_hook "$tool" "$op")"
    if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
        echo "FAIL [$label]: emitted invalid JSON:"; printf '%s\n' "$out"
        failures=$((failures + 1)); return
    fi
    if [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" == allow ]]; then
        got=allow
    elif [[ "$(printf '%s' "$out" | jq -c .)" == "{}" ]]; then
        got=pass
    else
        echo "FAIL [$label]: neither allow nor {}:"; printf '%s\n' "$out"
        failures=$((failures + 1)); return
    fi
    if [[ "$got" != "$want" ]]; then
        echo "FAIL [$label]: expected $want, got $got"
        failures=$((failures + 1)); return
    fi
    echo "ok   [$label]"
}

# 1. Nothing configured.
expect pass "no settings file" "${RUNNER}__executeWrite" createJiraIssueLink

# shellcheck disable=SC2016  # the backticks are literal Markdown, not expansion
write_list "$SB/cfg/lean-atlassian.local.md" \
    '- addOrEditJiraIssueWorklog' \
    '- `createJiraIssueLink` — issue-to-issue links' \
    '  - getConfluenceSpace'

# 2. Listed operations are approved, with or without backticks and comments.
expect allow "listed write op" "${RUNNER}__executeWrite" addOrEditJiraIssueWorklog
expect allow "backticked op with trailing comment" "${RUNNER}__executeWrite" createJiraIssueLink
expect allow "indented bullet, read runner" "${RUNNER}__executeRead" getConfluenceSpace

# 3. Anything else falls through.
expect pass "unlisted op" "${RUNNER}__executeWrite" createConfluenceComment
expect pass "prefix of a listed op" "${RUNNER}__executeWrite" createJiraIssue
expect pass "bullet from another section" "${RUNNER}__executeWrite" notAnOperation
expect pass "regex metacharacters are literal" "${RUNNER}__executeWrite" 'create.*'

# 4. executeDestructive is never approved, even when listed.
write_list "$SB/cfg/lean-atlassian.local.md" '- deleteJiraIssue'
expect pass "destructive runner refused" "${RUNNER}__executeDestructive" deleteJiraIssue

# 5. Non-runner tools fall through even if their name is listed.
write_list "$SB/cfg/lean-atlassian.local.md" '- createJiraIssue'
expect pass "named tool is not a runner" "${RUNNER}__createJiraIssue" createJiraIssue

# 6. A project file's list grants nothing until confirmed — and, being first
#    in the cascade, it shadows the global list rather than merging with it.
write_list "$SB/cfg/lean-atlassian.local.md" '- createJiraIssueLink'
PROJ_FILE="$SB/proj/.claude/lean-atlassian.local.md"
write_list "$PROJ_FILE" '- createJiraIssueLink'
expect pass "unconfirmed project list ignored" "${RUNNER}__executeWrite" createJiraIssueLink

# 7. Once confirmed, it is honoured.
"$TRUST" "$PROJ_FILE" "$SB/data" >/dev/null || { echo "FAIL: trust script failed"; failures=$((failures + 1)); }
expect allow "confirmed project list" "${RUNNER}__executeWrite" createJiraIssueLink

# 8. Reordering and comments keep the confirmation; a new operation voids it.
# shellcheck disable=SC2016  # literal Markdown backticks
write_list "$PROJ_FILE" '- `createJiraIssueLink` — now with a comment'
expect allow "comment edit keeps confirmation" "${RUNNER}__executeWrite" createJiraIssueLink
write_list "$PROJ_FILE" '- createJiraIssueLink' '- addOrEditJiraIssueWorklog'
expect pass "added operation voids confirmation" "${RUNNER}__executeWrite" createJiraIssueLink

# 9. Re-confirming replaces the old entry rather than piling up.
"$TRUST" "$PROJ_FILE" "$SB/data" >/dev/null
expect allow "re-confirmed project list" "${RUNNER}__executeWrite" addOrEditJiraIssueWorklog
n="$(grep -c "$PROJ_FILE" "$SB/data/trusted-lists")"
if [[ "$n" == 1 ]]; then echo "ok   [one trust entry per file]"
else echo "FAIL [one trust entry per file]: found $n"; failures=$((failures + 1)); fi

# 10. Without a plugin data dir nothing is confirmed, so project lists pass.
out="$(jq -nc '{tool_name: "mcp__claude_ai_Atlassian_MCP__executeWrite", tool_input: {name: "createJiraIssueLink"}}' \
    | CLAUDE_PROJECT_DIR="$SB/proj" CLAUDE_CONFIG_DIR="$SB/cfg" CLAUDE_PLUGIN_DATA="" "$HOOK")"
if [[ "$(jq -c . <<<"$out")" == "{}" ]]; then echo "ok   [no data dir -> project list ignored]"
else echo "FAIL [no data dir]: got $out"; failures=$((failures + 1)); fi

# 11. Legacy global filename still resolves (no project file in the way).
rm -f "$SB/proj/.claude"/*.md "$SB/cfg"/*.md
write_list "$SB/cfg/private-atlassian.local.md" '- createJiraIssueLink'
expect allow "legacy global name" "${RUNNER}__executeWrite" createJiraIssueLink

# 12. A project dir whose .claude IS the config dir (session in $HOME) reads
#     the file as global, so it needs no confirmation.
mkdir -p "$SB/home"
ln -s "$SB/cfg" "$SB/home/.claude"
out="$(jq -nc '{tool_name: "mcp__claude_ai_Atlassian_MCP__executeWrite", tool_input: {name: "createJiraIssueLink"}}' \
    | CLAUDE_PROJECT_DIR="$SB/home" CLAUDE_CONFIG_DIR="$SB/cfg" CLAUDE_PLUGIN_DATA="$SB/data" "$HOOK")"
if [[ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out")" == allow ]]; then
    echo "ok   [project .claude == config dir -> global]"
else echo "FAIL [project .claude == config dir]: got $out"; failures=$((failures + 1)); fi

# 13. Fenced code is documentation, not a list. A heading or bullets inside a
#     fence grant nothing, and a fence inside the real section hides its bullets.
rm -f "$SB/cfg"/*.md "$SB/home/.claude"
# shellcheck disable=SC2016  # literal Markdown fences
printf -- '---\ncloud_id: "id"\n---\n\n```markdown\n## Auto-approved operations\n\n- createJiraIssueLink\n```\n\n- notAnOperation\n' \
    > "$SB/cfg/lean-atlassian.local.md"
expect pass "fenced heading grants nothing" "${RUNNER}__executeWrite" createJiraIssueLink
# shellcheck disable=SC2016  # literal Markdown fences
write_list "$SB/cfg/lean-atlassian.local.md" '- addOrEditJiraIssueWorklog' '~~~' '- createJiraIssueLink' '~~~'
expect allow "bullet outside fence still listed" "${RUNNER}__executeWrite" addOrEditJiraIssueWorklog
expect pass "bullet inside fence in the section" "${RUNNER}__executeWrite" createJiraIssueLink

# 14. The shipped example, copied and filled in as the README says, grants
#     nothing: its sample list is fenced documentation.
EXAMPLE="$(cd "$HOOKS/../../.." && pwd)/.claude/lean-atlassian.local.md.example"
sed 's/your-cloud-id-here/real-id/' "$EXAMPLE" > "$SB/cfg/lean-atlassian.local.md"
for op in addOrEditJiraIssueWorklog createJiraIssueLink createConfluenceComment; do
    expect pass "example file: $op not approved" "${RUNNER}__executeWrite" "$op"
done

# 15. Garbage on stdin is not an error.
out="$(printf 'not json' | CLAUDE_CONFIG_DIR="$SB/cfg" "$HOOK")"
if [[ "$(printf '%s' "$out" | jq -c . 2>/dev/null)" == "{}" ]]; then
    echo "ok   [unparseable input -> {}]"
else
    echo "FAIL [unparseable input]: got $out"; failures=$((failures + 1))
fi

if (( failures )); then echo; echo "$failures check(s) failed"; exit 1; fi
echo; echo "all operation-approval checks passed"
