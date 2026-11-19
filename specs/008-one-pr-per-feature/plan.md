# Implementation Plan: One pull request per feature

**Branch**: `008-one-pr-per-feature` | **Date**: 2026-11-18 (revised the same day) | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-one-pr-per-feature/spec.md`

## Summary

Replace landspec's one issue, branch and PR per task with one branch and one PR per feature, and no
GitHub issue at all. The feature branch is made when the spec is written and holds the spec folder
and all the code. After the tasks step, one Opus plan review runs; only a high finding stops the
build. `/landspec:implement` starts every task whose dependencies are done at once (up to
`parallel_tasks`, default 4), each on a local task ref from the feature head in its own worktree;
each gets one Opus review (only high and medium findings block), at most one fix round checked by a
delta review, and lands on the feature branch, in any order, with a merge commit that marks it done
and carries its low findings. A landing conflict gives that task one round. A task still blocked is
failed and the run goes on with every independent task. When every task is done, the end check runs
the tests and an Opus feature review on the branch; not-met items become tasks of the same feature,
built in the same run. Tests run once per tree (`run_tests` records are reused); the security scan
and mutation testing run once on the feature diff right before the PR is marked ready. One draft PR
carries everything and turns ready when the end check passes. Secrets checks, the guard, the plan
gate for Terraform, the audit and the release stay. The per-task machinery (task issues, task
branches and PRs, stacking, restack, claims, spec PRs, gap spec PRs) and the issue step are
removed. Decisions: [research.md](research.md).

## Technical Context

**Language/Version**: bash 3.2 (macOS, BSD tools) and bash 5 (Linux, GNU tools); Markdown prompts

**Primary Dependencies**: git, GitHub CLI `gh`, GitHub Spec Kit `specify` v1.2.5; Claude Code 2.1.295+ (plugin hooks, subagents with `model` and `isolation: worktree`)

**Storage**: git (feature branch, landing commits, `tasks.md`), GitHub (one PR), local run records under `$(git rev-parse --git-common-dir)/landspec-run/`, `landspec-review/`, `landspec-test/`, `landspec-security/`, `landspec-mutants/`

**Testing**: `tests/run.sh`, one `tests/<script>.test.sh` per script through `tests/helpers.sh` (throwaway repo, local origin, fake `gh`); CI jobs `linux` and `bash32`

**Target Platform**: developer machines (macOS, Linux) running Claude Code; GitHub-hosted repositories

**Project Type**: CLI toolkit: Claude Code plugin + spec-kit extension and preset

**Performance Goals**: one human merge per feature (SC-002); independent tasks built at the same time (SC-006); each check run once (SC-007)

**Constraints**: bash 3.2 floor; never overwrite the user's files; scripts refuse, prompts explain; no secret or AI attribution in public places; the reviewer never sees the author's reasoning and runs in its own worktree

**Scale/Scope**: about 12 scripts and 10 prompt files change, one script and one command removed; 12 test files; README, design, reference, security docs, levels, preset templates, examples

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| bash 3.2 is the floor | no new bash features; trailers read with `git log --grep` | pass |
| One shared library | new helpers (`feature_branch`, `task_done`, `legacy_feature`, `tests_green`) go in `lib.sh`; `run_tests`' key, `add_meta`, `closed_issues` and `branch_feature`'s task key change there once | pass |
| Nothing of the user's is overwritten | `branch.sh` carries the spec folder as `pr.sh spec` does today and refuses other uncommitted changes; `land` aborts a conflict instead of resolving it (the task's own round resolves it on its ref); a developer commit on the branch is kept | pass |
| Scripts refuse, prompts explain | every new refusal is one `die` naming what to run; skills show it as is | pass |
| Tests are bash and prove themselves | each changed script's test file changes; each new rule ships with a check seen failing (FR-017) | pass |
| Pins and versions agree | no new pin; the removed keys (`review_model`, `issue_labels`, `milestone`, `project`) are reflected in `docs/reference.md` and `tests/static.test.sh` | pass |
| Docs are the source of truth | README, `docs/design.md`, `docs/reference.md`, `docs/security.md` and the help change in the same PR | pass |
| No AI attribution | unchanged | pass |
| Governance: amendments in their own PR | this repository's constitution states the per-task model in **Project** ("every task gets a GitHub issue, its own branch and its own pull request") and in the generated **Way of working** block | **justified below** |

Post-design re-check: the design adds no dependency and no new state store. Config: `task_rounds`
(fix rounds per task, default 2: one review and one delta; it replaces the `MAX_ROUNDS=3` constant)
is added; `parallel_tasks` (default 4) stays with a new meaning (builders at once on one branch);
`review_model`, `issue_labels`, `milestone` and `project` are removed. Still passes, with the one
justified item.

## Project Structure

### Documentation (this feature)

```text
specs/008-one-pr-per-feature/
├── plan.md              # this file
├── research.md          # decisions R1–R15 (R5 superseded)
├── data-model.md        # feature, plan review, task states, task ref, test record, landing commit, end check, PR
├── quickstart.md        # local checks and an end-to-end run
├── contracts/
│   └── scripts.md       # branch.sh, next.sh, implement.sh, pr.sh, review.sh, security-scan.sh, lib.sh, guard-review.sh, hooks
├── checklists/
│   └── requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
extension/
├── extension.yml                  # hooks: + after_specify; after_tasks/after_converge → plan-review; descriptions say one PR per feature
├── scripts/                       # copied to .specify/extensions/landspec/scripts/ (kept identical)
│   ├── lib.sh                     # feature_branch, task_done, legacy_feature, tests_green; run_tests keyed by tree; add_meta assign only; review_model=opus
│   ├── branch.sh                  # feature branch only (R1)
│   ├── issues.sh                  # removed (R5 superseded)
│   ├── next.sh                    # progress from landing commits (R3), no issue, claims or parallel lines
│   ├── implement.sh               # parallel status, mark/land (conflict round)/fail/retry/check/check-result; release-plan by feature PR (R7, R8, R10)
│   ├── pr.sh                      # feature [--ready]; scan and mutants at --ready; task and spec removed (R9, R15)
│   ├── review.sh                  # severity gates, no Simplify, no delta size limit; plan_text ignores ticks; check/report --feature (R6, R13)
│   ├── security-scan.sh           # `findings high` (R15)
│   ├── level.sh                   # no issue_labels
│   └── stats.sh                   # groups by feature PR
├── commands/                      # issues.md → plan-review.md; branch.md, pr.md, review.md rewritten for the new flow
├── levels/{lite,standard,full}.md # "Way of working": one branch, one PR per feature
└── scaffold/                      # PR template without a Closes line
hooks/guard-review.sh              # Opus only (R4)
agents/implementer.md              # builds one task on its task ref; tests through run_tests; no scan, no mutants, no push
agents/reviewer.md                 # unchanged rules
skills/implement/SKILL.md          # parallel loop: START all → build → review → fix → land as ready → … → end check → PR
skills/next/SKILL.md, skills/help/SKILL.md
preset/commands/speckit.implement.md  # points /speckit-implement at the same loop
preset/templates/{tasks,constitution}-template.md
README.md, docs/design.md, docs/reference.md, docs/security.md, docs/GUIDELINES.md, examples/
tests/{branch,next,implement,pr,review,guard-review,security-scan,static,stats,level}.test.sh; tests/issues.test.sh removed
```

**Structure Decision**: no new files outside the spec folder except `extension/commands/plan-review.md`,
which is `issues.md` renamed and cut down to its plan-review steps; every other change lands in the
existing script, prompt, doc and test of the area it changes, and each script's `.specify/` copy
stays identical (as `tests/static.test.sh` already checks).

## Design notes

1. **Order of work** (each step keeps the suite green): add first, remove once (the developer's
   answer to the plan review): each new path is added beside the old one, and the removal tasks
   come at the end. Done so far: T001 (feature branch), T007 (Opus only), T002 (status, land).
   Built, to land: T003 (`pr.sh feature`), T006 (`next.sh`).
   1. In parallel: parallel `status` and the conflict round (T017), the review gates (T018), the
      scan severity (T021), the release (T010).
   2. The issue removal (T005), Simplify removal (T019), tests once (T020).
   3. The implement skill and agent (T004); then the end check (T008) and the ready gate with the
      scan and mutants once (T009).
   4. The removal of the per-task modes, in three tasks (pr.sh, branch.sh, implement.sh); the gate
      tests keep running through `pr.sh fix`, the same shared arm, never deleted.
   5. Levels, templates, scaffolds, docs, help and examples (FR-016), then one negative check over
      everything that ships, with one allow-list.
2. **The loop** (`skills/implement/SKILL.md`): `status` → every `START` launches one implementer in
   the background, in its own worktree, on its task ref (`git switch -c landspec/<NNN>-<tnnn>-task
   <feature head>`, setting `landspec-parent`); the implementer commits and runs the tests through
   `run_tests` → `mark implemented` (needs that record) → `REVIEW`: one Opus reviewer, facts
   `commit:` the ref's head, `branch:` the ref, `base:` the feature branch → `record --branch` →
   `mark ready|changes` (high or medium: changes) → `FIX`: one round through SendMessage, always
   `record --delta` → `LAND` as soon as ready (one at a time) → `CONFLICT=`: one round in which the
   implementer merges the feature branch into its ref and resolves, then a delta and `land` again →
   `status` again for the newly startable tasks. A failed task is reported and the run goes on. A
   draft `pr.sh feature` opens after the first landing and is updated at the end of each run. When
   every task is done: `check` → tests (`run_tests`) → Opus feature review → gaps (and red tests) as
   tasks with one plan pass, committed and pushed, and back to the loop; or
   `security-scan.sh --changed` and `mutants.sh` on the feature diff, then `pr.sh feature --ready`.
3. **Removed** (with their tests and docs): `issues.sh` and the issues command, `pr.sh task|spec`,
   `implement.sh restack|stack|move|check-copy`, `branch.sh`'s task mode and claim push, `next.sh`'s
   claims and `parallel`/`RUN=` lines, `review.sh answer --plan` and the Simplify areas, the delta
   size limit, `review_model`, `issue_labels`, `milestone`, `project`, stacked drafts, the spec PR
   body, `Closes #N`, and the ` — #N` task suffix (read only to detect legacy features).
   `closed_issues` stays only for a legacy feature's release (R11).
4. **Changed in review.sh**: `plan_text` ignores ticks and the `**Issue**:` line; `check --plan`
   passes without a high finding; `check --branch` blocks on high or medium; `check --feature` and
   `report --feature` are added; the check-copy wording becomes the check ref.
5. **Kept unchanged** (apart from header comments that name `pr.sh task`): `pr.sh fix|state`,
   `tfplan.sh`, the guard (only its PR message changes), the secrets and pre-push hooks, the audit,
   release-bump, tag and publish. `mutants.sh` is unchanged; it is called once per feature.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| The constitution's **Project** paragraph and the generated **Way of working** block (its branch and review bullets: "a task through `pr.sh task`", a review recorded for the exact diff before any PR) describe one issue, branch and PR per task | the product changes; leaving them would make the constitution contradict every doc and script | Way of working is generated from `extension/levels/*.md`, so it changes with this feature and `/landspec:level` regenerates it. The **Project** paragraph is amended through `/speckit-constitution` in its own PR, as Governance requires, merged before this feature's PR |
