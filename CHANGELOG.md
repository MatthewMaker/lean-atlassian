# Changelog

Notable changes to the lean-atlassian plugin.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions below 0.7.0 were never tagged, so each heading links the commit that
carried the version bump in `plugin.json`.

## [Unreleased]

### Added

- `.github/` issue forms, pull request template, and `CODEOWNERS`.
- `SECURITY.md`, describing what the settings file holds and how to report a
  finding.

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
