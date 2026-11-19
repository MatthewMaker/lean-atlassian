#!/usr/bin/env bash
#
# Tests the PostToolUse hook that compares a Jira write's request with the
# issue it returns.
#
# Every write case below was reproduced against the live v2 server on
# 2026-11-19 on throwaway issues: each call reported success and
# left the field unset. The fixtures are trimmed copies of those responses
# with placeholder ids. The silent cases pin the other direction: a write that
# did apply must not get a note, and anything unparseable emits `{}`.
#
# Run from anywhere: tests/check-write-echo.sh

set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/lean-atlassian/hooks/check-write-echo.sh"
[[ -x "$HOOK" ]] || { echo "FAIL: hook not executable at $HOOK"; exit 1; }

failures=0
ME="712020:aaaaaaaa-1111-2222-3333-444444444444"
ME_OBJ="{\"accountId\": \"$ME\", \"displayName\": \"Alice Smith\", \"emailAddress\": \"alice@example.com\"}"

# Build a PostToolUse payload: TOOL, its INPUT, and the returned issue's
# FIELDS (merged over empty defaults). AGE is how many seconds ago the issue
# was last updated; ZONE "cst" writes that time with a -0600 offset, as Jira
# does for a US Central site.
payload() {
    local tool="$1" input="$2" fields="${3:-"{}"}" age="${4:-5}" zone="${5:-utc}"
    jq -nc --arg t "mcp__claude_ai_Atlassian_MCP__$tool" --argjson in "$input" \
        --argjson f "$fields" --argjson age "$age" --arg zone "$zone" '
        ((now - $age) | floor) as $u
        | (if $zone == "cst" then ($u - 21600 | strftime("%Y-%m-%dT%H:%M:%S.123-0600"))
           else ($u | strftime("%Y-%m-%dT%H:%M:%S.123+0000")) end) as $updated
        | {hook_event_name: "PostToolUse", tool_name: $t, tool_input: $in,
           tool_response: ({issues: {nodes: [{key: "PROJ-1", fields: (
               {summary: "s", components: [], labels: [], assignee: null,
                priority: {name: "Medium"}, updated: $updated} + $f)}]}} | tojson)}'
}

# Run the hook on stdin; fail on anything that isn't valid JSON.
run() {
    local label="$1" out
    out="$("$HOOK")"
    if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
        echo "FAIL [$label]: emitted invalid JSON:"; printf '%s\n' "$out"
        failures=$((failures + 1)); return 1
    fi
    printf '%s' "$out"
}

# Expect a note whose text contains every PATTERN (fixed strings).
expect_note() {
    local label="$1" input="$2"; shift 2
    local out ctx p
    out="$(printf '%s' "$input" | run "$label")" || return
    ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
    if [[ -z "$ctx" || "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" != PostToolUse ]]; then
        echo "FAIL [$label]: expected a PostToolUse note, got: $out"
        failures=$((failures + 1)); return
    fi
    for p in "$@"; do
        if [[ "$ctx" != *"$p"* ]]; then
            echo "FAIL [$label]: note lacks '$p':"; printf '%s\n' "$ctx"
            failures=$((failures + 1)); return
        fi
    done
}

# Expect exactly `{}`.
expect_silent() {
    local label="$1" input="$2" out
    out="$(printf '%s' "$input" | run "$label")" || return
    if [[ "$(printf '%s' "$out" | jq -c .)" != "{}" ]]; then
        echo "FAIL [$label]: expected {}, got: $out"
        failures=$((failures + 1))
    fi
}

# --- Silent failures seen live ------------------------------------------------

# The bare string under `fields` left the assignee null,
# and `updated` didn't move.
expect_note "edit: bare-string assignee in fields" \
    "$(payload editJiraIssue "{\"issueIdOrKey\": \"PROJ-1\", \"fields\": {\"assignee\": \"$ME\"}}" '{}' 600 cst)" \
    "assignee: asked for $ME, but it is unset" '{"accountId": "…"}'

# The same with a valid field alongside: labels saved and `updated` moved, so
# only the echo comparison catches the assignee.
expect_note "edit: bare-string assignee next to a field that saved" \
    "$(payload editJiraIssue "{\"issueIdOrKey\": \"PROJ-1\", \"fields\": {\"assignee\": \"$ME\", \"labels\": [\"x\"]}}" '{"labels": ["x"]}' 2)" \
    "assignee: asked for $ME"

# camelCase `additionalFields` dropped whole.
expect_note "create: camelCase additionalFields" \
    "$(payload createJiraIssue '{"projectKey": "PROJ", "summary": "s", "issueType": "Task", "additionalFields": {"components": [{"name": "Server"}]}}')" \
    "components: server missing" "no parameter \`additionalFields\`" "do not create it again"

# components and the sprint field as top-level parameters.
expect_note "create: top-level components and customfield" \
    "$(payload createJiraIssue '{"projectKey": "PROJ", "summary": "s", "issueType": "Task", "components": [{"name": "Server"}], "customfield_10020": 875}')" \
    "components: server missing" "\`components\`, \`customfield_10020\`"

expect_note "create: priority not applied" \
    "$(payload createJiraIssue '{"projectKey": "PROJ", "summary": "s", "issueType": "Task", "additional_fields": {"priority": {"name": "High"}}}')" \
    "priority: asked for high, but it is Medium"

# A field the response doesn't echo, on an edit that changed nothing.
expect_note "edit: non-echoed field, updated left behind" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "fields": {"customfield_10010": 3}}' '{}' 600)" \
    "no change recorded" "customfield_10010"
expect_note "edit: -0600 offset parsed" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "additional_fields": {"Story Points": 3}}' '{}' 600 cst)" \
    "no change recorded" "Story Points"

expect_note "edit: clearing the assignee didn't" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "fields": {"assignee": null}}' "{\"assignee\": $ME_OBJ}")" \
    "asked to clear it, but it is Alice Smith"

# --- Writes that applied ---------------------------------------------------------

expect_silent "edit: object-form assignee" \
    "$(payload editJiraIssue "{\"issueIdOrKey\": \"PROJ-1\", \"fields\": {\"assignee\": {\"accountId\": \"$ME\"}}}" "{\"assignee\": $ME_OBJ}")"
expect_silent "edit: bare string in additional_fields" \
    "$(payload editJiraIssue "{\"issueIdOrKey\": \"PROJ-1\", \"additional_fields\": {\"assignee\": \"$ME\"}}" "{\"assignee\": $ME_OBJ}")"
expect_silent "edit: assignee by email" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "additional_fields": {"assignee": "ALICE@example.com"}}' "{\"assignee\": $ME_OBJ}")"
expect_silent "create: everything in its place" \
    "$(payload createJiraIssue "{\"projectKey\": \"PROJ\", \"summary\": \"s\", \"issueType\": \"Task\", \"assignee\": \"$ME\", \"labels\": [\"a\"], \"priority\": \"High\", \"assignToSprint\": \"active\", \"additional_fields\": {\"components\": [{\"name\": \"server\"}]}}" \
        "{\"assignee\": $ME_OBJ, \"labels\": [\"a\"], \"priority\": {\"name\": \"High\"}, \"components\": [{\"name\": \"Server\"}]}")"
expect_silent "edit: non-echoed field, updated just now" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "fields": {"customfield_10010": 3}}' '{}' 3)"
expect_silent "edit: echoed field already held the value" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "fields": {"labels": ["x"]}}' '{"labels": ["x"]}' 600)"
expect_silent "edit: rank only" \
    "$(payload editJiraIssue '{"issueIdOrKey": "PROJ-1", "rankBeforeIssue": "PROJ-2"}' '{}' 600)"

# --- Payloads the hook must leave alone -----------------------------------------

expect_silent "response as MCP content blocks" \
    "$(payload editJiraIssue "{\"issueIdOrKey\": \"PROJ-1\", \"fields\": {\"assignee\": {\"accountId\": \"$ME\"}}}" "{\"assignee\": $ME_OBJ}" \
        | jq -c '.tool_response = [{type: "text", text: .tool_response}]')"
expect_note "content blocks still compared" \
    "$(payload editJiraIssue "{\"issueIdOrKey\": \"PROJ-1\", \"fields\": {\"assignee\": \"$ME\"}}" \
        | jq -c '.tool_response = [{type: "text", text: .tool_response}]')" \
    "assignee: asked for"
expect_silent "error response" \
    "$(payload createJiraIssue '{"additionalFields": {}}' | jq -c '.tool_response = ({data: {error: "TRANSITION_FAILED"}} | tojson)')"
expect_silent "response not JSON" \
    "$(payload createJiraIssue '{"additionalFields": {}}' | jq -c '.tool_response = "Error: something broke"')"
expect_silent "other tool" \
    "$(payload transitionJiraIssue '{"fields": {"resolution": "x"}}')"
expect_silent "stdin not JSON" "not json at all"
expect_silent "empty stdin" ""

if (( failures )); then
    echo "$failures check-write-echo test(s) failed"
    exit 1
fi
echo "check-write-echo: all tests passed"
