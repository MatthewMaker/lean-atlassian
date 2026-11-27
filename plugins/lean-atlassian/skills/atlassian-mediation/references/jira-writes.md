# Jira writes and the settings file

Read this before any Jira write — `createJiraIssue`, `editJiraIssue`,
`transitionJiraIssue`, a sprint move — and before rewriting the settings file.
SKILL.md covers reads.

## Creating Issues

Create issues with `createJiraIssue`. Default the `projectKey` to the injected
`project_key` and assignment-to-self to the injected `account_id` unless the
user says otherwise. Layer the prefix→Component behavior below on top.

### Field placement

`createJiraIssue` spreads its fields across several homes, and passing one to
the wrong home **fails silently**: the server ignores an unknown top-level
parameter rather than rejecting it, so the call returns a normal-looking issue
with that field unset.

| Field | Where it goes |
|-------|---------------|
| `summary`, `description`, `projectKey`, `parent` | own top-level parameters |
| issue type | top-level `issueType`, by name (`"Task"`, `"Bug"`) |
| assignee | top-level `assignee`, a bare accountId string |
| `priority` | top-level, by name (`"High"`) |
| `labels` | top-level, a list of strings |
| sprint | top-level `assignToSprint`, the numeric sprint id as a string |
| `components`, `fixVersions`, `customfield_*`, anything else | inside `additional_fields` |

`additional_fields` is **snake_case**. Keyed by `customfield_*` id or a system
field, it takes the raw Jira shape:

```json
{"components": [{"name": "Frontend"}], "customfield_10010": 8}
```

`editJiraIssue` takes the same `additional_fields`, plus a **`fields`**
parameter for raw Jira shapes, where assignee is an object rather than a bare
accountId. It does not set the sprint at all (see **Sprint assignment**):

```json
{"assignee": {"accountId": "…"}, "components": [{"name": "Frontend"}]}
```

The tool's description says `fields` accepts a bare accountId for assignee.
It doesn't: the edit reports success and leaves the assignee unchanged. A bare
accountId does work under `additional_fields`.

Getting this wrong is not hypothetical. Under the v1 server, a batch of issues
created with a camelCase `additionalFields` and a nested `assignee` came back
with assignee, components, priority and sprint all unset, and each create
reported success.

A create the server *does* reject comes back with a `repairHint` naming the
field at fault; correct that field and retry.

This is a "pass the right shape" rule, not a "verify afterwards" rule — it adds no
follow-up read. The plugin's `PostToolUse` hook does the checking: it compares
each `createJiraIssue` and `editJiraIssue` response with the request, and when
a field didn't apply it adds a note beside the result naming the field. Act on
that note; without one, there's no need to read the issue back.

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
   matches nothing — fetch the live list with `executeRead`, at most once per
   project per session, and
   `name: "listJiraProjectComponents"`, `inputs: {projectIdOrKey: <key>}` (read
   each component's `name`), then rewrite the cache section.

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

   Apply steps 4 and 5 even when the project's existing issues don't: recent
   tickets that kept a matching prefix in the summary, or lack the Component, are
   not a setting. Only `component_prefix_strip: false` keeps the prefix, and only a
   **Prefix exceptions** entry stops a token from mapping.

6. **Confirm.** After creating, report the resolved Components and the final
   summary, e.g. *"Created MYPROJ-123 (components: Frontend, Backend) — 'Fix login
   button'."*

### Assignees and people

To assign an issue or filter by a person, resolve the name to an accountId via
the **People cache** in the settings file first. On a miss, call (via
`executeRead`) `listJiraIssueAssignableUsers` to assign
(`inputs: {project: <key>, query: <name>}`; it returns only people who can be
assigned there) or `lookupJiraAccountId` to filter (`inputs: {query: <name>}`),
then append the result to the cache so future references skip the lookup. Use the injected `account_id` for the current user
without any lookup.

## Editing Issues

Use `editJiraIssue` to change fields on an existing issue (assignee, priority,
description, etc.). Multi-value fields are replaced, not appended: send the full
list for `labels` and `components`. Status and sprint changes go through
`transitionJiraIssue` instead.

### Sprint assignment

Sprints are addressed by the sprint's **numeric id**, **not** the sprint
number. `createJiraIssue`'s `assignToSprint` also accepts the exact sprint name
or `"active"`.

- **New issue**: pass `assignToSprint: "<id>"` to `createJiraIssue`. The response
  reports `sprintAssignment.assigned`. If it is `false`, the issue was still
  created — don't create it again; move it with `transitionJiraIssue` below.
- **Existing issue**: call `transitionJiraIssue` with `issueIdOrKey` and
  `sprintId: <id>` (an integer). The session-start context names the current
  sprint's id when the settings file caches it (see **Current sprint** below).
  When that line says the cache expired, or there's no line, refresh the cache
  first. No workflow transition is needed alongside it.
  `assignToBacklog: true` moves it out of a sprint instead.

Sprint moves haven't been seen to fail on either path, so don't read the issue
back to confirm one.

### Resolutions

A workflow's transition screen may not include `resolution`. Setting it in
`transitionJiraIssue`'s `fields` then fails with *"Field 'resolution' cannot
be set. It is not on the appropriate screen, or unknown."* The `repairHint`
that comes with it suggests passing `resolution: null`, which clears the
resolution rather than setting it; don't follow it. Instead:

1. Transition with no `fields`. A Done-category transition usually sets
   resolution `Done` by itself, so plain Done needs nothing more.
2. For any other resolution, follow up with `editJiraIssue` and
   `fields: {"resolution": {"name": "Won't Do"}}`.

### Descriptions and comments

Markdown is the default `contentFormat` for descriptions and comments, and
paragraphs, headings, bold, bullets and code render as expected in both.

Markdown checkboxes don't become Jira checkboxes. `- [ ]` is stored as a plain
bullet and `- [x]` as a struck-through one, and both read back as `- [ ]` /
`- [x]`, so a read can't tell a real checklist from a struck-through list.
To check, fetch with `expand: "renderedFields"`: a struck item renders as
`<del>`. For real checkboxes, get the HTML shape from
`executeRead(name: "getContentFormatGuide", inputs: {toolName: "editJiraIssue"})`.
Don't rewrite a description through markdown just to tick one box: a real
checklist comes back as plain bullets.

## Settings-file caches (file body)

Nested data is **not** injected at SessionStart — it is read (and written) lazily
by the **Creating Issues** workflow, only when needed, so no session pays context
for a map it will not use. Prefer the project-level settings file when writing,
since this data is project-specific. Maintain two Markdown sections in the file
body, refreshing each on a miss (append the freshly-fetched value, exactly like a
self-updating note):

- **Component cache** — one list of Component names per project key. On a prefix
  that matches nothing, re-fetch the project's live Components (one may have
  been added) unless this session already did, rewrite the list, then retry.
- **People cache** — a `Full Name: accountId` list for people you assign or query
  about. On a name miss, look the person up as **Assignees and people**
  describes, then append them here.

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

### Current sprint

One more body section holds the board's active sprint. Unlike the caches
above, the `SessionStart` hook reads it: it injects the id while `ends` is in
the future, and an instruction to refresh once it has passed.

```markdown
## Current sprint (auto-maintained)

- board: 7
- sprint: Sprint 12
- id: 340
- ends: 2026-07-20T05:00:00.000Z
```

Write or rewrite it, in the settings file the hook names, when:

- the session-start context says it expired or is unreadable,
- you need a sprint id and the file has no such section, or
- Jira rejects the cached id as a closed sprint (it ended early).

To refresh, call `executeRead` with `name: "getJiraBoardSprintData"`,
`inputs: {boardId: "<board>", includeIssues: false}` and
`responseFields: ["resolvedSprint"]`, and copy `id`, `name` and `endDate`
(verbatim, a UTC timestamp) into the section. With no board known yet, find
it with `executeRead` `listJiraBoards`, `inputs: {projectKeyOrId: <project_key>}`,
and pick the Scrum board.

## Auto-approved operations (a permission grant)

The settings file may hold a `## Auto-approved operations` section. The
plugin's `PreToolUse` hook auto-approves `executeRead`/`executeWrite` calls for
the operations listed there.

- **Write it only on the user's say-so**: when they accept a one-time offer
  injected at session start, or ask outright. Never on your own initiative,
  and never as a side effect of refreshing the caches — carry the section over
  byte-for-byte whenever you rewrite the file.
- Write the heading and bullets as plain Markdown, never inside a code fence:
  the hook ignores fenced lines.
- Never list anything the user hasn't named or approved, and never offer to
  list a destructive operation — the hook won't approve one anyway.
