#!/usr/bin/env bash
#
# Structural checks on the marketplace and plugin manifests.
#
# `claude plugin validate` covers schema correctness; these are the
# repo-specific invariants it can't know about — chiefly that the version is
# declared exactly once. When plugin.json and the marketplace entry both
# declare a version, plugin.json silently wins, so a stale duplicate is
# invisible until someone notices installs pinned to the wrong number.
#
# Run from anywhere: tests/manifest-invariants.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
ok()   { echo "ok   $*"; }

MARKET=.claude-plugin/marketplace.json

# 1. Every tracked JSON file must parse.
while IFS= read -r f; do
    jq -e . "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
done < <(git ls-files '*.json')
ok "all tracked JSON parses"

# 2. Marketplace-level required fields.
for field in name owner plugins; do
    [[ "$(jq -r "has(\"$field\")" "$MARKET")" == true ]] || fail "$MARKET missing '$field'"
done
[[ "$(jq -r '.owner | has("name")' "$MARKET")" == true ]] || fail "$MARKET owner missing 'name'"
ok "marketplace required fields present"

# 3. Marketplace name should be lowercase kebab-case, matching how every other
#    marketplace is registered (users type it in `/plugin install x@<name>`).
name="$(jq -r .name "$MARKET")"
[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || fail "marketplace name '$name' is not kebab-case"
ok "marketplace name is kebab-case"

# 4. Per-plugin entry checks.
while IFS=$'\t' read -r pname psource phasver; do
    [[ -n "$pname" ]] || continue
    # Relative sources must actually exist, or installs 404 after a rename.
    if [[ "$psource" == ./* ]]; then
        [[ -d "$psource" ]] || fail "plugin '$pname' source '$psource' does not exist"
        manifest="$psource/.claude-plugin/plugin.json"
        [[ -f "$manifest" ]] || fail "plugin '$pname' has no $manifest"
        # The version lives in plugin.json alone; see the header note.
        [[ "$phasver" == false ]] \
            || fail "plugin '$pname' declares 'version' in $MARKET; plugin.json owns it"
        if [[ -f "$manifest" ]]; then
            [[ "$(jq -r 'has("version")' "$manifest")" == true ]] \
                || fail "$manifest declares no version"
            [[ "$(jq -r .name "$manifest")" == "$pname" ]] \
                || fail "$manifest name disagrees with the marketplace entry '$pname'"
        fi
    fi
done < <(jq -r '.plugins[] | [.name, (.source|tostring), (has("version"))] | @tsv' "$MARKET")
ok "plugin entries resolve, names agree, version declared once"

# 5. No stray version declarations anywhere else (a third copy in SKILL.md
#    frontmatter is how this drifted before).
strays="$(git ls-files '*.md' | xargs grep -ln '^version:' 2>/dev/null || true)"
[[ -z "$strays" ]] || fail "unexpected 'version:' frontmatter in: $strays"
ok "no stray version declarations in Markdown"

# 6. The newest released changelog heading must be the declared version. Catches
#    a bump that ships with no note, and a release heading added without a bump.
#    CI's release job tags whatever plugin.json declares, with that heading's
#    section as the release notes, so the two must agree before a merge to main.
if [[ -f CHANGELOG.md ]]; then
    while IFS= read -r manifest; do
        v="$(jq -r '.version // empty' "$manifest")"
        [[ -n "$v" ]] || continue
        top="$(sed -nE 's/^## \[([0-9][^]]*)\].*/\1/p' CHANGELOG.md | head -1)"
        [[ "$top" == "$v" ]] \
            || fail "newest CHANGELOG.md release is '${top:-none}', but $manifest declares '$v'"
    done < <(git ls-files '*/.claude-plugin/plugin.json')
    ok "newest changelog release matches the declared version"
fi

# 7. Declared hook commands must exist and be executable, and quote the script
#    path so a plugin root containing spaces still runs. Each command is also
#    run through sh from a copy of the plugin under a path with a space.
SPACED="$(mktemp -d)/plugin root"
trap 'rm -rf "$(dirname "$SPACED")"' EXIT
while IFS= read -r hookfile; do
    root="$(dirname "$(dirname "$hookfile")")"
    mkdir -p "$SPACED" && cp -R "$root/." "$SPACED/"
    while IFS= read -r cmd; do
        if [[ "$cmd" != '"${CLAUDE_PLUGIN_ROOT}/'* ]]; then
            fail "hook command doesn't quote its path: $cmd"; continue
        fi
        rel="${cmd#\"\$\{CLAUDE_PLUGIN_ROOT\}/}"; rel="${rel%%\"*}"
        [[ -f "$root/$rel" ]] || { fail "hook command missing: $cmd"; continue; }
        [[ -x "$root/$rel" ]] || { fail "hook command not executable: $root/$rel"; continue; }
        out="$(CLAUDE_PLUGIN_ROOT="$SPACED" CLAUDE_CONFIG_DIR="$SPACED/none" CLAUDE_PROJECT_DIR="$SPACED/none" \
            sh -c "$cmd" </dev/null 2>/dev/null)"
        jq -e . >/dev/null 2>&1 <<<"$out" || fail "hook command didn't run from a path with a space: $cmd"
    done < <(jq -r '.. | objects | select(.type=="command") | .command' "$hookfile")
done < <(git ls-files '*/hooks/hooks.json')
ok "hook commands exist, are executable, and run from a path with a space"

# 8. Every skill directory carries a SKILL.md.
while IFS= read -r d; do
    [[ -f "$d/SKILL.md" ]] || fail "$d has no SKILL.md"
done < <(find plugins/*/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
ok "every skill directory has SKILL.md"

if (( failures )); then echo; echo "$failures check(s) failed"; exit 1; fi
echo; echo "all manifest invariants hold"
