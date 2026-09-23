# JQL Patterns for Jira

Common JQL query templates for use with `searchJiraIssuesUsingJql`.

## My Work

```jql
-- Issues assigned to me, not done, recently updated
assignee = currentUser() AND status != Done ORDER BY updated DESC

-- Issues I'm watching
watcher = currentUser() AND status != Done ORDER BY updated DESC

-- Issues I created
reporter = currentUser() ORDER BY created DESC
```

## By Project

```jql
-- All open issues in a project
project = "PROJ" AND status != Done ORDER BY updated DESC

-- Issues updated this week
project = "PROJ" AND updated >= -7d ORDER BY updated DESC

-- Issues in a sprint
project = "PROJ" AND sprint in openSprints()

-- Epics only
project = "PROJ" AND issuetype = Epic AND status != Done
```

## By Status

```jql
-- In progress across projects
status = "In Progress" ORDER BY updated DESC

-- Recently closed (last 7 days)
status = Done AND updated >= -7d ORDER BY updated DESC

-- Blocked issues
status = Blocked ORDER BY updated DESC

-- In review
status in ("In Review", "Code Review", "PR Open") ORDER BY updated DESC
```

## By Priority / Urgency

```jql
-- High priority open issues
priority in (High, Highest) AND status != Done ORDER BY priority DESC, updated DESC

-- Overdue (past due date)
duedate < now() AND status != Done ORDER BY duedate ASC
```

## Text Search

```jql
-- Full-text search across summary and description
text ~ "authentication" AND project = "PROJ"

-- Summary contains phrase
summary ~ "login bug" ORDER BY updated DESC

-- Label search
labels = "needs-triage" AND status != Done
```

## Related to a PR / Branch

```jql
-- Issues linked to a development branch or PR (if dev panel configured)
project = "PROJ" AND development[branches].count > 0
```

## Combining Filters

```jql
-- My open bugs, high priority
assignee = currentUser()
  AND issuetype = Bug
  AND priority in (High, Highest)
  AND status != Done
ORDER BY priority DESC

-- Team's sprint work
project = "PROJ"
  AND sprint in openSprints()
  AND status != Done
ORDER BY assignee ASC, priority DESC
```

## Field Reference

Common fields available for display:
- `summary` — issue title
- `status` — current workflow state
- `assignee` — assigned user
- `reporter` — created by
- `priority` — priority level
- `labels` — tag labels
- `issuetype` — Bug, Story, Task, Epic, etc.
- `created` / `updated` / `duedate`
- `fixVersions` — target release
- `components` — functional components

## Notes

- Date math: `-7d` = 7 days ago, `-1w` = 1 week ago, `-1M` = 1 month ago
- `currentUser()` resolves to the authenticated user's account
- Text search (`~`) is slower than field-specific searches; use sparingly on large projects
- Always add `ORDER BY updated DESC` as a default unless another sort is more relevant
