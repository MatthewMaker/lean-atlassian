#!/usr/bin/env bash
#
# Tests the SessionStart hook's one-time offers.
#
# Each offer must fire under exactly its condition, at most once (a declined
# offer never comes back), and never more than one per session. Without a
# plugin data dir nothing can be remembered, so nothing is offered. And as
# with every hook emission, the output must stay valid JSON.
#
# Run from anywhere: tests/offers.sh

set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/lean-atlassian/hooks"
HOOK="$HOOKS/load-atlassian-config.sh"
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

# Assert the next run's offer is of KIND (copy|add|none).
expect_offer() {
    local want="$1" label="$2" text got
    text="$(offer)"
    case "$text" in
        INVALID-JSON*)              got=invalid ;;
        "")                         got=none ;;
        *"copy it into this"*)      got=copy ;;
        *"has no \`## Auto-approved"*) got=add ;;
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

# 6. A project file that already has a list gets no offer.
write_settings "$PROJ_FILE" createJiraIssueLink
expect_offer none "project file with list -> silent"

# 7. Outside a git repo, a global-only setup gets no copy offer.
rm -rf "$SB/proj/.git" "$SB/data" "$PROJ_FILE"
mkdir -p "$SB/data"
write_settings "$GLOBAL_FILE" createJiraIssueLink
expect_offer none "not a git repo, global has list -> silent"

# 8. A file whose only `## Auto-approved operations` is a fenced sample (the
#     shipped example) has no list, so it gets the add offer.
rm -rf "$SB/data"; mkdir -p "$SB/data"
EXAMPLE="$(cd "$HOOKS/../../.." && pwd)/.claude/lean-atlassian.local.md.example"
sed 's/your-cloud-id-here/real-id/' "$EXAMPLE" > "$GLOBAL_FILE"
expect_offer add "example file (fenced sample only) -> add"

# 9. A subagent never gets an offer, and doesn't spend one: the next main
#    session still makes it.
rm -rf "$SB/data"; mkdir -p "$SB/data" "$SB/proj/.git"
write_settings "$GLOBAL_FILE"
out="$(CLAUDE_PROJECT_DIR="$SB/proj" CLAUDE_CONFIG_DIR="$SB/cfg" CLAUDE_PLUGIN_DATA="$SB/data" "$HOOK" SubagentStart)"
if jq -e . >/dev/null 2>&1 <<<"$out" \
    && ! jq -r '.hookSpecificOutput.additionalContext' <<<"$out" | grep -qF 'One-time offer'; then
    echo "ok   [SubagentStart -> no offer]"
else
    echo "FAIL [SubagentStart -> no offer]: got $out"; failures=$((failures + 1))
fi
expect_offer copy "offer not spent by a subagent -> copy"

if (( failures )); then echo; echo "$failures check(s) failed"; exit 1; fi
echo; echo "all one-time offer checks passed"
