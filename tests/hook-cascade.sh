#!/usr/bin/env bash
#
# Tests the SessionStart hook's settings-file cascade.
#
# The hook is the plugin's only executable code, and its failure mode is quiet:
# when it finds nothing it prints `{}` and the session simply goes without the
# injected cloud_id. A malformed emission is worse — it lands in every session
# of every install. So the invariants worth pinning are (a) the precedence
# order, (b) that the legacy filename still resolves, and (c) that whatever is
# emitted is always parseable JSON.
#
# Run from anywhere: tests/hook-cascade.sh

set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/lean-atlassian/hooks/load-atlassian-config.sh"
[[ -x "$HOOK" ]] || { echo "FAIL: hook not executable at $HOOK"; exit 1; }

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/proj/.claude" "$SB/cfg"

failures=0

# Run the hook against the sandbox tiers and echo its raw stdout.
run_hook() {
    CLAUDE_PROJECT_DIR="$SB/proj" CLAUDE_CONFIG_DIR="$SB/cfg" "$HOOK"
}

# Write a settings file with a given cloud_id, plus any extra frontmatter lines.
write_settings() {
    local path="$1" id="$2"; shift 2
    { printf -- '---\ncloud_id: "%s"\nsite_url: "https://example.test"\n' "$id"
      for line in "$@"; do printf '%s\n' "$line"; done
      printf -- '---\n'
    } > "$path"
}

# Every emission must parse as JSON, no matter which branch produced it.
assert_json() {
    local label="$1" out="$2"
    if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
        echo "FAIL [$label]: emitted invalid JSON:"; printf '%s\n' "$out"
        failures=$((failures + 1)); return 1
    fi
}

# Assert the hook stayed silent — `{}` with no additionalContext.
assert_silent() {
    local label="$1" out; out="$(run_hook)"
    assert_json "$label" "$out" || return
    if [[ "$(printf '%s' "$out" | jq -c .)" != "{}" ]]; then
        echo "FAIL [$label]: expected {} but got:"; printf '%s\n' "$out"
        failures=$((failures + 1)); return
    fi
    echo "ok   [$label]"
}

# Assert which cloud_id won, and optionally which file it was read from.
assert_resolves() {
    local label="$1" want_id="$2" want_src="${3:-}" out ctx
    out="$(run_hook)"
    assert_json "$label" "$out" || return
    ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
    if ! grep -qF -- "- cloud_id: $want_id" <<<"$ctx"; then
        echo "FAIL [$label]: expected cloud_id $want_id in:"; printf '%s\n' "$ctx"
        failures=$((failures + 1)); return
    fi
    if [[ -n "$want_src" ]] && ! grep -qF -- "(loaded from $want_src)" <<<"$ctx"; then
        echo "FAIL [$label]: expected source '$want_src' in:"; printf '%s\n' "$ctx"
        failures=$((failures + 1)); return
    fi
    echo "ok   [$label]"
}

# 1. Nothing configured anywhere.
assert_silent "no config -> {}"

# 2. Legacy global name alone still resolves (back-compat after the rename).
write_settings "$SB/cfg/private-atlassian.local.md" GLOBAL-LEGACY
assert_resolves "legacy global resolves" GLOBAL-LEGACY "$SB/cfg/private-atlassian.local.md"

# 3. Current name beats legacy within the same tier.
write_settings "$SB/cfg/lean-atlassian.local.md" GLOBAL-CURRENT
assert_resolves "current beats legacy (global)" GLOBAL-CURRENT

# 4. Project tier beats global even under the legacy name — the per-project
#    override must not be defeated by a newer filename one tier up.
write_settings "$SB/proj/.claude/private-atlassian.local.md" PROJ-LEGACY
assert_resolves "project legacy beats global current" PROJ-LEGACY \
    "project .claude/private-atlassian.local.md"

# 5. Full cascade populated: project + current name wins outright.
write_settings "$SB/proj/.claude/lean-atlassian.local.md" PROJ-CURRENT
assert_resolves "project current wins cascade" PROJ-CURRENT \
    "project .claude/lean-atlassian.local.md"

# 6. Optional scalars appear only when configured.
rm -f "$SB/proj/.claude"/*.md "$SB/cfg"/*.md
write_settings "$SB/cfg/lean-atlassian.local.md" WITH-OPTIONALS \
    'account_id: "712020:abc"' 'project_key: "MYPROJ"'
assert_resolves "optional scalars present" WITH-OPTIONALS
out="$(run_hook)"; ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
for want in 'account_id: 712020:abc' 'project_key: MYPROJ'; do
    grep -qF -- "- $want" <<<"$ctx" || { echo "FAIL: missing $want"; failures=$((failures + 1)); }
done
write_settings "$SB/cfg/lean-atlassian.local.md" NO-OPTIONALS
ctx="$(run_hook | jq -r '.hookSpecificOutput.additionalContext')"
for absent in account_id project_key; do
    grep -qF -- "- $absent:" <<<"$ctx" && { echo "FAIL: $absent leaked when unset"; failures=$((failures + 1)); }
done
echo "ok   [optional scalars gated on presence]"

# 7. The unedited example placeholder counts as unconfigured, not as a cloud_id.
printf -- '---\ncloud_id: "your-cloud-id-here"\n---\n' > "$SB/cfg/lean-atlassian.local.md"
assert_silent "placeholder -> {}"

# 8. Values containing JSON metacharacters must not break the emission.
write_settings "$SB/cfg/lean-atlassian.local.md" 'weird"id\with'
assert_resolves 'quotes and backslashes stay valid JSON' 'weird"id\with'

if (( failures )); then echo; echo "$failures check(s) failed"; exit 1; fi
echo; echo "all hook cascade checks passed"
