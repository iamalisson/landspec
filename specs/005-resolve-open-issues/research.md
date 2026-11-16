# Research: Resolve the open issues (#184, #185, #186)

## R1. Where the dependency clause leaks (#185)

- **Decision**: strip a trailing `(depends on …)` clause inside `task_summary` (`lib.sh`), before
  the ` in <path>` cuts, case-insensitively, English keyword only.
- **Rationale**: `task_summary` has exactly three callers, and all three are the leaks:
  `issues.sh:56` (the title, and the duplicate lookup by title), `branch.sh:49` (the slug, first 4
  words) and `next.sh:63` (the text shown). Fixing it once in the shared helper fixes all three
  (constitution: one shared library). The parsers that read dependencies (`next.sh:55-56`,
  `implement.sh:251`) read the raw line and are untouched.
- **Alternatives**: a `Depends on:` sub-bullet (two parsers that can disagree; rejected in #185
  itself); also matching `depende de` (no parser reads it, so it would hide a clause that does
  nothing).

## R2. The rule copies (#185)

- **Decision**: new wording in the four copies: `extension/commands/issues.md:38`,
  `.specify/extensions/landspec/commands/issues.md:38`,
  `.specify/extensions/landspec/.specify-dev/agent-commands/claude/speckit-landspec-issues/SKILL.md:43`,
  `skills/implement/SKILL.md:113`. Allow changing only the `(depends on …)` suffix, then
  `issues.sh --sync`.
- **Rationale**: `--sync` already rewrites the linked issue's body from the line (verified in the
  issue report); the title survives once R1 holds.

## R3. Nothing to bump today (#184)

- **Decision**: no pin moves on 2026-11-16. Every pin is already the newest release at least three
  weeks old. The pin check gets the age rule so it stops reporting releases that cannot be used
  yet. No bump task: nothing in landspec can hold a task until a date (`next.sh` blocks only on
  an open dependency issue), and a task that merged as a no-op would close #184 with no pin moved.
  When the fixed checker reports a settled release, the bump is a small fix PR.
- **Rationale** (GitHub releases, read 2026-11-16; three weeks back is 2026-10-26):

  | Tool | Pin | Newer releases (published) | Newest ≥ 3 weeks | Old enough on |
  |---|---|---|---|---|
  | osv-scanner | 2.7.0 (10-12) | 2.7.1 (11-09) | 2.7.0 | 2.7.1: 2026-11-30 |
  | semgrep | 1.183.0 (10-29) | 1.184.0 (11-05), 1.185.0 (11-10) | 1.183.0 | 1.184.0: 11-26; 1.185.0: 12-01 |
  | trivy | 0.76.1 (10-21) | 0.76.2 (11-05) | 0.76.1 | 0.76.2: 2026-11-26 |

  The issue was opened by `bin/check-tools.sh`, which compares with `releases/latest` whatever its
  age, while its own issue text says "to releases that have been out for a few weeks". The root
  cause is the checker; a bump today would break the rule `pins.sh` states for trivy.
- **How**: the checker asks for the release list and picks the newest non-prerelease whose
  `published_at` is at least 21 days old, inside gh's `--jq` (`fromdateiso8601`, `now`): no
  `date` arithmetic, so the BSD/GNU difference never comes up.
- **Alternatives**: bump to latest now (breaks the age rule, and trivy's distribution was attacked
  in March 2026, the reason the rule exists); close #184 with no change (the checker reopens it
  next Monday).

## R4. Which plan state the reviewer reports (#186)

- **Decision**: a new read-only action `review.sh state --plan [<dir>]` prints the same `state()`
  hash the gate uses (with `<dir>`: of `<dir>/plan.md` and `<dir>/tasks.md`). The reviewer first
  copies those two files out of `<checkout>` into a temp folder, runs `state --plan <folder>` in its
  own copy, reviews the copied files, and writes `Plan state: <hash>` in the report. `record --plan` compares that line with the current
  `state()` and refuses when it is missing or different.
- **Rationale**: hashing the snapshot it reads means the state is exactly the text reviewed; an
  edit in the checkout after the copy can only cause a refusal at record time. The isolated
  reviewer cannot run git in `<checkout>` (the harness refuses it, plan review round 2), and its
  own copy is a clean checkout of the commit without the uncommitted spec folder, so `feature_dir`
  finds nothing there: the folder argument avoids both. The reviewer may not write to `<checkout>`, so `state` must
  return before `review.sh` creates `.git/landspec-review` (today line 39 runs `mkdir -p` for
  every action); `feature_dir` only reads `.specify/feature.json`.
- **Alternatives**: hash at record time (the bug); commit the plan before reviewing (the spec PR
  flow keeps plan edits uncommitted until `pr.sh spec`, by design); have the reviewer compute
  the hash by hand (`sha256` differs between macOS and Linux; one shared helper avoids drift).

## R5. Upgrades (#186)

- **Decision**: a plan report with no `Plan state:` line is refused with "the report has no Plan
  state line: run the review again (this landspec version records it)". One line in the release
  notes.
- **Rationale**: the only safe reading of an old report is "we do not know what it read".
