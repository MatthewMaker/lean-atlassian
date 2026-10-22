---
name: atlassian-mediation
description: >
  This skill should be used when the user asks to "look up a Jira issue",
  "find a Confluence page", "search Jira", "search Confluence", "show me
  issues in project X", "what's the status of ticket Y", "find docs about Z",
  "what have I done", "what tickets did I touch", "since my last standup",
  "what's blocked", "what's in progress", "what's in this sprint", or any
  task that involves reading from or searching Atlassian (Jira or Confluence)
  — including activity, progress, and "what changed" questions that imply a
  Jira or Confluence query. Guides efficient, low-bloat interaction with the
  Atlassian MCP server by enforcing digest output, cloudId caching, and
  targeted queries.
---

# Atlassian Mediation

## Purpose

Interact with Jira and Confluence via the Atlassian MCP server in a way that
minimizes context consumption. The raw MCP tools return verbose JSON that
quickly overwhelms the context window. This skill enforces a discipline of
**digest-first, detail-on-demand**: always summarize before expanding, always
limit fields fetched, and always cache the cloudId rather than re-fetching it.

## The MCP server (v2)

This plugin targets the Atlassian MCP v2 endpoint (`https://mcp.atlassian.com/v2/mcp`;
in Claude Code, the `mcp__claude_ai_Atlassian_MCP__*` tools). It exposes tools in
two layers:

- **Primary tools** — called directly: `searchJiraIssuesUsingJql`, `getJiraIssue`,
  `createJiraIssue`, `editJiraIssue`, `transitionJiraIssue`,
  `addOrEditJiraIssueComment`, `searchConfluence`, `getConfluenceContent`,
  `createConfluenceContent`, `updateConfluenceContent`, `search`, and a few more.
- **Everything else** — reached through a runner that matches the operation's
  risk tier: `executeRead`, `executeWrite`, or `executeDestructive`. Pass
  `name`, a top-level `cloudId` (never inside `inputs`), and a flat `inputs`
  object:

  ```
  executeRead(name: "listJiraProjectComponents", cloudId: <from settings>,
              inputs: {projectIdOrKey: "MYPROJ"})
  ```

  The operations this skill uses are named below. For anything else, call
  `discover` with a short goal ("list jira issue transitions") and use the exact
  name it returns — never guess one.

## Settings

All settings live in one uncommitted file, resolved by a cascading lookup —
first match wins:

1. Per-project — `.claude/lean-atlassian.local.md` in the project root
2. Global fallback — `lean-atlassian.local.md` in the Claude config directory
   (`$CLAUDE_CONFIG_DIR`, typically `~/.claude`)

The file is a private, per-user/per-project store. Because Component names,
project keys, and account IDs are site-specific, this taxonomy belongs here —
not hardcoded into the skill, which stays deliberately generic.

### Injected at SessionStart (scalars)

The plugin's `SessionStart` hook reads the single-line scalar fields from the
frontmatter and injects them into the session:

| Field | Purpose | Replaces the call |
|-------|---------|-------------------|
| `cloud_id` | Workspace UUID; required on every MCP call | `getAccessibleAtlassianResources` |
| `site_url` | Site URL for building links | — |
| `account_id` | Your Jira accountId, for assigning issues to yourself | `atlassianUserInfo` |
| `project_key` | Default project for searches and new issues | `listJiraProjects` |

Use the injected values directly. **Never call `getAccessibleAtlassianResources`,
`atlassianUserInfo`, or `listJiraProjects` for a value already injected.**
`cloud_id`/`site_url` are required; `account_id`/`project_key` are optional.

If nothing was injected (no config file yet), call `getAccessibleAtlassianResources`
once, then offer to save at least the frontmatter below to
`.claude/lean-atlassian.local.md` in the current project so future sessions
skip the lookup. Before writing it, check `git check-ignore -q
.claude/lean-atlassian.local.md`; if the file would not be ignored, offer to
add `.claude/*.local.md` to `.git/info/exclude` first — the people cache it
will grow must never be committed.

```yaml
---
cloud_id: "your-cloud-id-here"
site_url: "https://your-org.atlassian.net"
account_id: ""            # optional — your Jira accountId
project_key: ""           # optional — default project key, e.g. MYPROJ
component_prefix_strip: true   # optional — see references/jira-writes.md
---
```

## Core Discipline: Digest First

For every Atlassian response, produce a **digest** — a compact, human-readable
summary — before offering to expand. The default output format for any search
or fetch is:

### Jira Issue Digest

```
[KEY-123] Title of the issue (Status · Assignee · Priority)
  Summary: one-sentence description
  Labels: label1, label2
  Updated: 2024-01-15
```

### Confluence Page Digest

```
[Page Title] — Space Name
  Last edited: 2024-01-15 by Author
  Excerpt: first ~120 characters of body content...
  URL: https://org.atlassian.net/wiki/...
```

### Search Results Digest

Present at most **10 results** per search, each as a single-line digest.
Never dump raw JSON. Never include full body content unless the user explicitly
asks to "show the full page" or "show full details".

## Jira Workflows

### Searching Issues

Use `searchJiraIssuesUsingJql` with a targeted JQL query, and always pass
`fields` and `maxResults` — both are honoured, and `maxResults` defaults to 50.
Default fields: `summary`, `status`, `assignee`, `priority`, `labels`, `updated`.
Limit to 10–20 results unless the user asks for more.

```
searchJiraIssuesUsingJql(
  cloudId: <from settings>,
  jql: "project = MYPROJ AND status != Done ORDER BY updated DESC",
  fields: ["summary", "status", "assignee", "priority", "labels", "updated"],
  maxResults: 10
)
```

Issues come back at `.issues.nodes[]`. When `.issues.pageInfo.hasNextPage` is
true, pass `.issues.pageInfo.endCursor` as `nextPageToken` for the next page.

Produce a digest list. Offer: "Want details on any of these?"

### Fetching a Single Issue

Use `getJiraIssue` only when the user asks about a specific ticket. The default
`view: "compact"` is enough for a digest; use `view: "evidence"` when you need
issue links or custom fields. It reports a comment count, not the comments —
read those with `listJiraIssueComments` (via `executeRead`) only on request.
Produce a digest, then offer to show the full description or comments.

### JQL Patterns

See `references/jql-patterns.md` for common query templates. Key rules:
- Always add `ORDER BY updated DESC` unless sorting by something specific
- Use `status != Done` to exclude resolved issues by default
- Use `assignee = currentUser()` for "my issues" queries
- Use `text ~ "keyword"` for full-text search across summary + description

## Writing to Jira

Before creating, editing, or transitioning an issue, moving it between sprints,
or rewriting the settings file's caches, read **`references/jira-writes.md`**.
It holds the field placement rules — a field passed in the wrong place is
dropped without an error — plus the prefix→Component mapping, the people and
Component caches, and the rules for the `## Auto-approved operations` section.

## Confluence Workflows

### Searching Pages

Use `searchConfluence` with a focused CQL query. Limit to 10 results.

```
searchConfluence(
  cloudId: <from settings>,
  cql: "title ~ \"deployment\" AND space.key = \"ENG\" AND type = page",
  limit: 10
)
```

Produce a digest list with page title, space, last-edited date, and a short
excerpt. Do **not** fetch full page content during a search.

### Fetching a Page

Use `getConfluenceContent` only when the user asks to "read", "open", or "show"
a specific page. Pass `content_id` (or `content_url` for a pasted link) and
`content_format: "markdown"` — the default is HTML, which costs far more tokens.

Its `detail` parameter sets how much comes back. Start cheap and expand on
request:

| `detail` | Returns | Use for |
|----------|---------|---------|
| `summary` (default) | title, excerpt, counts | a digest line |
| `outline` | the heading tree | the table of contents |
| `full` | the whole body | reading a section the user asked for |

Even after a `full` fetch, **summarize the page** rather than dumping the body:
- Section headings as a table of contents
- A 2–3 sentence abstract
- Offer: "Want me to read a specific section?"

### CQL Patterns

See `references/cql-patterns.md` for common query templates. Key rules:
- `type = page` to exclude blog posts and attachments
- `ancestor = <pageId>` to search within a page tree
- `space.key = "KEY"` to scope to a specific space
- `lastModified >= "2024-01-01"` for recency filtering

## Context Budget Rules

Apply these limits at all times:

| Operation | Max results | Body content |
|-----------|-------------|--------------|
| JQL search | 10–20 | Never in search |
| CQL search | 10 | Never in search |
| Single Jira issue | 1 | Digest only; full on request |
| Single Confluence page | 1 | Summarize; section on request |
| Page descendants (`getConfluenceContentDescendants`, via `executeRead`) | 10 | Titles only |

If the user asks for "all issues" or "everything", explain that fetching
everything would flood the context, then offer a targeted query instead.

## Error Handling

- **cloudId missing**: Call `getAccessibleAtlassianResources`, show the result,
  prompt user to add it to `.claude/lean-atlassian.local.md`.
- **No results**: Suggest a relaxed query (remove filters, broaden text search).
- **Permission error**: Note the user may not have access; suggest checking
  Atlassian permissions.
- **Ambiguous request**: Ask one clarifying question (Jira or Confluence? which
  project/space?) before making any MCP call.

## Additional Resources

- **`references/jql-patterns.md`** — Common JQL query templates for Jira
- **`references/cql-patterns.md`** — Common CQL query templates for Confluence
- **`references/mcp-tools-reference.md`** — Quick reference for all available
  Atlassian MCP tools and their parameters
- **`references/jira-writes.md`** — Creating and editing issues, sprints, and
  the settings file's caches and approval list
