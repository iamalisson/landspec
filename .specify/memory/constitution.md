# landspec Constitution

## Project

landspec is a Claude Code plugin and a GitHub Spec Kit extension and preset. Developers who
plan features with spec-kit install it so that every task gets a GitHub issue, its own branch and
its own pull request, every commit and push is checked for secrets, every PR gets an independent
review, and every project starts from constitution defaults sized to its level. It is prompts
(`skills/`, `extension/commands/`), bash scripts (`extension/scripts/`, `bin/`) and scaffold
files, with no runtime of its own. It must never commit or push on the user's behalf outside the
flows it documents, never overwrite a file the user edited, never open a PR on red checks, and
never put a secret, an AI attribution line or a security finding into a public place.

## Stack

- Bash scripts that must run on bash 3.2 with BSD or busybox tools (macOS) and on bash 5 with
  GNU tools (Linux); CI runs both (`.github/workflows/test.yml`, jobs `linux` and `bash32`).
- Depends on `git`, the GitHub CLI `gh`, and GitHub Spec Kit `specify` at the release pinned in
  `bin/setup.sh` (`SPECKIT_VERSION`, today v1.2.5); the plugin needs Claude Code 2.1.295 or newer,
  because `hooks/hooks.json` uses `onFailure: "block"`, which needs it: below it a guard that
  times out or crashes lets the command through (`README.md`). `python3` is optional, for YAML and
  JSON checks only.
- Published as a Claude Code plugin from this repo (`.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`); its version is also in `extension/extension.yml` and
  `preset/preset.yml`, and the three are bumped together. Releases are tags `vX.Y.Z` on `main`.
- GitHub Actions in every workflow are pinned to full commit SHAs, listed once in
  `extension/scripts/pins.sh`.

**Commands**: build `python3 -c "import json; [json.load(open(f)) for f in ('.claude-plugin/plugin.json', '.claude-plugin/marketplace.json', 'hooks/hooks.json')]"` · test `tests/run.sh` · lint `shellcheck -S warning -x -P extension/scripts:tests bin/*.sh extension/scripts/*.sh tests/*.sh hooks/*.sh extension/scaffold/lite/.githooks/*` · mutate `[MUTATE_COMMAND]`

## Project principles

- **bash 3.2 is the floor.** No associative arrays, no `${var,,}`, no `mapfile`, no
  `patsub_replacement`; empty arrays are expanded as `${arr[@]+"${arr[@]}"}`, `sed -i.bak` then
  `rm -f *.bak`, case changes go through `tr`. The `bash32` job in `.github/workflows/test.yml`
  fails otherwise.
- **One shared library.** Every script sources `extension/scripts/lib.sh` and starts with
  `landspec_cd_root`; helpers (`cfg`, `feature_dir`, `base_branch`, `constitution_cmd`, `add_meta`)
  live there once and are never copied into a script.
- **Nothing of the user's is overwritten.** Generated files carry the marker line defined in
  `extension/scripts/level.sh` (`put()`) and are re-created only while it stays; files that
  cannot carry it (`.claude/settings.json`, the PR template) are written only when missing;
  `bin/remove.sh` deletes only what still matches what landspec wrote.
- **Scripts refuse, prompts explain.** A script fails with one `die` message that says what is
  missing and what to run (`extension/scripts/branch.sh`, `pr.sh`); the command prompts in
  `extension/commands/` tell Claude to show that message as is and never work around it.
- **Tests are bash and prove themselves.** One `tests/<script>.test.sh` per script, checks
  written as "when …, then …" through `tests/helpers.sh` (a throwaway repo with a local origin
  and a fake `gh`). There is no mutation tool for bash: a new behavior ships with a check that
  was seen to fail when the behavior is disabled, and the PR says so.
- **Pins and versions agree in one place.** Action SHAs live in `extension/scripts/pins.sh` and
  `bin/sync-pins.sh` copies Dependabot bumps into it; the spec-kit version is written in
  `bin/setup.sh`, `skills/init/SKILL.md` and the README badge; `tests/static.test.sh` fails on
  any drift.
- **Docs are the product's source of truth.** `/landspec:help` answers from `README.md`,
  `docs/reference.md`, `docs/design.md` and `docs/security.md`, so a behavior change edits the
  doc in the same PR. Every GUARDRAILS row and every `docs/references.yaml` entry names a primary
  source.
- **No AI attribution.** `.claude/settings.json` empties it; commit and PR bodies carry none,
  and long PR content goes in `<details>`.

<!-- landspec:start (managed by /landspec:level; edit outside this block) -->
## Defaults (landspec, level: lite)

### Simplicity (KISS, YAGNI)

- Build the smallest thing that fully solves the task. No abstraction, option or "for later" code
  nobody asked for.
- Choose in this order: what the codebase already has → the standard library → an installed
  dependency → a new dependency.

### Secrets

- No secret, token or password in the repository, in logs, or in client-side code. Configuration
  comes from the environment; `.env` files are git-ignored and an `.env.example` documents the keys.

### Accessibility (when the project has a user interface)

- What people see meets WCAG 2.2 AA: text contrast at least 4.5:1 against its background (3:1
  for large text, 24 px or 18.7 px bold, and for icons, borders and focus indicators), a visible
  focus on every control, an accessible name on every control and image. A colour copied from an
  existing page is checked too: the old page may already fail.

### Tests

- Every piece of logic (parsing, validation, money, permissions, sorting) has a test, written as
  "when …, then …".
- A failing test is never deleted, skipped or loosened to make it pass.
- One command runs the whole suite: `tests/run.sh`.

### Way of working

- One feature = one branch = one pull request; landspec creates no GitHub issues. The feature's
  tasks run in parallel, and a task is done when it lands on the feature branch with its review;
  a ticked checkbox alone is not done.
- Features go through specs and tasks. A small fix (a typo, a one-line bug, a dependency bump)
  goes on a normal branch and PR: no spec needed, but the review, hooks and CI still apply.
- Branch flow: `feat/* → main`, always through a pull request.
- Each task's diff is reviewed by a fresh reader against the whole repository before it lands
  (`/speckit-landspec-review`); High and Medium findings block it. The feature PR opens as a
  draft (`pr.sh feature`) and is marked ready only after its feature review, recorded for its
  head, and one scan of the feature diff; it merges once. Any other PR goes through `pr.sh fix`:
  its review is recorded for the exact diff and its `## Review` section says what was found and
  done.
<!-- landspec:end -->

## Governance

- This constitution supersedes other practices. Every plan.md checks against it; a violation is
  accepted only with a written justification in the plan.
- Amendments go through `/speckit-constitution` in their own PR, with semantic versioning.
- The block between the `landspec:start` and `landspec:end` markers is generated by
  `/landspec:level`; change the level instead of editing it by hand.

**Version**: 1.0.1 | **Ratified**: 2026-11-05 | **Last Amended**: 2026-11-05
