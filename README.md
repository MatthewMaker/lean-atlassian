# lean-atlassian

A Claude Code plugin that mediates interaction with the Atlassian MCP server,
keeping Jira and Confluence responses focused and context-efficient.

## The Problem

The Atlassian MCP server returns verbose JSON. A single Confluence page fetch
can consume thousands of tokens; a JQL search dumping 20 full issue objects is
worse. Without mediation, every Atlassian interaction risks flooding the context
window with noise.

## What This Plugin Does

- **Digest-first output**: Summaries by default, full content only on request
- **Targeted queries**: JQL/CQL patterns that fetch only what's needed
- **cloudId injection**: A `SessionStart` hook loads your `cloud_id` from a
  settings file and injects it into the session, so it's never redundantly fetched
- **Per-operation approval**: A `PreToolUse` hook auto-approves the
  `executeRead`/`executeWrite` operations you list, so you don't have to allow
  every Atlassian write to skip the prompt for a few
- **Structured research**: An autonomous agent for multi-step Atlassian research
  that keeps raw intermediate results out of the main conversation

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `atlassian-mediation` | Skill | Teaches Claude the discipline of efficient Atlassian interaction |
| `/jira` | Command | Search Jira, look up an issue, or create one with digest output |
| `/confluence` | Command | Search Confluence or fetch a page with digest output |
| `atlassian-researcher` | Agent | Multi-step autonomous research across Jira + Confluence |
| `load-atlassian-config` | Hook | `SessionStart` hook that injects your `cloud_id`/`site_url` into each session; also runs as a `SubagentStart` hook so `atlassian-researcher` gets the same settings |
| `approve-listed-operations` | Hook | `PreToolUse` hook that auto-approves the `executeRead`/`executeWrite` operations listed in your settings file |

## Prerequisites

- The Atlassian MCP **v2** server (`https://mcp.atlassian.com/v2/mcp`) connected
  in Claude Code, as the claude.ai connector named "Atlassian MCP"
  (`mcp__claude_ai_Atlassian_MCP__*` tools available). The commands and agent
  name those tools exactly; the legacy v1 SSE server
  (`https://mcp.atlassian.com/v1/sse`, `mcp__claude_ai_Atlassian__*`) is no
  longer supported by Atlassian or by this plugin.
- An Atlassian account with access to your workspace

## Setup

1. **Install the plugin** in Claude Code:

   ```
   /plugin marketplace add MatthewMaker/lean-atlassian
   /plugin install lean-atlassian@lean-atlassian
   ```

2. **Create your settings file.** The plugin's `SessionStart` hook looks for
   `lean-atlassian.local.md` in two places, project first, then global:
   - **Global** (every project): in your Claude config dir
     (`$CLAUDE_CONFIG_DIR`, typically `~/.claude`)
   - **Per-project** (overrides global for one repo): `.claude/lean-atlassian.local.md`

   ```bash
   # global — available everywhere
   cp .claude/lean-atlassian.local.md.example \
      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lean-atlassian.local.md"
   ```

3. **Find your cloud ID** — ask Claude:
   > "What is my Atlassian cloud ID?"

   Claude will call `getAccessibleAtlassianResources` and display it.

4. **Edit the file** you just created:
   ```yaml
   ---
   cloud_id: "your-cloud-id-here"
   site_url: "https://your-org.atlassian.net"
   ---
   ```

   Neither location is committed. (If you skip this step, the first `/jira` or
   `/confluence` call will look the ID up via MCP and offer to save it for you.)

## Usage

### Commands

```
/jira PROJ-123
/jira my open bugs
/jira project = MYPROJ AND status = "In Progress"
/jira create bug: Frontend: Fix login button
/jira new Backend: rate-limit the search endpoint

/confluence deployment runbooks
/confluence auth docs in ENG space
/confluence 123456789
```

### Agent

Ask naturally:
> "Research the background on the auth refactor — check Jira and Confluence."

> "Give me a complete picture of PROJ-456: linked issues, history, related docs."

> "What Confluence pages exist about our deployment process?"

### Skill (automatic)

The `atlassian-mediation` skill activates automatically whenever you ask Claude
to look up Jira or Confluence content, enforcing context-efficient behavior
without any explicit invocation.

## Configuration

Settings live in `lean-atlassian.local.md`, loaded by the `SessionStart`
hook from a cascading lookup (first match wins):

1. **Per-project** — `.claude/lean-atlassian.local.md` in the project root
2. **Global** — `lean-atlassian.local.md` in your Claude config dir
   (`$CLAUDE_CONFIG_DIR`, typically `~/.claude`)

Both locations are outside the plugin repo and never committed. See
`.claude/lean-atlassian.local.md.example` for the template.

This plugin was previously called `private-atlassian`. Both tiers still accept
a `private-atlassian.local.md` file, checked after the current name, so an
existing settings file keeps working with no migration. Rename it at your
convenience.

| Field | Description |
|-------|-------------|
| `cloud_id` | Atlassian workspace UUID (required) |
| `site_url` | Your Atlassian site URL, e.g. `https://acme.atlassian.net` |
| `account_id` | Optional — your Jira accountId; injected so self-assignment skips an `atlassianUserInfo` lookup |
| `project_key` | Optional — default project key for searches and new issues |
| `component_prefix_strip` | Optional — strip a matched `Prefix: ` from a new issue's summary once mapped to a Component (default `true`) |

The `account_id` and `project_key` scalars are injected at `SessionStart` like
`cloud_id`. Nested caches — a per-project **Component list** and a
**name → accountId** people map — are maintained automatically in the settings
file body and read lazily only when creating issues, so they cost no session
context until used.

### Creating issues: summary prefix → Component

When you create a Jira issue whose summary starts with one or more `Token: `
prefixes (e.g. `"Frontend: Backend: Fix login button"`), each prefix is matched
case-insensitively against the target project's existing Components and every
match is added to the issue. Unmatched prefixes stay in the summary — nothing is
invented. By default the matched prefixes are stripped from the summary; set
`component_prefix_strip: false` to keep it verbatim. Component names are
discovered from the project and cached locally so repeat creates skip the lookup.

### Auto-approving `executeRead` / `executeWrite` operations

The v2 Atlassian MCP server reaches most operations through generic runners —
`executeRead`, `executeWrite`, `executeDestructive` — that take the operation
name as an input. A permission rule can only name the runner, so allowing
`executeWrite` allows every write in every Atlassian product.

To approve specific operations instead, list them in your settings file under
this heading:

```markdown
## Auto-approved operations

- addOrEditJiraIssueWorklog
- createJiraIssueLink
- createConfluenceComment
```

The `PreToolUse` hook approves an `executeRead` or `executeWrite` call whose
operation is listed (exact name match), and stays silent otherwise, so the
normal prompt appears. Rules:

- **Same cascade as everything else.** The list comes from whichever settings
  file wins (project first, then global). A project file's list replaces the
  global one; the two are not merged.
- **Fenced code doesn't count.** A heading or bullet inside a ``` or ~~~
  block is documentation, not part of the list.
- **`executeDestructive` is never auto-approved**, whatever the list says.
- **Deny and ask rules still win.** A hook approval skips the prompt but never
  overrides a matching `deny` or `ask` rule in your Claude Code settings.
- Requires `jq`. Without it the hook does nothing and every call prompts.

Use the exact operation names that `discover` returns.

### One-time offers

At session start the plugin may ask Claude to make **one** offer, at a natural
pause. Each is made once — declining means it doesn't come back:

| When | Offer |
|------|-------|
| Only the global file exists and you're in a git repo | Copy it into this repo's `.claude/` (and make sure the copy is git-ignored). Once per repository, across all its worktrees. |
| The settings file in use has no `## Auto-approved operations` section | Add one, starting from the three operations above. Once per file. |

Markers for offers already made live in the plugin's data directory
(`${CLAUDE_PLUGIN_DATA}`, kept across plugin updates and removed on uninstall).

## Development

No build step. Checks, runnable from anywhere in the repo:

```bash
tests/hook-cascade.sh          # SessionStart hook: precedence, scalars, JSON escaping
tests/offers.sh                # SessionStart hook: one-time offers fire once, under their condition
tests/approve-operations.sh    # PreToolUse hook: only listed, never fenced, never destructive
tests/manifest-invariants.sh   # manifest structure; version declared exactly once
shellcheck plugins/*/hooks/*.sh tests/*.sh
claude plugin validate .
```

CI runs all six on every pull request.

To release, bump `version` in `plugins/lean-atlassian/.claude-plugin/plugin.json`
and rename the CHANGELOG's `[Unreleased]` entries to a matching
`## [x.y.z] - date` heading in the same PR — the manifest check fails if the two
disagree. Once that merges and CI passes on `main`, CI tags `vx.y.z` and
publishes a GitHub Release with that CHANGELOG section as its notes. Installed
copies pick it up on `claude plugin update`, which keys on the version. See
[CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT — see [LICENSE](LICENSE).
