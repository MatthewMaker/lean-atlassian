---
name: Atlassian Mediation
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
version: 0.2.0
---

# Atlassian Mediation

## Purpose

Interact with Jira and Confluence via the Atlassian MCP server in a way that
minimizes context consumption. The raw MCP tools return verbose JSON that
quickly overwhelms the context window. This skill enforces a discipline of
**digest-first, detail-on-demand**: always summarize before expanding, always
limit fields fetched, and always cache the cloudId rather than re-fetching it.

## Settings: cloudId and Site URL

The settings file `private-atlassian.local.md` (in the user's Claude config
directory) holds their `cloud_id` and `site_url`. Its contents are **injected
below at load time** — no `Read` tool call and no permission prompt, since the
`cat` runs as a built-in read-only command:

!`cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/private-atlassian.local.md" 2>/dev/null`

Use the `cloud_id` from the block above for every Atlassian MCP call.

If the block is empty (the file doesn't exist yet), call
`getAccessibleAtlassianResources` once to retrieve the cloudId, then remind the
user to create the file with this frontmatter so future sessions skip the lookup:

```yaml
---
cloud_id: "your-cloud-id-here"
site_url: "https://your-org.atlassian.net"
---
```

**Never call `getAccessibleAtlassianResources` if `cloud_id` is already
available above.**

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

Use `searchJiraIssuesUsingJql` with a targeted JQL query. Default fields to
fetch: `summary`, `status`, `assignee`, `priority`, `labels`, `updated`.
Limit to 10–20 results unless the user asks for more.

```
searchJiraIssuesUsingJql(
  cloudId: <from settings>,
  jql: "project = MYPROJ AND status != Done ORDER BY updated DESC",
  maxResults: 10
)
```

Produce a digest list. Offer: "Want details on any of these?"

### Fetching a Single Issue

Use `getJiraIssue` only when the user asks about a specific ticket. Request
only the fields needed for the current task. Produce a digest, then offer to
show the full description or comments if needed.

### JQL Patterns

See `references/jql-patterns.md` for common query templates. Key rules:
- Always add `ORDER BY updated DESC` unless sorting by something specific
- Use `status != Done` to exclude resolved issues by default
- Use `assignee = currentUser()` for "my issues" queries
- Use `text ~ "keyword"` for full-text search across summary + description

## Confluence Workflows

### Searching Pages

Use `searchConfluenceUsingCql` with a focused CQL query. Limit to 10 results.

```
searchConfluenceUsingCql(
  cloudId: <from settings>,
  cql: "title ~ \"deployment\" AND space.key = \"ENG\" AND type = page",
  limit: 10
)
```

Produce a digest list with page title, space, last-edited date, and a short
excerpt. Do **not** fetch full page content during a search.

### Fetching a Page

Use `getConfluencePage` only when the user asks to "read", "open", or "show"
a specific page. Request `markdown` format (not `adf`) for readability.

Even after fetching, **summarize the page** rather than dumping the full body:
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
| Page descendants | 10 | Titles only |

If the user asks for "all issues" or "everything", explain that fetching
everything would flood the context, then offer a targeted query instead.

## Error Handling

- **cloudId missing**: Call `getAccessibleAtlassianResources`, show the result,
  prompt user to add it to `.claude/private-atlassian.local.md`.
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
