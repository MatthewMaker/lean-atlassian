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

`editJiraIssue` is different: it takes a parameter named **`fields`** with raw
Jira shapes, assignee included, and does not set the sprint at all (see
**Sprint assignment**):

```json
{"assignee": {"accountId": "…"}, "components": [{"name": "Frontend"}]}
```

Getting this wrong is not hypothetical. Under the v1 server, a batch of issues
created with a camelCase `additionalFields` and a nested `assignee` came back
with assignee, components, priority and sprint all unset, and each create
reported success.

A create the server *does* reject comes back with a `repairHint` naming the
field at fault; correct that field and retry.

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
   matches nothing — fetch the live list once with `executeRead` and
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

6. **Confirm.** After creating, report the resolved Components and the final
   summary, e.g. *"Created MYPROJ-123 (components: Frontend, Backend) — 'Fix login
   button'."*

### Assignees and people

To assign an issue or filter by a person, resolve the name to an accountId via
the **People cache** in the settings file first. On a miss, call
`lookupJiraAccountId` once (via `executeRead`, `inputs: {query: <name>}`), then
append the result to the cache so future
references skip the lookup. Use the injected `account_id` for the current user
without any lookup.

## Editing Issues

Use `editJiraIssue` to change fields on an existing issue (assignee, priority,
description, etc.). Multi-value fields are replaced, not appended: send the full
list for `labels` and `components`. Status and sprint changes go through
`transitionJiraIssue` instead.

### Sprint assignment

Sprints are addressed by the sprint's **numeric id**, **not** the sprint
number.

- **New issue**: pass `assignToSprint: "<id>"` to `createJiraIssue`. The response
  reports `sprintAssignment.assigned`. If it is `false`, the issue was still
  created — don't create it again; move it with `transitionJiraIssue` below.
- **Existing issue**: call `transitionJiraIssue` with `issueIdOrKey` and
  `sprintId: <id>` (an integer). No workflow transition is needed alongside it.
  `assignToBacklog: true` moves it out of a sprint instead.

**Don't follow either with `getJiraIssue` to check.** Both responses say whether
the sprint move happened; a confirming read spends context on something the
response already told you.

## Settings-file caches (file body)

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
  about. On a name miss, call `lookupJiraAccountId` (via `executeRead`) once,
  then append it here.

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
