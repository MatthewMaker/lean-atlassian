#!/usr/bin/env bash
#
# Tests the SessionStart hook's one-time offers.
#
# Each offer must fire under exactly its condition, at most once (a declined
# offer never comes back), and never more than one per session. The confirm
# offer re-arms only when the set of listed operations changes. Without a
# plugin data dir nothing can be remembered, so nothing is offered. And as
# with every hook emission, the output must stay valid JSON.
#
# Run from anywhere: tests/offers.sh

set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/lean-atlassian/hooks"
HOOK="$HOOKS/load-atlassian-config.sh"
TRUST="$HOOKS/trust-approval-list.sh"
[[ -x "$HOOK" ]] || { echo "FAIL: hook not executable at $HOOK"; exit 1; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/proj/.claude" "$SB/proj/.git" "$SB/cfg" "$SB/data"
PROJ_FILE="$SB/proj/.claude/lean-atlassian.local.md"
GLOBAL_FILE="$SB/cfg/lean-atlassian.local.md"

failures=0

# Run the hook and print the offer section of its context (empty if none).
offer() {
    local out
    out="$(CLAUDE_PROJECT_DIR="$SB/proj" CLAUDE_CONFIG_DIR="$SB/cfg" CLAUDE_PLUGIN_DATA="${DATA-$SB/data}" "$HOOK")"
    if ! jq -e . >/dev/null 2>&1 <<<"$out"; then
        echo "INVALID-JSON: $out"; return
    fi
    jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" | sed -n '/## One-time offer/,$p'
}

# Write a configured settings file, optionally with an approval list.
write_settings() {
    local path="$1"; shift
    { printf -- '---\ncloud_id: "id"\nsite_url: "https://example.test"\n---\n'
      if (( $# )); then
          printf '\n## Auto-approved operations\n\n'
          for op in "$@"; do printf -- '- %s\n' "$op"; done
      fi
    } > "$path"
}

# Assert the next run's offer is of KIND (copy|add|confirm|none).
expect_offer() {
    local want="$1" label="$2" text got
    text="$(offer)"
    case "$text" in
        INVALID-JSON*)              got=invalid ;;
        "")                         got=none ;;
        *"copy it into this"*)      got=copy ;;
        *"has no \`## Auto-approved"*) got=add ;;
        *"has not confirmed"*)      got=confirm ;;
        *)                          got=unknown ;;
    esac
    if [[ "$got" != "$want" ]]; then
        echo "FAIL [$label]: expected $want, got $got"; [[ -n "$text" ]] && printf '%s\n' "$text"
        failures=$((failures + 1)); return
    fi
    echo "ok   [$label]"
}

# 1. Without a data dir nothing is offered, even when every condition holds.
write_settings "$GLOBAL_FILE"
DATA="" expect_offer none "no data dir -> no offers"

# 2. Global only, in a git repo: copy offer, once.
expect_offer copy "global only in git repo -> copy"
# 3. Next session the copy offer is spent, so the missing list is offered.
expect_offer add "copy spent -> add list to global"
# 4. Then nothing.
expect_offer none "both spent -> silent"

# 5. A project file without a list gets its own add offer.
write_settings "$PROJ_FILE"
expect_offer add "project file without list -> add"
expect_offer none "project add spent -> silent"

# 6. An unconfirmed project list: confirm offer, once per set of operations.
write_settings "$PROJ_FILE" createJiraIssueLink
expect_offer confirm "unconfirmed project list -> confirm"
expect_offer none "confirm spent -> silent"
write_settings "$PROJ_FILE" createJiraIssueLink addOrEditJiraIssueWorklog
expect_offer confirm "changed list -> confirm again"

# 7. A confirmed list is never offered.
write_settings "$PROJ_FILE" createJiraIssueLink addOrEditJiraIssueWorklog createConfluenceComment
"$TRUST" "$PROJ_FILE" "$SB/data" >/dev/null
expect_offer none "confirmed list -> silent"

# 8. The confirm offer names the operations and carries a runnable command.
write_settings "$PROJ_FILE" 'weird"op'
text="$(offer)"
if grep -qF 'weird"op' <<<"$text" && grep -qF "trust-approval-list.sh' '$PROJ_FILE' '$SB/data'" <<<"$text"; then
    echo "ok   [confirm offer names ops and the trust command; quotes stay valid JSON]"
else
    echo "FAIL [confirm offer content]:"; printf '%s\n' "$text"; failures=$((failures + 1))
fi

# 9. Outside a git repo, a global-only setup gets no copy offer.
rm -rf "$SB/proj/.git" "$SB/data" "$PROJ_FILE"
mkdir -p "$SB/data"
write_settings "$GLOBAL_FILE" createJiraIssueLink
expect_offer none "not a git repo, global has list -> silent"

# 10. A file whose only `## Auto-approved operations` is a fenced sample (the
#     shipped example) has no list, so it gets the add offer.
rm -rf "$SB/data"; mkdir -p "$SB/data"
EXAMPLE="$(cd "$HOOKS/../../.." && pwd)/.claude/lean-atlassian.local.md.example"
sed 's/your-cloud-id-here/real-id/' "$EXAMPLE" > "$GLOBAL_FILE"
expect_offer add "example file (fenced sample only) -> add"

if (( failures )); then echo; echo "$failures check(s) failed"; exit 1; fi
echo; echo "all one-time offer checks passed"
