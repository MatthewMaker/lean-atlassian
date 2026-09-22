---
name: jira
description: >
  Search Jira issues, look up a specific ticket, or create a new issue.
  Produces digest-style output to minimize context usage. Accepts a JQL
  query, an issue key (e.g. PROJ-123), a plain-text description of what to
  find, or a "create ..." request.
argument-hint: "<issue-key | jql | query | create ...>"
allowed-tools:
  - mcp__claude_ai_Atlassian__getAccessibleAtlassianResources
  - mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__getVisibleJiraProjects
  - mcp__claude_ai_Atlassian__createJiraIssue
  - mcp__claude_ai_Atlassian__getJiraIssueTypeMetaWithFields
  - mcp__claude_ai_Atlassian__lookupJiraAccountId
---

## /jira Command

Perform a focused Jira lookup or search and return a compact digest.

### Steps

1. **Load settings**: the plugin's `SessionStart` hook injects the user's
   `cloud_id`, `site_url`, and (when configured) `account_id` and `project_key`
   into the session context at startup (read from a per-project
   `.claude/lean-atlassian.local.md`, falling back to one in the Claude config
   directory). Use the injected `cloud_id` for every Atlassian MCP call, and the
   injected `account_id`/`project_key` instead of looking them up.

   If no Atlassian settings were injected (no config file yet), call
   `getAccessibleAtlassianResources` once, then offer to save the `cloud_id` and
   `site_url` to `.claude/lean-atlassian.local.md` in the current project so
   future sessions skip the lookup.

2. **Interpret the argument** — check in this order:
   - **Create intent** — starts with a creation verb (`create`, `new`, `add`,
     `file`, `make`), optionally followed by an issue type (`bug`, `task`,
     `story`, `epic`, `issue`, `ticket`): treat the remainder as the new issue's
     summary and follow **Creating an issue** below.
   - **Issue key** (e.g. `PROJ-123`, `ABC-42`): fetch that single issue with
     `getJiraIssue`.
   - **JQL** (contains `=`, `AND`, `OR`, `~`, `ORDER BY`): use it directly with
     `searchJiraIssuesUsingJql`.
   - Otherwise: treat as a natural-language query. Convert it to a JQL query.
     Examples:
     - "my open bugs" → `assignee = currentUser() AND issuetype = Bug AND status != Done ORDER BY updated DESC`
     - "recent PROJ issues" → `project = PROJ AND updated >= -7d ORDER BY updated DESC`
     - "login bug" → `text ~ "login bug" AND status != Done ORDER BY updated DESC`

### Creating an issue

Delegate to the atlassian-mediation skill's **Creating Issues** workflow — don't
reinvent it. In brief:

1. **Project & type**: default `projectKey` to the injected `project_key`; if none
   is set and the request names no project, ask before creating. Default the
   issue type to `Task` unless the request names one (bug/story/epic/…).
2. **Prefixes → Components**: parse leading `Token: ` prefixes from the summary
   and match them case-insensitively against the project's Components (from the
   settings-file Component cache; fetch via `getJiraIssueTypeMetaWithFields` and
   refresh the cache on a miss). Add every match to `components`; leave unmatched
   prefixes in the summary. Strip matched prefixes from the summary unless
   `component_prefix_strip: false`.
3. **Assignee**: resolve any named assignee via the People cache /
   `lookupJiraAccountId`; use the injected `account_id` for "assign to me".
4. **Create** with `createJiraIssue`, then confirm with the digest below. Since
   `/jira create …` is explicit authorization, create directly — but if the
   project is unknown, ask first rather than guessing.

3. **Fetch results**:
   - For searches: request at most 15 results. Do not fetch full issue bodies.
   - For single issue: fetch the issue. Produce a digest, not the raw JSON.

4. **Output digest**:

   For a list of issues:
   ```
   Found N issues (JQL: <the query used>)

   [PROJ-123] Fix login timeout — In Progress · Alice · High
     Labels: auth, bug  |  Updated: Jan 15
   [PROJ-121] Add rate limiting — To Do · Bob · Medium
     Updated: Jan 14
   ...
   ```

   For a single issue:
   ```
   [PROJ-123] Fix login timeout
   Status: In Progress  |  Assignee: Alice  |  Priority: High
   Reporter: Bob  |  Created: Jan 10  |  Updated: Jan 15
   Labels: auth, bug
   Type: Bug  |  Sprint: Sprint 12

   Summary:
   <2–3 sentence description from the issue body, not the full text>
   ```

   For a created issue:
   ```
   Created [PROJ-123] Fix login button
   Project: MYPROJ  |  Type: Task  |  Components: Frontend, Backend
   Assignee: Me  |  URL: <site_url>/browse/PROJ-123
   ```
   Note which prefixes mapped to Components (and any that didn't) so the
   stripping is transparent.

5. **Offer to expand**: End with a brief offer:
   - For lists: "Want details on any of these, or a different query?"
   - For single issues: "Want the full description, comments, or linked issues?"
   - For a created issue: "Want to set the assignee, add a description, or link it?"

### Rules

- Never dump raw JSON or the full `description` field unprompted.
- If the user's query is ambiguous (could be Jira or Confluence), default to
  Jira but mention that `/confluence` exists for Confluence searches.
- If no results are found, suggest a relaxed query (fewer filters, broader text).
- Limit output to at most 15 issues per response. If there are more, say so and
  offer to paginate or narrow the query.
- When creating, never invent a Component — only apply ones that exist in the
  project. If the project can't be determined, ask before creating rather than
  guessing.
