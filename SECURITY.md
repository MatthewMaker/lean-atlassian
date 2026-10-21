# Security

## What this plugin does and doesn't hold

It holds **no credentials**. Authentication to Jira and Confluence belongs
entirely to the Atlassian MCP server; this plugin only shapes the requests sent
through it and summarises what comes back.

What it does store, in an uncommitted `lean-atlassian.local.md`:

| Field | What it is |
|-------|------------|
| `cloud_id`, `site_url` | Your Atlassian workspace UUID and URL |
| `account_id` | Your own Jira accountId |
| `project_key` | A default project key |
| Component cache | Component names for your projects |
| People cache | Colleagues' names paired with their Jira accountIds |
| Auto-approved operations | Atlassian operations the `PreToolUse` hook may run without a prompt |

The plugin's data directory (`${CLAUDE_PLUGIN_DATA}`) holds the fingerprints of
project lists you've confirmed, and markers for offers already made.

None of these are secrets in the sense that a token is — they don't grant
access on their own. They do identify your organisation and your colleagues,
which is why the file is never committed.

## The realistic incident

Committing a settings file. The most sensitive thing in it is the people cache:
real names mapped to accountIds, for an entire team.

`.gitignore` covers `.claude/*.local.md`, which catches a file in the standard
per-project location. It does **not** catch one you put somewhere else, and the
global-tier file lives in your Claude config directory, outside any repository.
GitHub secret scanning with push protection is enabled here, but these
identifiers are not the kind of token those rules recognise — don't count on
them for this.

If you do commit one: the identifiers can't be rotated the way a key can.
Removing the file and rewriting the history is the only remedy, and it's worth
telling anyone whose accountId was in the people cache.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting — the **Security** tab, or
[report one directly](https://github.com/MatthewMaker/lean-atlassian/security/advisories/new).
That keeps the report private until a fix ships. If you'd rather not use
GitHub, email **info@entropyreductionservices.com**.

Either way, describe the class of problem and how to reproduce it, and please
don't open a public issue first.

The two hooks are the parts worth scrutinising — they are the only executable
code here (with `trust-approval-list.sh`, which Claude runs on your say-so),
and they run automatically in every session of every install. Each reads a
settings file and prints JSON; neither evaluates the file's contents. A
finding that either can be made to do anything else is worth reporting.

The `PreToolUse` hook is the one that grants anything: it approves Atlassian
`executeRead`/`executeWrite` calls whose operation is listed in the resolved
settings file — for a project file, only once you've confirmed that exact set
of operations. A way to make it approve an unlisted operation, an
`executeDestructive` call, or an unconfirmed project list is a vulnerability.

The confirmation is a fingerprint Claude records after asking you. It guards
against a list a repository committed without your noticing; it is not a
barrier against Claude itself, which acts with your permissions either way.

No formal support window is offered. Fixes land on `main` and ship in the next
version bump.
