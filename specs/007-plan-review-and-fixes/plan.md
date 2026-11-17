# Implementation Plan: A plan review that can be trusted, and the open bugs (#187, #188, #206, #216, #217, #218)

**Branch**: `spec/007-plan-review-and-fixes` | **Date**: 2026-11-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-plan-review-and-fixes/spec.md`

## Summary

The plan review becomes checkable instead of trusted:
- **Passes with tables:** one reviewer per round fills a table for each of eight passes (size,
  requirements, rules, claims, inputs, guards, rollout, orderings). `review.sh record --plan`
  refuses a `ready` with a missing, empty or failing table, or with a spec requirement id that has
  no row (research R1, R2).
- **Fix rounds read cold:** the reviewed folder is kept, so a fix round gets the diff since the
  last round and the earlier report, never the author's answers (R3, R4).
- **Areas that keep breaking:** an area with 3 findings gets a Simplify section the developer must
  answer (R5).
- **The whole folder:** the plan state covers every document of the feature folder (R7).
- **Moved to a follow-up feature:** the 12-task split with a second reader, and the plan delta
  (R6, R8), after seven plan review rounds of this feature kept finding gaps between them.
- **Statistics:** plan rounds, findings and outside findings appear in the statistics report (R9).

Three bugs are fixed at their root:
- **#216:** the task delta's line count subtracts a base merge through `git merge-tree` (R10).
- **#217:** a failed semgrep run names the first error from its JSON (R11).
- **#218:** a new `formatters.sh` run by `/landspec:adopt` finds formatter hooks that would rewrite
  most files, in a throwaway worktree (R12).

## Technical Context

**Language/Version**: bash 3.2+ (BSD, busybox, GNU); markdown prompts.

**Primary Dependencies**:
- `git`: `diff --no-index`, and `merge-tree --write-tree` (git 2.38 or newer; older git keeps
  today's count);
- `gh` and `pre-commit`: optional, and only for `formatters.sh`.

**Storage**: `.git/landspec-review/` (the kept plan copy, area log), `.git/landspec-events` (new event kinds); nothing in the tree.

**Testing**: `tests/run.sh`; checks added to `review`, `stats`, `security-scan`, `static` tests, and a new `tests/formatters.test.sh`; fixtures in `tests/fixtures/plan-review/` (quickstart Q1–Q13, without Q4 and Q6).

**Target Platform**: Linux and macOS.

**Project Type**: Claude Code plugin plus spec-kit extension.

**Performance Goals**:
- A plan review round may take longer per round: it enumerates instead of sampling. The target is
  fewer rounds (SC-008).
- `record --plan` stays a few hundred milliseconds of awk and grep.

**Constraints**:
- bash 3.2: no associative arrays, so the area log is a flat file counted with awk.
- busybox: no `python3` or `jq`, so semgrep's JSON is read with grep and sed.
- The reviewer never writes to the author's checkout.
- `formatters.sh` never writes to the user's files.

**Scale/Scope**: about 15 files plus their project copies; 8 tasks (see Notes).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | How | Status |
|---|---|---|
| bash 3.2 is the floor | flat files and awk instead of associative arrays; `git diff --no-index` instead of `diff -r` output parsing (busybox `diff` prints unified only); JSON read with grep and sed | pass |
| One shared library | `formatters.sh` sources `lib.sh` and starts with `landspec_cd_root`; the plan-state hashing stays one `state()` in `review.sh`, reused by `record`, `check`, `diff` | pass |
| Nothing of the user's is overwritten | kept copies and logs live in `.git`; `formatters.sh` runs the hooks in a throwaway worktree and removes it on exit | pass |
| Scripts refuse, prompts explain | every new refusal is one `die` naming the pass and row, or the command to run next (`answer --plan`, a full plan review) | pass |
| Tests are bash and prove themselves | each behavior has a "when …, then …" check seen failing with it disabled (Q13); fixtures are literal folders, not generated from the code under test | pass |
| Pins and versions agree in one place | no pin changes; the version goes to 2.8.0 in the three files at release | pass |
| Docs are the product's source of truth | `docs/reference.md` changes in the same PR as each behavior; release notes at the release | pass |
| No AI attribution | unchanged | pass |
| One task = one issue = one PR | 8 tasks, each one behavior; the review-prompt tasks are stacked, since they edit the same sections | pass |

Post-design re-check: no violation.

## Project Structure

### Documentation (this feature)

```text
specs/007-plan-review-and-fixes/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/changes.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
extension/scripts/review.sh         # plan state, tables, copy, diff, answer, outside; #216 count
extension/scripts/issues.sh         # issues event
extension/scripts/stats.sh          # PLAN line
extension/scripts/security-scan.sh  # semgrep reason (#217)
extension/scripts/formatters.sh     # new (#218)
extension/commands/review.md        # subagent step 2, facts, Plan review as eight passes
extension/commands/issues.md        # step 2: rounds, Simplify, outside
agents/reviewer.md                  # step 2: copy the whole folder
agents/implementer.md               # formatter failure line
skills/implement/SKILL.md           # plan-review steps it repeats
skills/adopt/SKILL.md               # formatters step
.specify/extensions/landspec/…      # project copies, kept identical
tests/{review,stats,security-scan,static,formatters}.test.sh, tests/fixtures/plan-review/
docs/reference.md, docs/releases/2.8.0.md
```

**Structure Decision**: edits in place; one new script (`formatters.sh`) with its test, and one
fixtures folder.

## Complexity Tracking

No violations.

## Notes

- **Ordering of tasks.** The plan-review tasks edit the same parts of `review.sh` (`record --plan`)
  and `review.md` ("Plan review"), so they are stacked: plan state over the folder, kept copy and
  `diff --plan`; then the pass tables; then fix rounds without answers (with the area tag); then
  areas and Simplify; then the statistics (they edit the same event line and issues.md step).

  #216, #217 and #218 touch other code and start at once.
- **Invariant** (data-model "Invariant"): a plan state is `ready` only through a report recorded
  for exactly that state with every pass passing, no `open` row in its earlier findings and no open
  Simplify question. Each refusal is a case of it.
- **This feature's own plan review** runs with 2.7.0's reviewer, because the new one ships with
  it. Q12 checks the new one on this folder after the merge.
- **Size of this plan:** 8 tasks.
- **The 2.7.0 audit findings** are not part of this feature: the repository is public, and
  `/landspec:security` handles them privately.
