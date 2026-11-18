# Quickstart: validating one PR per feature

## Local (CI)

Prerequisites: the repository, bash 3.2 or 5, git, the fake `gh` and throwaway repo of
`tests/helpers.sh`.

| # | Run | Expect |
|---|---|---|
| L1 | `tests/run.sh` | all pass on both CI jobs |
| L2 | `tests/branch.test.sh` | `branch.sh <feature>` creates `<prefix>/<NNN>-<name>` from the base, carries the uncommitted spec folder, commits and pushes it; a rerun switches; a task id is refused; a legacy feature is refused |
| L3 | `tests/issues.test.sh` | one issue per feature with one checklist line per task; a rerun updates it; `--sync` ticks landed tasks; refused off the feature branch and without a ready plan review |
| L4 | `tests/next.test.sh` | done comes from landing commits, not issues; `waiting` for unmet dependencies; legacy feature prints `LEGACY=` |
| L5 | `tests/implement.test.sh` | `status` lists at most one task; `land` refuses an unreviewed or changed ref, ticks and merges a ready one with the trailers; the fix-round limit fails a task and blocks its dependants only; `check` on the branch head, rounds counted; `release-plan` keyed on the feature PR |
| L6 | `tests/pr.test.sh` | `pr.sh feature` runs every gate on the whole diff, refuses a tick without a landing commit, opens a draft with the task table and `Closes #N`; `--ready` refuses without a ready feature review; `task` and `spec` are gone |
| L7 | `tests/guard-review.test.sh` | a reviewer on `sonnet` or `fable` is refused; `opus` passes |
| L8 | `tests/static.test.sh` | docs, help, levels and the constitution template describe one issue and one PR per feature, and no doc names `pr.sh task`, `pr.sh spec`, stacked PRs or one issue per task |

Each new check is run once with its rule disabled and seen to fail (constitution).

## End to end (a throwaway GitHub repository)

| # | Steps | Expect |
|---|---|---|
| Q1 | `/landspec:init`, then `/speckit-specify` a three-task feature | one branch `feat/001-…` on origin holding the spec folder; the base unchanged |
| Q2 | `/speckit-plan`, `/speckit-tasks` | a ready plan review; exactly one issue `[001] …` with three checklist lines; `tasks.md` has `**Issue**: #N` |
| Q3 | `/landspec:implement` | three landing commits on the branch, each ticked and with `Landspec-Review: ready`; an Opus review per task; the end check green and ready; one PR, ready for review, with the task table and `Closes #N`; no other branch on origin and no other PR or issue |
| Q4 | Plant a defect in task 2's completion criteria, rerun on a fresh feature | task 2's review asks for changes, a fix round follows on its task ref, then it lands; task 3 starts only after |
| Q5 | Leave one FR unbuilt on purpose | the end check reports it `not met`, a new task is appended on the branch and built, the issue gets its line, the check passes on the next round |
| Q6 | Merge the PR, run `/landspec:implement` | the issue closes; the release plan lists that one PR |
