---
name: jira
description: >
  Search Jira issues or look up a specific ticket. Produces digest-style
  output to minimize context usage. Accepts a JQL query, an issue key
  (e.g. PROJ-123), or a plain-text description of what to find.
argument-hint: "<issue-key | jql | natural language query>"
allowed-tools:
  - mcp__claude_ai_Atlassian__getAccessibleAtlassianResources
  - mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
  - mcp__claude_ai_Atlassian__getJiraIssue
  - mcp__claude_ai_Atlassian__getVisibleJiraProjects
---

## /jira Command

Perform a focused Jira lookup or search and return a compact digest.

### Steps

1. **Load settings**: the `cloud_id` and `site_url` are injected below from
   `private-atlassian.local.md` — no `Read` tool call, no permission prompt
   (`cat` is a built-in read-only command):

   !`cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/private-atlassian.local.md" 2>/dev/null`

   Use the `cloud_id` from that block. If it's empty, call
   `getAccessibleAtlassianResources` once and remind the user to create the file.

2. **Interpret the argument**:
   - If it looks like an issue key (e.g. `PROJ-123`, `ABC-42`): fetch that single
     issue with `getJiraIssue`.
   - If it looks like JQL (contains `=`, `AND`, `OR`, `~`, `ORDER BY`): use it
     directly with `searchJiraIssuesUsingJql`.
   - Otherwise: treat as a natural-language query. Convert it to a JQL query.
     Examples:
     - "my open bugs" → `assignee = currentUser() AND issuetype = Bug AND status != Done ORDER BY updated DESC`
     - "recent PROJ issues" → `project = PROJ AND updated >= -7d ORDER BY updated DESC`
     - "login bug" → `text ~ "login bug" AND status != Done ORDER BY updated DESC`

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

5. **Offer to expand**: End with a brief offer:
   - For lists: "Want details on any of these, or a different query?"
   - For single issues: "Want the full description, comments, or linked issues?"

### Rules

- Never dump raw JSON or the full `description` field unprompted.
- If the user's query is ambiguous (could be Jira or Confluence), default to
  Jira but mention that `/confluence` exists for Confluence searches.
- If no results are found, suggest a relaxed query (fewer filters, broader text).
- Limit output to at most 15 issues per response. If there are more, say so and
  offer to paginate or narrow the query.
