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

The `SessionStart` hook is the part worth scrutinising — it is the only
executable code here, and it runs automatically in every session of every
install. It reads a settings file and prints JSON; it does not evaluate the
file's contents. A finding that it can be made to do anything else is worth
reporting.

No formal support window is offered. Fixes land on `main` and ship in the next
version bump.
