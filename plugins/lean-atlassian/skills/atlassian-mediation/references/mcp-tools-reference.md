# Atlassian MCP Tools Reference

Quick reference for the Atlassian MCP v2 server
(`https://mcp.atlassian.com/v2/mcp`). In Claude Code the tools are
`mcp__claude_ai_Atlassian_MCP__<name>`.

The server has two layers. **Primary tools** are called directly. **Operations**
are reached through a runner matching their risk tier — `executeRead`,
`executeWrite`, `executeDestructive` — with a top-level `cloudId`, the operation
`name`, and a flat `inputs` object:

```
executeRead(name: "listJiraIssueTransitions", cloudId: <from settings>,
            inputs: {issueIdOrKey: "MYPROJ-123"})
```

Use only operation names listed here or returned by `discover`; never guess one.
`responseFields` (dot paths, e.g. `["key", "fields.summary"]`) trims any runner's
response.

## Authentication / Setup

| Tool | Purpose | When to use |
|------|---------|-------------|
| `atlassianUserInfo` | Get the current user's accountId | Only if `account_id` isn't in the settings file |
| `getAccessibleAtlassianResources` | Get cloudId and site info | Only if `cloud_id` isn't in the settings file |
| `discover` | Find an operation by goal (`query: "list confluence spaces"`) | When you need an operation not listed here |

## Search

| Tool | Purpose | Key params |
|------|---------|-----------|
| `searchJiraIssuesUsingJql` | JQL-based Jira search | `cloudId`, `jql`, `fields`, `maxResults` (default 50, max 100), `nextPageToken` |
| `searchConfluence` | CQL-based Confluence search | `cloudId`, `cql`, `limit` (default 25), `cursor` |
| `search` | Rovo semantic search across Jira, Confluence, and connected apps | `cloudId`, `query`, `targetApp`, `limit` (10–30) |

**Prefer the JQL/CQL tools** over `search`. They return structured, scoped
results, and `search` can spend up to 10 Rovo credits per call (it fails when
the org has none left).

`searchJiraIssuesUsingJql` honours `fields`; issues are at `.issues.nodes[]`, and
paging is at `.issues.pageInfo` — pass `endCursor` as `nextPageToken` while
`hasNextPage` is true.

## Jira

### Primary tools

| Tool | Purpose | Key params |
|------|---------|-----------|
| `getJiraIssue` | Fetch a single issue | `cloudId`, `issueIdOrKey`, `view` (`compact` default; `evidence` adds issue links and custom fields) |
| `createJiraIssue` | Create an issue | `cloudId`, `projectKey`, `summary`, `issueType`; top-level `assignee` (accountId), `priority`, `labels`, `parent`, `assignToSprint` (sprint id); components/fixVersions/custom fields in `additional_fields` |
| `editJiraIssue` | Edit issue fields | `cloudId`, `issueIdOrKey`, `fields` (raw Jira shapes, assignee included as `{"accountId": …}`); multi-value fields are replaced, not appended |
| `transitionJiraIssue` | Change status and/or sprint | `cloudId`, `issueIdOrKey`, `transitionId` or `transitionName`, `sprintId` (integer), `assignToBacklog` |
| `addOrEditJiraIssueComment` | Add a comment, or edit one by `commentId` | `cloudId`, `issueIdOrKey`, `commentBody` (markdown) |

An unknown top-level parameter is silently ignored, not rejected — a field in
the wrong place leaves it unset with no error. See `jira-writes.md`'s *Field placement*.

### Operations

| Operation | Runner | Purpose | Key inputs |
|-----------|--------|---------|-----------|
| `listJiraProjects` | `executeRead` | Projects the user can see | `query` |
| `listJiraProjectComponents` | `executeRead` | A project's Components | `projectIdOrKey` |
| `listJiraProjectIssueTypesMetadata` | `executeRead` | Issue types for a project | `projectIdOrKey` |
| `getJiraIssueTypeMetaWithFields` | `executeRead` | Create fields for one issue type | `projectIdOrKey`, `issueTypeId` |
| `lookupJiraAccountId` | `executeRead` | A user's accountId by name or email | `query` |
| `listJiraIssueAssignableUsers` | `executeRead` | Users who can be assigned in a project | `project` or `issueKey`, `query` |
| `listJiraIssueTransitions` | `executeRead` | Valid status transitions for an issue | `issueIdOrKey` |
| `listJiraIssueComments` | `executeRead` | An issue's comments | `issueIdOrKey` |
| `listJiraIssueRemoteIssueLinks` | `executeRead` | Web links (Confluence pages, URLs) on an issue | `issueIdOrKey` |
| `listJiraIssueLinkTypes` | `executeRead` | Link type names and their wording | — |
| `createJiraIssueLink` | `executeWrite` | Link two issues | `linkType`, `inwardIssue`, `outwardIssue` — plain strings (`"Blocks"`, `"MYPROJ-1"`) |
| `addOrEditJiraIssueWorklog` | `executeWrite` | Log time, or edit a worklog by `worklogId` | `issueIdOrKey`, `timeSpent` (`"2h 30m"`), `comment` |

## Confluence

### Primary tools

| Tool | Purpose | Key params |
|------|---------|-----------|
| `getConfluenceContent` | Read a page, blog post, or other content | `cloudId`, `content_id` or `content_url`, `content_format` (`html` default — pass `markdown`), `detail` (`summary` default, `outline`, `full`) |
| `createConfluenceContent` | Create a page or other content | `cloudId`, `parent` (`{spaceId}` and/or `{parentContentId}`), `contentType` (`page`), `title`, `body` (`{format, value}`) |
| `updateConfluenceContent` | Edit content | `cloudId`, `contentId`, `snapshotToken` (from a prior `getConfluenceContent`), `body` or `edits` |

Before authoring a body for create or update, the server asks for its format
guide: `executeRead(name: "getContentFormatGuide", inputs: {toolName: "createConfluencePage"})`
(or `updateConfluencePage`).

### Operations

| Operation | Runner | Purpose | Key inputs |
|-----------|--------|---------|-----------|
| `getConfluenceContentDescendants` | `executeRead` | Child pages | `contentId`, `depth` (default 2), `limit` |
| `listConfluenceSpaces` | `executeRead` | Accessible spaces | `keys`, `limit` |
| `getConfluenceSpace` | `executeRead` | One space, with its authoring instructions | `spaceIdOrKey` |
| `listConfluenceComments` | `executeRead` | A page's footer and inline comments | `content-id`, `comment-type` |
| `createConfluenceComment` | `executeWrite` | Add a comment, or reply to one | `contentId`, `commentType` (`footer`/`inline`), `body` (`{format, value}`) |

## Teamwork Graph

| Tool | Purpose | Key params |
|------|---------|-----------|
| `getGraphContext` | Relationships around an entity, across products | `cloudId`, `objectType`, `objectIdentifier` |
| `getGraphObject` | Full data for ARIs or URLs from `getGraphContext` | `cloudId`, `objects` (≤ 25) |

Both can spend Rovo credits. Use them for "what's connected to X" questions,
not for fetching a single issue or page.

## cloudId Notes

- Every tool requires `cloudId` except `atlassianUserInfo`,
  `getAccessibleAtlassianResources`, and `discover`
- On the `execute*` runners, `cloudId` is a top-level argument, never inside `inputs`
- `cloudId` is a UUID, e.g., `"a1b2c3d4-1234-5678-abcd-ef0123456789"`
- Read from the settings file; if not set, call `getAccessibleAtlassianResources`
  once and cache

## Content Format Notes

For `getConfluenceContent`, always pass `content_format: "markdown"`. The default
is HTML, which is far more verbose. Start with `detail: "summary"` or
`"outline"`, and fetch `"full"` only for the part the user wants to read.
