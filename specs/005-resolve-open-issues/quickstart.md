# Quickstart: validating the fixes

All local; CI runs the same (`linux` and `bash32` jobs).

| # | Run | Expect |
|---|---|---|
| Q1 | `tests/run.sh` | all pass |
| Q2 | `source extension/scripts/lib.sh; task_summary "<each line of data-model.md's table>"` | the summaries in that table |
| Q3 | `tests/issues.test.sh` | a linked task's dependency change: `--sync` refused until the plan review is recorded again, then updates the same issue, creates none; a create that failed before `— #N` was written, then a dependency change, then a rerun: `(existing)`, no duplicate |
| Q4 | `tests/branch.test.sh` | the same branch name before and after a task gains a dependency |
| Q5 | `tests/check-tools.test.sh` | a fake release list where the only newer release is 10 days old: `BEHIND=0`, no issue; 30 days old: `behind:` and one issue |
| Q6 | `tests/review.test.sh` | record a ready plan report with the current `Plan state:` → `REVIEW=ready`; edit a sub-bullet in `tasks.md`, record the same report → refused "the plan changed since this review"; only ` — #N` appended → still ready; no `Plan state:` line → refused; `review.sh state --plan` leaves no `.git/landspec-review` behind in a fresh clone |
| Q7 | `bin/check-tools.sh` against the real GitHub API (read-only), today | `BEHIND=` counts only releases at least 21 days old (compare with the dates in research R3) |
| Q8 | Each new check with its behavior disabled | it fails; the PR says so (constitution) |
