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
4. Do not tick the task's checkbox in `tasks.md`. The task is done when its issue closes.
