# Implementation Plan: Resolve the open issues (#184, #185, #186)

**Branch**: `spec/005-resolve-open-issues` | **Date**: 2026-11-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-resolve-open-issues/spec.md`

## Summary

Three small fixes, each at its root:
- **#185**: `task_summary` drops a trailing `(depends on …)` clause, so the issue title, the
  branch slug and the `next` text stop changing when a dependency is added; the four copies of the
  "linked line" rule allow changing that suffix, followed by `issues.sh --sync` (research R1, R2).
- **#184**: no pin can move today: each is already the newest release three weeks old (R3). The
  real defect is `bin/check-tools.sh`, which reports releases younger than the age rule; it now
  compares with the newest settled release. The bump itself happens when a release is old enough.
- **#186**: the reviewer reports the plan state it read, taken with a new read-only
  `review.sh state --plan` before it reads; `record --plan` refuses a missing or different state
  (R4, R5).

## Technical Context

**Language/Version**: bash 3.2+ (BSD, busybox, GNU); markdown prompts.

**Primary Dependencies**: git, gh (`--jq` with `fromdateiso8601` and `now` for the release age).

**Storage**: none new.

**Testing**: `tests/run.sh`; checks added to `issues`, `branch`, `next`, `check-tools`, `review` tests (quickstart Q1–Q8).

**Target Platform**: Linux and macOS.

**Project Type**: Claude Code plugin plus spec-kit extension.

**Performance Goals**: none beyond today's (one extra `sed` in `task_summary`; one gh call per tool, as now).

**Constraints**: bash 3.2 (no `sed` `I` flag: BSD lacks it); the reviewer never writes to the checkout; pins only to releases three weeks old.

**Scale/Scope**: about 10 files plus their project copies.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | How | Status |
|---|---|---|
| bash 3.2 is the floor | case-insensitive match through `tr` on a copy, not `sed …I`; date math inside gh's jq, not `date -d` | pass |
| One shared library | the fix is in `lib.sh task_summary`, the one helper all three callers use; `state()` reused, not copied | pass |
| Nothing of the user's is overwritten | no file written | pass |
| Scripts refuse, prompts explain | two new `die` lines in `review.sh record --plan`, each says to run the review again | pass |
| Tests are bash and prove themselves | each new check seen failing with its behavior disabled (Q8) | pass |
| Pins and versions agree in one place | pins move only in `pins.sh` (+ project copy), with checksums; the age rule now lives in the checker too | pass |
| Docs are the product's source of truth | `docs/reference.md` (task summary, plan review fields), release notes for the upgrade refusal and the title change | pass |
| One task = one issue = one PR | three tasks, one per issue, independent | pass |

Post-design re-check: no violation.

## Project Structure

### Documentation (this feature)

```text
specs/005-resolve-open-issues/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/changes.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
extension/scripts/lib.sh            # task_summary (#185)
extension/commands/issues.md        # rule (#185)
skills/implement/SKILL.md           # rule (#185)
bin/check-tools.sh                  # settled releases only (#184)
extension/scripts/review.sh         # state --plan; record --plan checks Plan state (#186)
extension/commands/review.md        # plan review: take the state first, report it (#186)
.specify/extensions/landspec/…      # project copies of the above, kept identical
tests/{issues,branch,next,check-tools,review}.test.sh
docs/reference.md, docs/releases/<next>.md
```

**Structure Decision**: edits in place; no new file except tests' additions.

## Complexity Tracking

No violations.

## Notes

- T003 (the checker) closes #184. The bump itself is not a task here: it cannot be done before
  2026-11-26 (trivy 0.76.2, semgrep 1.184.0) or 2026-11-30 (osv-scanner 2.7.1), and nothing in
  `next.sh` can hold a task until a date. The fixed checker opens a new issue when a release is
  settled; the bump then goes in as a small fix (constitution: no spec needed).
- Invariant for the plan review (data-model "Plan state"): the reviewer hashes and reads one
  snapshot of `plan.md` and `tasks.md`, copied into its own copy; it never runs git in, or writes
  to, the author's checkout. Rounds 1 and 2 of the plan review each found a case of breaking it.
- Changing a linked task's dependency keeps the plan gate on: plan review, record, then
  `issues.sh --sync` (contracts/changes.md).
- `fix/review-findings` (the review fixes from the PDF) is a separate branch and PR; it touches
  `secrets.sh`, `prepush.sh`, `guard.sh`, `pr.sh`, none of the files above.
