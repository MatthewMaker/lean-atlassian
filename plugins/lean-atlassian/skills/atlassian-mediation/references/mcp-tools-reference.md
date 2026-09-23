# Atlassian MCP Tools Reference

Quick reference for all available tools from the Atlassian MCP server.

## Authentication / Setup

| Tool | Purpose | When to use |
|------|---------|-------------|
| `atlassianUserInfo` | Get current user info | Rarely needed; useful for debugging auth |
| `getAccessibleAtlassianResources` | Get cloudId and site info | Only if `cloud_id` not in settings file |

## Search

| Tool | Purpose | Key params |
|------|---------|-----------|
| `search` | General cross-product search | `cloudId`, `query`, `limit` |
| `searchJiraIssuesUsingJql` | JQL-based Jira search | `cloudId`, `jql`, `maxResults` |
| `searchConfluenceUsingCql` | CQL-based Confluence search | `cloudId`, `cql`, `limit` |

**Prefer the specific tools** (`searchJiraIssuesUsingJql`, `searchConfluenceUsingCql`) over
the general `search` — they return cleaner, more structured results.

## Jira

### Read Operations

| Tool | Purpose | Key params |
|------|---------|-----------|
| `getJiraIssue` | Fetch a single issue by key | `cloudId`, `issueIdOrKey` |
| `getVisibleJiraProjects` | List accessible projects | `cloudId` |
| `getJiraProjectIssueTypesMetadata` | Get issue types for a project | `cloudId`, `projectIdOrKey` |
| `getTransitionsForJiraIssue` | List valid status transitions | `cloudId`, `issueIdOrKey` |
| `getJiraIssueRemoteIssueLinks` | Get linked external issues | `cloudId`, `issueIdOrKey` |

### Write Operations

| Tool | Purpose | Key params |
|------|---------|-----------|
| `createJiraIssue` | Create a new issue | `cloudId`, `projectKey`, `summary`, `issueTypeName`; assignee via `assignee_account_id`; priority/components/labels/custom fields via `additional_fields` |
| `editJiraIssue` | Edit issue fields | `cloudId`, `issueIdOrKey`, `fields` (assignee included — unlike create) |
| `transitionJiraIssue` | Move issue to new status | `cloudId`, `issueIdOrKey`, `transitionId` |
| `addCommentToJiraIssue` | Add a comment | `cloudId`, `issueIdOrKey`, `body` |
| `addWorklogToJiraIssue` | Log time | `cloudId`, `issueIdOrKey`, `timeSpent` |
| `lookupJiraAccountId` | Find a user's account ID | `cloudId`, `query` |
| `createIssueLink` | Link two issues | `cloudId`, `inwardIssue`, `outwardIssue`, `type` — all **plain strings** (`"MYPROJ-123"`, `"Relates"`), not objects |

## Confluence

### Read Operations

| Tool | Purpose | Key params |
|------|---------|-----------|
| `getConfluencePage` | Fetch a page by ID | `cloudId`, `pageId`, `contentFormat` |
| `getConfluencePageDescendants` | List child pages | `cloudId`, `pageId` |
| `getConfluenceSpaces` | List accessible spaces | `cloudId` |
| `getConfluencePageFooterComments` | Get footer comments | `cloudId`, `pageId` |
| `getConfluencePageInlineComments` | Get inline comments | `cloudId`, `pageId` |

### Write Operations

| Tool | Purpose | Key params |
|------|---------|-----------|
| `createConfluencePage` | Create a new page | `cloudId`, `spaceId`, `title`, `body` |
| `updateConfluencePage` | Edit a page | `cloudId`, `pageId`, `version`, `body` |
| `createConfluenceFooterComment` | Add footer comment | `cloudId`, `pageId`, `body` |
| `createConfluenceInlineComment` | Add inline comment | `cloudId`, `pageId`, `body`, `inlineMarker` |

## General

| Tool | Purpose | Key params |
|------|---------|-----------|
| `fetch` | Fetch by ARI (Atlassian Resource Identifier) | `id` (ARI string) |

Use `fetch` when you have an ARI from search results and need full details.
ARIs look like: `ari:cloud:jira:CLOUD_ID:issue/10107`

## cloudId Notes

- Every tool requires `cloudId` except `atlassianUserInfo` and `getAccessibleAtlassianResources`
- `cloudId` is a UUID, e.g., `"a1b2c3d4-1234-5678-abcd-ef0123456789"`
- Read from `.claude/lean-atlassian.local.md` settings file
- If not set, call `getAccessibleAtlassianResources` once and cache

## Content Format Notes

For `getConfluencePage`, always use `contentFormat: "markdown"` rather than `"adf"`.
ADF (Atlassian Document Format) is verbose JSON that bloats context significantly.
Markdown is human-readable and token-efficient.
