## What changes

<!-- What behaves differently after this, in a sentence or two. -->

## Why

<!-- Only state reasons you can point at. If the motivation is "it was asked
     for", say that rather than inventing a rationale. -->

## Checks

```bash
tests/hook-cascade.sh
tests/manifest-invariants.sh
shellcheck plugins/*/hooks/*.sh tests/*.sh
claude plugin validate .
```

- [ ] All four pass locally (CI runs them too)

## If this changes behavior

- [ ] `SKILL.md` carries the change; the commands still delegate rather than
      restating it
- [ ] README and `.claude/lean-atlassian.local.md.example` describe any new or
      changed setting
- [ ] `plugin.json` version bumped, with a matching `## [x.y.z]` heading in
      `CHANGELOG.md` — `tests/manifest-invariants.sh` enforces the pairing
- [ ] Breaking for existing installs? Say so in the changelog entry and give
      the remove/re-add commands

## Notes for review

<!-- Anything deliberately left out, or a decision worth a second opinion. -->
