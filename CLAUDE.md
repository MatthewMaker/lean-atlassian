# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-plugin Claude Code marketplace. The only executable code is one bash
`SessionStart` hook; everything else is Markdown that instructs a future Claude
instance. There is no build step and no package manager. Checks, all runnable
from anywhere in the repo:

```bash
tests/hook-cascade.sh          # hook precedence, optional scalars, JSON escaping
tests/manifest-invariants.sh   # manifest structure; version declared exactly once
shellcheck plugins/*/hooks/*.sh
claude plugin validate .       # schema; runs unauthenticated
```

CI runs all four on every PR.

The hook's governing invariant: it must always emit valid JSON on stdout —
`{}` when nothing is configured, never an error or a bare message. It fails
quietly by design, so a bad emission reaches every session of every install
without announcing itself. That's what `tests/hook-cascade.sh` exists to pin.

## Layout

```
.claude-plugin/marketplace.json          # catalog entry
.github/workflows/ci.yml
tests/{hook-cascade,manifest-invariants}.sh
plugins/lean-atlassian/
  .claude-plugin/plugin.json             # plugin manifest
  hooks/{hooks.json,load-atlassian-config.sh}
  commands/{jira,confluence}.md
  skills/atlassian-mediation/SKILL.md    # + references/*.md
  agents/atlassian-researcher.md
.claude/lean-atlassian.local.md.example
```

`plugin.json` is the single source of truth for the version. Don't add a
`version` to the marketplace entry — when both declare one, `plugin.json` wins
silently and the two drift.

## How the components fit together

Every component applies the same digest-first discipline at a different level of
explicitness:

- **`load-atlassian-config.sh`** (SessionStart) resolves the user's settings file
  — project `.claude/lean-atlassian.local.md` first, then
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lean-atlassian.local.md` — and injects
  its scalar frontmatter fields as `additionalContext`, so the other components
  never call `getAccessibleAtlassianResources`, `atlassianUserInfo`, or
  `getVisibleJiraProjects`.
- **`atlassian-mediation` skill** is the source of truth for behavior: digest
  formats, JQL/CQL rules, context budgets, prefix→Component mapping, and MCP
  field placement.
- **`/jira`, `/confluence`** are explicit entry points that delegate to the skill
  rather than restating it.
- **`atlassian-researcher` agent** absorbs multi-call research in its own context
  and returns only a structured briefing.

Change SKILL.md first and keep the commands thin — duplicating a rule into a
command is how the two drift apart.

## Why the hook exists instead of `!`-injection

The command-bash permission checker rejects injected commands containing shell
expansion, so `$CLAUDE_CONFIG_DIR` can't be referenced from a command or skill
body. A plugin hook runs as a real shell with the full environment.

## Settings file contract

The user's `lean-atlassian.local.md` (gitignored) is both config and a
self-maintained cache:

- **Frontmatter scalars** — injected at SessionStart, always present.
- **Body sections** (`## Component cache`, `## People cache`,
  `## Prefix exceptions`) — deliberately not injected; read and rewritten lazily
  by the issue-creation workflow so sessions that never create an issue pay no
  context for them.

Preserve that split when adding settings: scalars in frontmatter, anything
list-shaped or project-specific in the body.

## MCP shapes that fail silently

Documented in SKILL.md and `references/mcp-tools-reference.md`:

- `createJiraIssue`: issue type is `issueTypeName`; assignee is a bare id string
  in top-level `assignee_account_id`; priority/components/labels/`customfield_*`
  go inside snake_case `additional_fields`. Unknown top-level params are dropped
  and the create still reports success.
- `editJiraIssue`: everything, assignee included, goes inside `fields`.
- Sprint is `customfield_10020` and takes the numeric sprint id, not the sprint
  number. A successful edit omits it from the response; with a trusted id that's
  a display quirk, not a failure.
- `searchJiraIssuesUsingJql` ignores `fields` and floors `maxResults` at ~50; on
  overflow the harness spills full JSON to a file and returns the path. Issues
  are at `.issues.nodes[]`, paging at `.issues.pageInfo`.

## Documentation is the product

README.md, the `.example` settings file, and the skill/command bodies are all
user-facing. A behavior change isn't complete until the README table and the
`.example` file describe it.
