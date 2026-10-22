# Changelog

Notable changes to the lean-atlassian plugin.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions below 0.7.0 were never tagged, so each heading links the commit that
carried the version bump in `plugin.json`.

## [Unreleased]

### Added

- `SubagentStart` hook for the `atlassian-researcher` agent: the same
  `load-atlassian-config.sh`, run with `SubagentStart` as its argument, injects
  the settings into the agent's context. Before, the agent read only
  `.claude/lean-atlassian.local.md` and fell back to
  `getAccessibleAtlassianResources` with a global-only setup. A subagent gets
  no skill pointer and never makes or spends a one-time offer.
- CI `release` job: after checks pass on `main`, tags `v<version>` from
  `plugin.json` and publishes a GitHub Release with that version's CHANGELOG
  section, unless the tag already exists.

### Changed

- `tests/manifest-invariants.sh` now requires the newest released CHANGELOG
  heading to equal the `plugin.json` version, not just to appear somewhere.
- CI no longer cancels in-flight runs on `main`, only on pull requests.

- `SKILL.md` holds only what reads need (about 10 KB, from about 17 KB). Creating
  and editing issues, sprint moves, the settings file's caches and the
  `## Auto-approved operations` rules move to
  `skills/atlassian-mediation/references/jira-writes.md`, which `SKILL.md` and
  `/jira` point to before any write.
- The `SessionStart` context names the `atlassian-mediation` skill and repeats
  its three core read rules (digests, never raw JSON; `fields`/`maxResults` on
  JQL search; `content_format: markdown` on Confluence fetch), so they apply
  even when the skill's description is dropped from the skill listing.
- The skill's frontmatter `name` is kebab-case: `atlassian-mediation`.
- `/jira`'s create section no longer restates the skill's workflow, and sits
  after the numbered steps instead of splitting them.
- The skill's "save your settings" fallback checks the file is git-ignored
  before writing it, as the one-time copy offer already did.

- `atlassian-researcher` uses the `sonnet` model alias instead of the pinned
  `claude-sonnet-4-6`.

### Removed

- Confirmation of project approval lists: `trust-approval-list.sh`, the
  `${CLAUDE_PLUGIN_DATA}/trusted-lists` store, and the one-time "confirm"
  offer. A project file's `## Auto-approved operations` list is now honoured
  like a global one. **Behavior change:** a project list that was waiting for
  confirmation takes effect on upgrade, and so does any list a repository
  commits in `.claude/lean-atlassian.local.md`. An existing `trusted-lists`
  file is left in place and no longer read.

### Fixed

- Hook commands in `hooks.json` didn't quote the script path, so a plugin root
  containing a space (for example, under a `CLAUDE_CONFIG_DIR` with one) failed
  to run any hook. All three are quoted now, and `tests/manifest-invariants.sh`
  rejects an unquoted one and runs each command from a path with a space.
- A settings file copied from the `.example`, as the README's setup describes,
  auto-approved `addOrEditJiraIssueWorklog`, `createJiraIssueLink` and
  `createConfluenceComment`: the approval list was read from the example's
  fenced sample. Headings and bullets inside fenced code no longer count, and
  such a file now gets the one-time offer to add a real list.
- The `SessionStart` hook read frontmatter fields from anywhere in the file, so
  the example's sample `account_id`/`project_key` were injected when the
  frontmatter lacked them. It now reads only the frontmatter block; a file
  without one is treated as unconfigured.
- Trailing YAML comments were kept as part of a value, so the frontmatter
  template in SKILL.md (`account_id: ""   # optional …`) injected the comment
  as the accountId. Comments are now dropped.

## [0.8.0] - 2026-10-21

The plugin now targets the Atlassian MCP v2 server, which breaks installs still
on the v1 SSE connector: connect `https://mcp.atlassian.com/v2/mcp` in Claude
Code (the claude.ai "Atlassian MCP" connector). Settings files are unaffected.

### Added

- `.github/` issue forms, pull request template, and `CODEOWNERS`.
- `SECURITY.md`, describing what the settings file holds and how to report a
  finding.
- `PreToolUse` hook `approve-listed-operations.sh`: auto-approves Atlassian
  MCP v2 `executeRead`/`executeWrite` calls whose operation is listed under
  `## Auto-approved operations` in the resolved settings file. A project
  file's list counts only once the user has confirmed that exact set of
  operations; `executeDestructive` is never approved; anything unlisted falls
  through to the normal prompt. Requires `jq`.
- `trust-approval-list.sh`, which Claude runs after the user confirms a
  project list. Confirmations live in `${CLAUDE_PLUGIN_DATA}/trusted-lists`.
- One-time offers from the `SessionStart` hook, at most one per session and
  never repeated once made: copy a global-only setup into the current git
  repo's `.claude/`; add an `## Auto-approved operations` section where there
  is none; confirm an unconfirmed project list.
- `tests/approve-operations.sh` and `tests/offers.sh`, run in CI.

### Changed

- **Breaking:** the commands, agent, skill, and references now target the
  Atlassian MCP v2 server (`https://mcp.atlassian.com/v2/mcp`, tools
  `mcp__claude_ai_Atlassian_MCP__*`). The v1 SSE server, which Atlassian
  stopped supporting after 2026-06-30, is no longer supported. Renamed tools:
  `searchConfluenceUsingCql` → `searchConfluence`, `getConfluencePage` →
  `getConfluenceContent`, `addCommentToJiraIssue` →
  `addOrEditJiraIssueComment`. Project, Component, account, descendant, and
  remote-link lookups now go through `executeRead`.
- `createJiraIssue` field placement follows v2: `issueType`, `assignee`,
  `priority`, `labels`, and `assignToSprint` are top-level. Sprint moves on
  existing issues use `transitionJiraIssue`'s `sprintId` instead of writing
  `customfield_10020` with `editJiraIssue`.
- Confluence page reads ask for `content_format: "markdown"` and start from
  `detail: "outline"`, fetching the full body only when needed.
- The settings cascade moved into `hooks/lib.sh`, shared by both hooks. When
  the project's `.claude/` is the config directory itself (a session started
  in `$HOME`), the file is now treated as global rather than project-tier.
- `.shellcheckrc` lets shellcheck follow the sourced `lib.sh`.

## [0.7.0] - 2026-09-21

The plugin, marketplace, and settings file were renamed, which breaks existing
installs: remove and re-add the marketplace, then reinstall. Settings files are
unaffected.

### Changed

- **Renamed from `private-atlassian` to `lean-atlassian`** — the old name
  described the repository's former private visibility, not the plugin. The
  marketplace, plugin, plugin directory, and settings file all moved.
  Re-register with `/plugin marketplace add MatthewMaker/lean-atlassian` and
  `/plugin install lean-atlassian@lean-atlassian`.
- The `SessionStart` hook checks four candidate paths instead of two, accepting
  the legacy `private-atlassian.local.md` filename after the current name at
  both the project and global tier. Existing settings files need no migration.
  Project tier still beats global at either name.
- `plugin.json` is the sole declaration of the plugin version. It had been
  declared in three places and had already drifted — both manifests read 0.6.0
  while `SKILL.md` frontmatter still said 0.5.0.
- `$schema` in `marketplace.json` points at the URL the plugin-marketplace docs
  specify.

### Added

- `LICENSE` (MIT). The README declared the license but the file was absent.
- `repository` and `license` metadata on both manifests; `homepage` on
  `plugin.json`.
- Literal install commands in the README, which previously said only to install
  the plugin without saying how.
- `CLAUDE.md`, orienting future Claude Code sessions.
- `tests/hook-cascade.sh` — nine checks over the hook's settings-file
  precedence, optional-scalar gating, placeholder handling, and JSON escaping.
- `tests/manifest-invariants.sh` — structural manifest checks, including that
  the version is declared exactly once and that the changelog has an entry for
  it.
- GitHub Actions CI running shellcheck, both test scripts, and
  `claude plugin validate` on every pull request.

## [0.6.0] - 2026-07-06

### Added

- Issue creation wired into the `/jira` command, covering create intent, issue
  type, project defaulting, and assignee resolution.
  ([42aecc3](https://github.com/MatthewMaker/lean-atlassian/commit/42aecc3))

### Documented

- Where `createJiraIssue`'s fields actually go: `issueTypeName` rather than
  `issueType`, a bare id in top-level `assignee_account_id`, and
  priority/components/labels/custom fields inside snake_case
  `additional_fields`. Passing one to the wrong home fails silently — the
  create reports success with the fields unset.
  ([3ef6f44](https://github.com/MatthewMaker/lean-atlassian/commit/3ef6f44))
- That a sprint edit made with a cached, trusted `customfield_10020` id needs
  no confirming read. `editJiraIssue` omits the field from its response on
  success, which is a response-shape quirk rather than a failure.
  ([49d7387](https://github.com/MatthewMaker/lean-atlassian/commit/49d7387))

## [0.5.0] - 2026-07-05

### Added

- Summary prefixes map to Jira Components on create. Leading `Token: `
  segments are matched case-insensitively against the project's existing
  Components; every match is added, unmatched prefixes stay in the summary, and
  matched ones are stripped unless `component_prefix_strip: false`.
- Self-maintained Component and People caches in the settings file body, read
  lazily so sessions that never create an issue pay no context for them.
  ([7d471b7](https://github.com/MatthewMaker/lean-atlassian/commit/7d471b7))

## [0.4.0] - 2026-06-22

### Added

- Exhaustive-enumeration mode in the `atlassian-researcher` agent, for requests
  to list or recap *all* matching issues, where the default narrowing would
  silently drop real work.
  ([8bb39b0](https://github.com/MatthewMaker/lean-atlassian/commit/8bb39b0))

### Fixed

- Enumeration read the wrong path out of spilled search JSON. Issues are at
  `.issues.nodes[]`, with paging metadata at `.issues.pageInfo`; cursor paging
  via `nextPageToken` was added.
  ([886811f](https://github.com/MatthewMaker/lean-atlassian/commit/886811f))

## [0.3.0] - 2026-05-25

### Fixed

- Atlassian settings load through a `SessionStart` hook instead of a `!`-command
  injection. The command-bash permission checker rejects injected commands
  containing shell expansion, so `$CLAUDE_CONFIG_DIR` could not be referenced
  from a command or skill body.
  ([288b42b](https://github.com/MatthewMaker/lean-atlassian/commit/288b42b))

## [0.2.0] - 2026-05-25

### Changed

- `cloud_id` is injected into the session rather than read from disk at use
  time, which avoids a permission prompt.
  ([58b8b08](https://github.com/MatthewMaker/lean-atlassian/commit/58b8b08))
- Catalog version synced to `plugin.json`, which had drifted.
  ([2428caf](https://github.com/MatthewMaker/lean-atlassian/commit/2428caf))

## [0.1.1] - 2026-05-01

### Changed

- Broadened the `atlassian-mediation` skill's triggers to cover activity and
  "what changed" questions that imply a Jira or Confluence query.
  ([f4ef48e](https://github.com/MatthewMaker/lean-atlassian/commit/f4ef48e))

## [0.1.0] - 2026-02-26

### Added

- Initial plugin: the `atlassian-mediation` skill, `/jira` and `/confluence`
  commands, and the `atlassian-researcher` agent.
  ([7ddbd3e](https://github.com/MatthewMaker/lean-atlassian/commit/7ddbd3e))
- Restructured as a marketplace-compatible plugin repo with
  `.claude-plugin/marketplace.json`.
  ([a42b7f0](https://github.com/MatthewMaker/lean-atlassian/commit/a42b7f0),
  [690c179](https://github.com/MatthewMaker/lean-atlassian/commit/690c179))
