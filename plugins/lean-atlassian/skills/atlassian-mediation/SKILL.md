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
---

# Atlassian Mediation

## Purpose

Interact with Jira and Confluence via the Atlassian MCP server in a way that
minimizes context consumption. The raw MCP tools return verbose JSON that
quickly overwhelms the context window. This skill enforces a discipline of
**digest-first, detail-on-demand**: always summarize before expanding, always
limit fields fetched, and always cache the cloudId rather than re-fetching it.

## Settings & Cache

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
| `project_key` | Default project for searches and new issues | `getVisibleJiraProjects` |

Use the injected values directly. **Never call `getAccessibleAtlassianResources`,
`atlassianUserInfo`, or `getVisibleJiraProjects` for a value already injected.**
`cloud_id`/`site_url` are required; `account_id`/`project_key` are optional.

If nothing was injected (no config file yet), call `getAccessibleAtlassianResources`
once, then offer to save at least the frontmatter below to
`.claude/lean-atlassian.local.md` in the current project so future sessions
skip the lookup:

```yaml
---
cloud_id: "your-cloud-id-here"
site_url: "https://your-org.atlassian.net"
account_id: ""            # optional — your Jira accountId
project_key: ""           # optional — default project key, e.g. MYPROJ
component_prefix_strip: true   # optional — see Creating Issues
---
```

### Lazy self-maintained caches (file body)

Nested data is **not** injected at SessionStart — it is read (and written) lazily
by the **Creating Issues** workflow, only when needed, so no session pays context
for a map it will not use. Prefer the project-level settings file when writing,
since this data is project-specific. Maintain two Markdown sections in the file
body, refreshing each on a miss (append the freshly-fetched value, exactly like a
self-updating note):

- **Component cache** — one list of Component names per project key. On a prefix
  that matches nothing, re-fetch the project's live Components once (one may have
  been added), rewrite the list, then retry.
- **People cache** — a `Full Name: accountId` list for people you assign or query
  about. On a name miss, call `lookupJiraAccountId` once, then append it here.

```markdown
## Component cache (auto-maintained)

### MYPROJ
- Frontend
- Backend
- Platform
_refreshed: 2026-07-05_

## People cache (auto-maintained)

- Alice Smith: 712020:aaaaaaaa-1111-2222-3333-444444444444
- Bob Jones: 712020:bbbbbbbb-5555-6666-7777-888888888888

## Prefix exceptions

- Urgent
- WIP
```

**Prefix exceptions** is an optional body list of tokens that must never be
treated as a Component prefix even if a Component of that name exists.

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

## Creating Issues

Create issues with `createJiraIssue`. Default the `projectKey` to the injected
`project_key` and assignment-to-self to the injected `account_id` unless the
user says otherwise. Layer the prefix→Component behavior below on top.

### Field placement

`createJiraIssue` spreads its fields across three homes, and passing one to the
wrong home **fails silently** — an unknown top-level parameter is dropped rather
than rejected, so the call returns a normal-looking issue with those fields unset.

| Field | Where it goes |
|-------|---------------|
| `summary`, `description`, `projectKey`, `parent` | own top-level parameters |
| issue type | `issueTypeName` — **not** `issueType` |
| assignee | `assignee_account_id`, top-level, a bare id string |
| `priority`, `components`, `labels`, `fixVersions`, `customfield_*` | inside `additional_fields` |

`additional_fields` is **snake_case** and takes raw Jira field shapes:

```json
{"components": [{"name": "Frontend"}], "priority": {"name": "Low"}, "customfield_10020": 123}
```

Note the asymmetry with `editJiraIssue`, which puts everything — assignee
included — inside a parameter named **`fields`**:

```json
{"assignee": {"accountId": "…"}, "components": [{"name": "Frontend"}]}
```

Getting this wrong is not hypothetical. A batch of issues created with a
camelCase `additionalFields` and a nested `assignee` came back with assignee,
components, priority and sprint all unset, and each create reported success.

This is a "pass the right shape" rule, not a "verify afterwards" rule — it adds no
follow-up read. See **Sprint assignment** under *Editing Issues* for why a trusted
write needs no confirming fetch.

### Summary prefixes → Components

A **prefix** is a leading token followed by a colon and a space: in
`"Frontend: Fix login button"`, the prefix is `Frontend`. A summary may carry
**any number** of stacked leading prefixes —
`"Frontend: Backend: Fix login button"` yields candidate prefixes `Frontend`
and `Backend`.

When creating an issue:

1. **Peel leading prefixes.** From the front of the summary, repeatedly split off
   `<token>: ` segments. Each `<token>` is a candidate prefix. Stop at the first
   token that does not resolve to a Component (step 3) — a non-matching leading
   token (e.g. `Urgent`) is ordinary summary text, not a prefix. Tokens listed
   under **Prefix exceptions** in the settings file are never treated as prefixes.

2. **Get the project's Components.** Read the **Component cache** for this project
   from the settings file first. On a miss — no cached list, or a candidate
   matches nothing — fetch the live list once via `getJiraIssueTypeMetaWithFields`
   (read the `components` field's allowed values), then rewrite the cache section.

3. **Match case-insensitively.** A candidate resolves to a Component when it
   equals an existing Component name ignoring case — `frontend`, `Frontend`, and
   `FRONTEND` all match a `Frontend` component.

4. **Apply matches.** Set the new issue's `components` field to every matched
   Component (the field is a list, so stacked prefixes add multiple components).
   Never invent a Component that doesn't exist in the project; unmatched prefixes
   add nothing and are left in the summary.

5. **Summary text.** By default (`component_prefix_strip: true` or unset),
   **strip** each matched prefix from the summary, since the Component now carries
   that information — `"Frontend: Fix login"` with a matched `Frontend` component
   becomes summary `"Fix login"`. If `component_prefix_strip: false`, keep the
   summary verbatim.

6. **Confirm.** After creating, report the resolved Components and the final
   summary, e.g. *"Created MYPROJ-123 (components: Frontend, Backend) — 'Fix login
   button'."*

### Assignees and people

To assign an issue or filter by a person, resolve the name to an accountId via
the **People cache** in the settings file first. On a miss, call
`lookupJiraAccountId` once, then append the result to the cache so future
references skip the lookup. Use the injected `account_id` for the current user
without any lookup.

## Editing Issues

Use `editJiraIssue` to change fields on an existing issue (assignee, priority,
sprint, description, etc.).

### Sprint assignment

Set the sprint by writing the sprint's **numeric id** to `customfield_10020`
(e.g. `{"customfield_10020": 705}`). The id is the sprint id, **not** the sprint
number.

**Do not verify the assignment afterward when the id came from a trusted cache.**
`editJiraIssue` omits `customfield_10020` from its response payload on success —
the missing sprint field is a quirk of the response shape, not a signal that the
write failed. When the sprint id is a **cached/known-good identifier** (e.g. the
current-sprint id maintained in project settings, `CLAUDE.md`, or `AGENTS.md`), a
non-error response means the edit took. Skip the follow-up `getJiraIssue` — it
spends context confirming something the absence of an error already told you.

(If the id is *unverified* — a number the user supplied that may not be a real,
open sprint on this board — a bad id can be silently rejected; there, a single
confirming read is warranted. The no-verify rule applies specifically to cached
ids you already trust.)

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
