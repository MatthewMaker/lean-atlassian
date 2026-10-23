# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single-plugin Claude Code marketplace. The only executable code is bash: two
hook scripts (`load-atlassian-config.sh` for `SessionStart` and `SubagentStart`,
`approve-listed-operations.sh` for `PreToolUse`) and the `lib.sh` they share.
Everything
else is Markdown that instructs a future Claude instance. There is no build
step and no package manager. Checks, all runnable from anywhere in the repo:

```bash
tests/hook-cascade.sh          # SessionStart: precedence, optional scalars, JSON escaping
tests/offers.sh                # SessionStart: one-time offers fire once, under their condition
tests/approve-operations.sh    # PreToolUse: only listed, never fenced, never destructive
tests/manifest-invariants.sh   # manifest structure; version declared exactly once
shellcheck plugins/*/hooks/*.sh tests/*.sh   # .shellcheckrc makes it follow lib.sh
claude plugin validate .       # schema; runs unauthenticated
```

CI runs all six on every PR. On `main`, a `release` job then tags and
releases the `plugin.json` version if it isn't tagged yet, using its CHANGELOG
section as the notes. `manifest-invariants.sh` fails unless the newest
`## [x.y.z]` CHANGELOG heading equals that version, so a release is a version
bump plus a CHANGELOG heading in the same PR.

The hooks' governing invariant: they must always emit valid JSON on stdout —
`{}` when there's nothing to say, never an error or a bare message. They fail
quietly by design, so a bad emission reaches every session of every install
without announcing itself. That's what the hook tests exist to pin.

`approve-listed-operations.sh` is the only code that grants anything, so its
failure direction matters: every doubt resolves to `{}` (the normal prompt),
never to an allow. It never approves `executeDestructive`, and never reads a
list from fenced code (the `.example` file's sample list is fenced). Keep both
properties when changing it.

The threat it guards against is the user's own earlier settings files, such as
one copied from an older `.example`, not a hostile repository: project and
global lists are honoured alike, with no confirmation step.

The settings cascade lives once, in `lib.sh::resolve_settings`. Both hooks
source it; don't re-inline it.

## Layout

```
.claude-plugin/marketplace.json          # catalog entry
.github/workflows/ci.yml
tests/{hook-cascade,offers,approve-operations,manifest-invariants}.sh
.shellcheckrc
plugins/lean-atlassian/
  .claude-plugin/plugin.json             # plugin manifest
  hooks/hooks.json
  hooks/lib.sh                           # cascade + approval-list helpers, sourced
  hooks/load-atlassian-config.sh         # SessionStart: settings + offers; SubagentStart: settings
  hooks/approve-listed-operations.sh     # PreToolUse: per-operation approval
  commands/{jira,confluence}.md
  skills/atlassian-mediation/SKILL.md    # reads; references/jira-writes.md for writes
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
  `listJiraProjects`. It also names the skill and repeats its three most
  important read rules, because the skill's description can be dropped from
  the skill listing when many skills are installed. Subagents don't receive
  that context, so `hooks.json` also runs the script as a `SubagentStart` hook
  (matcher `atlassian-researcher$`), which injects the settings alone.
- **`atlassian-mediation` skill** is the source of truth for behavior: digest
  formats, JQL/CQL rules, context budgets, prefix→Component mapping, and MCP
  field placement.
- **`/jira`, `/confluence`** are explicit entry points that delegate to the skill
  rather than restating it.
- **`atlassian-researcher` agent** absorbs multi-call research in its own context
  and returns only a structured briefing.

Change SKILL.md (or `references/jira-writes.md`, for anything about writes or
the settings file's body) first and keep the commands thin — duplicating a rule
into a command is how the two drift apart. SKILL.md holds only what reads need,
so a session that never writes doesn't load the write rules.

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
- **`## Auto-approved operations`** — a permission grant, read by the
  `PreToolUse` hook from whichever file the cascade resolves. Claude writes it
  only when the user accepts an offer or asks outright, and carries it over
  untouched when rewriting the caches (`references/jira-writes.md`).

Preserve that split when adding settings: scalars in frontmatter, anything
list-shaped or project-specific in the body.

## MCP shapes that fail silently

The plugin targets the Atlassian MCP v2 server; tools are
`mcp__claude_ai_Atlassian_MCP__*`, and operations without a primary tool go
through `executeRead`/`executeWrite`/`executeDestructive` with a top-level
`cloudId`. Documented in SKILL.md, `references/jira-writes.md`, and
`references/mcp-tools-reference.md`:

- The server ignores unknown top-level params rather than rejecting them,
  despite its schemas declaring `additionalProperties: false`. A field in the
  wrong place is left unset with no error.
- `createJiraIssue`: `issueType`, `assignee` (bare accountId), `priority`,
  `labels`, `parent`, and `assignToSprint` are top-level;
  components/fixVersions/`customfield_*` go inside snake_case
  `additional_fields`.
- `editJiraIssue`: the same `additional_fields`, or raw Jira shapes inside
  `fields`, assignee included. It doesn't move sprints or change status —
  `transitionJiraIssue` does both (`sprintId`, `transitionId`).
- Sprints take the numeric sprint id, not the sprint number.
  `createJiraIssue`'s `assignToSprint` also takes the exact sprint name or
  `"active"`; `transitionJiraIssue`'s `sprintId` takes only the id.
- `searchJiraIssuesUsingJql` honours `fields` and `maxResults` (default 50,
  max 100). Issues are at `.issues.nodes[]`, paging at `.issues.pageInfo`
  (`endCursor` → `nextPageToken`). A large result can still overflow; the
  harness then spills full JSON to a file and returns the path.
- `getConfluenceContent` returns HTML unless `content_format: "markdown"` is
  passed, and only a summary unless `detail` says otherwise.

## Documentation is the product

README.md, the `.example` settings file, and the skill/command bodies are all
user-facing. A behavior change isn't complete until the README table and the
`.example` file describe it.
