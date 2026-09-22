---
name: confluence
description: >
  Search Confluence pages or fetch a specific page. Produces digest-style
  output to minimize context usage. Accepts a page ID, a CQL query, or a
  plain-text description of what to find.
argument-hint: "<page-id | cql | natural language query>"
allowed-tools:
  - mcp__claude_ai_Atlassian__getAccessibleAtlassianResources
  - mcp__claude_ai_Atlassian__searchConfluenceUsingCql
  - mcp__claude_ai_Atlassian__getConfluencePage
  - mcp__claude_ai_Atlassian__getConfluencePageDescendants
  - mcp__claude_ai_Atlassian__getConfluenceSpaces
---

## /confluence Command

Perform a focused Confluence search or page fetch and return a compact digest.

### Steps

1. **Load settings**: the plugin's `SessionStart` hook injects the user's
   `cloud_id` and `site_url` into the session context at startup (read from a
   per-project `.claude/private-atlassian.local.md`, falling back to one in the
   Claude config directory). Use that injected `cloud_id` for every Atlassian
   MCP call.

   If no Atlassian settings were injected (no config file yet), call
   `getAccessibleAtlassianResources` once, then offer to save the `cloud_id` and
   `site_url` to `.claude/private-atlassian.local.md` in the current project so
   future sessions skip the lookup.

2. **Interpret the argument**:
   - If it looks like a numeric page ID (all digits): fetch that page with
     `getConfluencePage`.
   - If it looks like CQL (contains `~`, `AND`, `type =`, `space.key`): use it
     directly with `searchConfluenceUsingCql`.
   - Otherwise: treat as a natural-language query. Convert it to a CQL query.
     Examples:
     - "deployment runbooks" → `text ~ "deployment" AND type = page AND label = "runbook" ORDER BY lastModified DESC`
     - "auth docs in ENG space" → `space.key = "ENG" AND text ~ "authentication" AND type = page ORDER BY lastModified DESC`
     - "recently updated pages" → `type = page AND lastModified >= -7d ORDER BY lastModified DESC`

3. **Fetch results**:
   - For searches: limit to 10 results. Do not fetch page bodies during search.
   - For single page fetch: use `contentFormat: "markdown"`. Summarize; do not
     dump the full body.

4. **Output digest**:

   For a list of pages:
   ```
   Found N pages (CQL: <the query used>)

   [Deployment Runbook] — Engineering
     Last edited: Jan 15 by Alice
     Preview: How to deploy services to production. This runbook covers...
   [Auth Service Overview] — Engineering
     Last edited: Jan 12 by Bob
     Preview: Architecture overview for the authentication service...
   ...
   ```

   For a single page:
   ```
   [Page Title] — Space Name
   Last edited: Jan 15 by Alice  |  Version: 23
   URL: https://org.atlassian.net/wiki/spaces/ENG/pages/123456789

   ## Table of Contents
   - Overview
   - Prerequisites
   - Step-by-step guide
   - Troubleshooting

   ## Abstract
   <2–3 sentence summary of what the page covers>
   ```

5. **Offer to expand**: End with a brief offer:
   - For lists: "Want me to open any of these pages, or try a different search?"
   - For single pages: "Want me to read a specific section, or show the full content?"

### Rules

- Always use `contentFormat: "markdown"` when fetching pages — never `adf`.
- Never dump the full page body unprompted, even if it was fetched. Summarize first.
- If the page is very long (>200 lines of markdown), offer to read specific
  sections by heading rather than showing everything.
- If the user asks to "read" or "show" a page section, find the relevant heading
  in the markdown and output only that section.
- Limit search results to 10 per response. If more exist, say so and offer to
  narrow the query or browse by space.
- If the user's query is ambiguous (could be Jira or Confluence), default to
  Confluence but mention that `/jira` exists for ticket searches.
