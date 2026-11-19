# Quickstart: validating one PR per feature

## Local (CI)

Prerequisites: the repository, bash 3.2 or 5, git, the fake `gh` and throwaway repo of
`tests/helpers.sh`.

| # | Run | Expect |
|---|---|---|
| L1 | `tests/run.sh` | all pass on both CI jobs |
| L2 | `tests/branch.test.sh` | `branch.sh <feature>` creates `<prefix>/<NNN>-<name>` from the base, carries the uncommitted spec folder, commits and pushes it; a rerun switches; a task id is refused; a legacy feature is refused |
| L3 | `tests/review.test.sh` | the plan gate passes with medium and low findings and fails on a high; the task gate fails on a high or medium and passes on lows only; a delta of any size is accepted; no `answer --plan`, no `SIMPLIFY=` |
| L4 | `tests/next.test.sh` | done comes from landing commits; `waiting` for unmet dependencies; no `ISSUE=` and no `gh issue` call; legacy feature prints `LEGACY=` |
| L5 | `tests/implement.test.sh` | `status` prints a `START=` for every startable task up to `parallel_tasks`; `mark implemented` needs the test record of the ref's tree; `land` refuses a blocked or changed ref, ticks and merges a ready one with the trailers and `Low:` lines; a conflicting landing prints `CONFLICT=` and gives one round, a second fails the task; the fix-round limit (2) fails a task and blocks its dependants only; `check` on the branch head, rounds counted; `release-plan` keyed on the feature PR |
| L6 | `tests/pr.test.sh` | `pr.sh feature` runs the gates on the whole diff, refuses a tick without a landing commit, opens a draft with the task table and `## Low findings`, no `Closes #`, and needs no scan record; `--ready` refuses without a ready feature review, without the scan record, and on `findings high`; `task` and `spec` are gone |
| L7 | `tests/guard-review.test.sh` | a reviewer on `sonnet` or `fable` is refused; `opus` passes |
| L8 | `tests/static.test.sh` | docs, help, levels and the constitution template describe one PR per feature and no issues, and no shipped file names `pr.sh task`, `pr.sh spec`, `issues.sh`, stacked PRs or one issue per task |
| L9 | `tests/security-scan.test.sh`, `tests/pr.test.sh` (`run_tests` cases) | a high finding is recorded as `findings high`; a tree tested green in one worktree is not run again from another |

Each new check is run once with its rule disabled and seen to fail (constitution).

## End to end (a throwaway GitHub repository)

| # | Steps | Expect |
|---|---|---|
| Q1 | `/landspec:init`, then `/speckit-specify` a three-task feature | one branch `feat/001-…` on origin holding the spec folder; the base unchanged |
| Q2 | `/speckit-plan`, `/speckit-tasks` | one plan review pass recorded; the spec folder committed on the branch; no issue |
| Q3 | `/landspec:implement` (T002 and T003 independent of each other, both after T001) | T001 alone, then T002 and T003 built at the same time; three landing commits on the branch, each ticked and with `Landspec-Review: ready`; one Opus review per task; the end check green; one PR, ready for review, with the task table; no other branch on origin, no other PR, no issue |
| Q4 | Plant a defect in task 2's completion criteria, rerun on a fresh feature | task 2's review has a high or medium finding, one fix round follows on its task ref and is reviewed as a delta, then it lands; task 3 is not held by it |
| Q5 | Leave one FR unbuilt on purpose | the end check reports it `not met`, a new task is appended on the branch, gets one plan pass and is built, the check passes on the next round |
| Q6 | Merge the PR, run `/landspec:implement` | the release plan lists that one PR |
