# Implementation Plan: One issue and one pull request per feature

**Branch**: `008-one-pr-per-feature` | **Date**: 2026-11-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-one-pr-per-feature/spec.md`

## Summary

Replace landspec's one issue, branch and PR per task with one issue, one branch and one PR per
feature. The feature branch is made when the spec is written and holds the spec folder and all the
code. `/landspec:implement` builds the tasks one at a time, each on a local task ref from the
feature head, reviews each with a fresh Opus reviewer (fix rounds as today), and lands it on the
feature branch with a merge commit that marks it done. When every task is done, the end check runs
the tests and an Opus feature review on the branch; not-met items become tasks of the same feature,
built in the same run. One draft PR carries everything and turns ready when the end check passes.
Existing gates (tests, scan, plan gate, mutants, secrets, guard), the audit and the release stay.
The per-task machinery (task issues, task branches and PRs, stacking, restack, claims, spec PRs,
gap spec PRs) is removed. Decisions: [research.md](research.md).

## Technical Context

**Language/Version**: bash 3.2 (macOS, BSD tools) and bash 5 (Linux, GNU tools); Markdown prompts

**Primary Dependencies**: git, GitHub CLI `gh`, GitHub Spec Kit `specify` v1.2.5; Claude Code 2.1.295+ (plugin hooks, subagents with `model` and `isolation: worktree`)

**Storage**: git (feature branch, landing commits, `tasks.md`), GitHub (one issue, one PR), local run records under `$(git rev-parse --git-common-dir)/landspec-run/` and `landspec-review/`

**Testing**: `tests/run.sh`, one `tests/<script>.test.sh` per script through `tests/helpers.sh` (throwaway repo, local origin, fake `gh`); CI jobs `linux` and `bash32`

**Target Platform**: developer machines (macOS, Linux) running Claude Code; GitHub-hosted repositories

**Project Type**: CLI toolkit: Claude Code plugin + spec-kit extension and preset

**Performance Goals**: one human merge per feature (SC-002); no added wait beyond the reviews themselves

**Constraints**: bash 3.2 floor; never overwrite the user's files; scripts refuse, prompts explain; no secret or AI attribution in public places; the reviewer never sees the author's reasoning and runs in its own worktree

**Scale/Scope**: about 10 scripts and 10 prompt files change; 10 test files; README, design, reference, security docs, levels, preset templates, examples

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| bash 3.2 is the floor | no new bash features; trailers read with `git log --grep` | pass |
| One shared library | new helpers (`feature_branch`, `task_done`, `feature_issue`, `legacy_feature`) go in `lib.sh`; `closed_issues`, `task_issue` and `branch_feature`'s task key change there once | pass |
| Nothing of the user's is overwritten | `branch.sh` carries the spec folder as `pr.sh spec` does today and refuses other uncommitted changes; `land` refuses a conflict instead of resolving it; a developer commit on the branch is kept | pass |
| Scripts refuse, prompts explain | every new refusal is one `die` naming what to run; skills show it as is | pass |
| Tests are bash and prove themselves | each changed script's test file changes; each new rule ships with a check seen failing (FR-017) | pass |
| Pins and versions agree | no new pin; the `review_model` removal is reflected in `docs/reference.md` and `tests/static.test.sh` | pass |
| Docs are the source of truth | README, `docs/design.md`, `docs/reference.md`, `docs/security.md` and the help change in the same PR | pass |
| No AI attribution | unchanged | pass |
| Governance: amendments in their own PR | this repository's constitution states the per-task model in **Project** ("every task gets a GitHub issue, its own branch and its own pull request") and in the generated **Way of working** block | **justified below** |

Post-design re-check: the design adds no dependency, no new state store and one config key,
`task_rounds` (fix rounds per task, default 3; it replaces the `MAX_ROUNDS=3` constant at `implement.sh:53`). It
removes `parallel_tasks` and `review_model`. Still passes, with the one justified item.

## Project Structure

### Documentation (this feature)

```text
specs/008-one-pr-per-feature/
├── plan.md              # this file
├── research.md          # decisions R1–R12
├── data-model.md        # feature, task states, task ref, landing commit, end check, issue, PR
├── quickstart.md        # local checks and an end-to-end run
├── contracts/
│   └── scripts.md       # branch.sh, issues.sh, next.sh, implement.sh, pr.sh, review.sh, guard-review.sh, hooks
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
extension/
├── extension.yml                  # hooks: + after_specify; descriptions say one PR per feature
├── scripts/                       # copied to .specify/extensions/landspec/scripts/ (kept identical)
│   ├── lib.sh                     # feature_branch, task_done, feature_issue, legacy_feature; review_model=opus
│   ├── branch.sh                  # feature branch only (R1)
│   ├── issues.sh                  # one feature issue, --sync ticks (R5)
│   ├── next.sh                    # progress from landing commits (R3), no claims or parallel lines
│   ├── implement.sh               # status/mark/land/fail/retry/check/check-result; release-plan by feature PR (R7, R8, R10)
│   ├── pr.sh                      # feature [--ready]; task and spec removed (R9)
│   ├── review.sh                  # review_model fixed; plan_text ignores ticks and the Issue line; check/report --feature
│   └── stats.sh                   # groups by feature PR
├── commands/                      # issues.md, branch.md, pr.md, review.md rewritten for the new flow
├── levels/{lite,standard,full}.md # "Way of working": one issue, one branch, one PR per feature
└── scaffold/                      # PR template without a per-task Closes line
hooks/guard-review.sh              # Opus only (R4)
agents/implementer.md              # builds one task on its task ref; no claim, no push
agents/reviewer.md                 # unchanged rules
skills/implement/SKILL.md          # sequential loop: build → test → Opus review → fix → land → … → end check → PR
skills/next/SKILL.md, skills/help/SKILL.md
preset/commands/speckit.implement.md  # points /speckit-implement at the same loop
preset/templates/{tasks,constitution}-template.md
README.md, docs/design.md, docs/reference.md, docs/security.md, docs/GUIDELINES.md, examples/
tests/{branch,issues,next,implement,pr,review,guard-review,static,stats,level}.test.sh
```

**Structure Decision**: no new files outside the spec folder; every change lands in the existing
script, prompt, doc and test of the area it changes, and each script's `.specify/` copy stays
identical (as `tests/static.test.sh` already checks).

## Design notes

1. **Order of work** (each step keeps the suite green):
   Add first, remove once (the developer's answer to the plan review): each new path is added
   beside the old one, and one task removes every per-task mode at the end.
   1. `branch.sh` feature mode and the `after_specify` hook (R1); Opus-only review (R4).
   2. `implement.sh` status and land (R3, R7); `pr.sh feature` (R9); the implement skill and agent.
   3. `issues.sh` feature issue (R5) and `next.sh` (R3, R11).
   4. The end check and the ready gate (R8, R9); release and stats keyed on the feature PR (R10).
   5. The removal of the per-task modes, in three tasks (pr.sh, branch.sh, implement.sh); the
      gate tests keep running through `pr.sh fix`, the same shared arm, never deleted.
   6. Levels, templates, scaffolds, docs, help and examples (FR-016), then one negative check over
      everything that ships, with one allow-list.
2. **The loop** (`skills/implement/SKILL.md`): `status` → `START` launches one implementer on the
   task ref (`git switch -c landspec/<NNN>-<tnnn>-task <feature head>` in its copy, setting
   `landspec-parent`) → tests in its copy → `mark implemented` → `REVIEW`: one Opus reviewer, facts
   `commit:` the ref's head, `branch:` the ref, `base:` the feature branch → record →
   `mark ready|changes` → `FIX` rounds through SendMessage or a new implementer → `LAND` →
   `issues.sh --sync` → the next task. At `DONE=y/y`: `check` → tests → Opus feature review → gaps
   as tasks (plan review of the new lines, `issues.sh --sync`) and back to the loop, or
   `pr.sh feature --ready`. A draft `pr.sh feature` opens after the first landing and is updated at
   the end of each run.
3. **Removed** (with their tests and docs): `pr.sh task|spec`, `implement.sh restack|stack|move|
   check-copy`, `branch.sh`'s task mode and claim push, `next.sh`'s claims and `parallel`/`RUN=`
   lines, `parallel_tasks`, `review_model`, stacked drafts, the spec PR body, and the ` — #N` task
   suffix (read only to detect legacy features). `closed_issues` stays only for a legacy feature's
   release (R11).
4. **Changed in review.sh**: `plan_text` ignores ticks and the `**Issue**:` line; `check --feature`
   and `report --feature` are added; the check-copy wording becomes the check ref.
5. **Kept unchanged** (apart from header comments that name `pr.sh task`): `pr.sh fix|state`,
   `security-scan.sh`, `mutants.sh`, `tfplan.sh`, the guard (only its PR message changes),
   the secrets and pre-push hooks, the task and delta review records, the audit,
   release-bump, tag and publish.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| The constitution's **Project** paragraph and the generated **Way of working** block (its branch and review bullets: "a task through `pr.sh task`", a review recorded for the exact diff before any PR) describe one issue, branch and PR per task | the product changes; leaving them would make the constitution contradict every doc and script | Way of working is generated from `extension/levels/*.md`, so it changes with this feature and `/landspec:level` regenerates it. The **Project** paragraph is amended through `/speckit-constitution` in its own PR, as Governance requires, merged before this feature's PR |
