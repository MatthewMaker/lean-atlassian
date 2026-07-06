# private-atlassian

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
- **Structured research**: An autonomous agent for multi-step Atlassian research
  that keeps raw intermediate results out of the main conversation

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `atlassian-mediation` | Skill | Teaches Claude the discipline of efficient Atlassian interaction |
| `/jira` | Command | Search Jira, look up an issue, or create one with digest output |
| `/confluence` | Command | Search Confluence or fetch a page with digest output |
| `atlassian-researcher` | Agent | Multi-step autonomous research across Jira + Confluence |
| `load-atlassian-config` | Hook | `SessionStart` hook that injects your `cloud_id`/`site_url` into each session |

## Prerequisites

- Atlassian MCP server configured in Claude Code
  (`mcp__claude_ai_Atlassian__*` tools available)
- An Atlassian account with access to your workspace

## Setup

1. **Install the plugin** in Claude Code

2. **Create your settings file.** The plugin's `SessionStart` hook looks for
   `private-atlassian.local.md` in two places, project first, then global:
   - **Global** (every project): in your Claude config dir
     (`$CLAUDE_CONFIG_DIR`, typically `~/.claude`)
   - **Per-project** (overrides global for one repo): `.claude/private-atlassian.local.md`

   ```bash
   # global — available everywhere
   cp .claude/private-atlassian.local.md.example \
      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/private-atlassian.local.md"
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

Settings live in `private-atlassian.local.md`, loaded by the `SessionStart`
hook from a cascading lookup (first match wins):

1. **Per-project** — `.claude/private-atlassian.local.md` in the project root
2. **Global** — `private-atlassian.local.md` in your Claude config dir
   (`$CLAUDE_CONFIG_DIR`, typically `~/.claude`)

Both locations are outside the plugin repo and never committed. See
`.claude/private-atlassian.local.md.example` for the template.

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

## License

MIT
