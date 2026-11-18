---
name: speckit-landspec-branch
description: Switch to the task's branch before implementing
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: iamalisson
  source: landspec:commands/branch.md
---

# Task branch (before `/speckit-implement`)

One task = one issue = one branch = one PR. This puts the session on the task's branch before
any code is touched.

**After `/speckit-specify`** (the `after_specify` hook), it makes the feature's branch instead, and
the steps below do not apply:

- Run `bash .specify/extensions/landspec/scripts/branch.sh` with no task ID (the new feature is the
  active one). It makes `<branch_prefix>/<NNN>-<short-name>` from the base branch, commits the spec
  folder on it and pushes it; on a later run it only switches to it.
- On `LEGACY=<feature>`, or any other failure, show the script's message as is and stop. Never work
  around it: no stash, no reset, no checkout of other files.
- On success, print `On <BRANCH> for feature <FEATURE>`; the plan and tasks are written on that branch.

1. Find the task ID: the single `T###` in the arguments passed to `/speckit-implement`.
   - If there is none, or more than one: **stop the whole implement run**. Tell the user to pass
     exactly one task, e.g. `/speckit-implement T003`. Do not implement anything.
   - A feature number or folder in the arguments (`002`, `002-reports`) names the feature; without
     it, the active one is used. `/speckit-implement 002 T001` is T001 of feature 002.
2. Run `bash .specify/extensions/landspec/scripts/branch.sh [<FEATURE>] <TASK_ID>`. It also pushes a
   new branch to origin at once, so the task shows as in progress to every clone and worktree.
   - On failure, stop the implement run and show the script's message as is. It explains what is
     missing: the issue, the spec PR, the analysis, or a clean working tree. Never work around
     it: no stash, no reset, no checkout of other files.
3. On success, print `On <BRANCH> for <TASK> (#<ISSUE>)` and continue `/speckit-implement`
   with **only that task**. Before writing code, follow the "Installed skills and MCP servers" section
   of `.specify/extensions/landspec/commands/review.md`, and put its `Skills:` line in the PR's
   *Evidence*. Follow the constitution's defaults while implementing.
   - When the branch already has an open PR (a run again: `gh pr list --head <BRANCH> --state open
     --json number -q '.[0].number'`), run `bash .specify/extensions/landspec/scripts/pr.sh state <pr>`
     first. On `COPILOT=comments <n> REPORT=<file>` with n > 0, the report's `thread=` lines are a fix
     round: verify each comment as a review finding (try to disprove it), fix the real ones, and keep
     one answer per thread, `fixed in <sha>` or `not a defect: <reason>`; then run
     `/speckit-landspec-pr` from step 2 (a full review, never a delta); then, for each thread, write
     its answer to a `mktemp` file and run `pr.sh state <pr> --reply <thread id> <file>`. Each
     `RESOLVE=` thread (already answered), whatever n: `pr.sh state <pr> --reply <thread id>` with no
     file. Otherwise follow `pr.md` step 7's hand-over: `pr.sh state <pr>`, and the PR is ready to merge only on
     `CONFLICT=no` and `COPILOT=` `none`, `clean` or `unavailable`, else its reason; the CI state ("CI
     passed", "CI still running", "CI failed: <jobs>") is shown beside it, never waited for.
4. Do not tick the task's checkbox in `tasks.md`. The task is done when its issue closes.
