---
name: next
description: "Show a spec-kit feature's progress (a task is done when its issue is closed) and start the next open task with /speckit-implement, or, when two or more can start, offer /landspec:implement for the whole feature; with several features, asks which. Use when the user asks what's next or has just merged a task PR."
argument-hint: "[feature]"
---

# Next task

1. Run `bash .specify/extensions/landspec/scripts/next.sh [feature]`, with the argument when the user
   named a feature (`002` or `002-reports`); it becomes the active feature. With no argument on
   a task branch, it serves that branch's feature.
   - If it stops with `cannot read the state of feature …`, show gh's error above it (it names the
     issue number) and stop: the task line links an issue that is missing or not an issue.
   - If it stops with `cannot fetch origin`, `cannot read origin's branches` or `cannot list the
     open pull requests`, show the error above it and stop: without them a claimed task looks free.
   - If `.specify/extensions/landspec/` does not exist, tell the user to run `/landspec:init`
     first, and stop.
   - If it prints `CHOOSE=...`, more than one feature has tasks to start: show the `feature` lines
     with their counts, ask which one, and run it again with that feature.
2. Show the progress as a short list (done / resume / in-progress / blocked / open / no-issue),
   then `DONE=x/y`.
   - **blocked** tasks say "depends on Txxx" on their line and that task's issue is still open;
     they are never picked before it closes (merge that PR first).
   - **resume** is a task whose branch you started in this clone; it is picked first.
   - **in-progress** tasks are being done elsewhere (a branch on origin, another worktree, an
     open PR) and are never picked; they finish when their PR merges.
   - **parallel**: an open `[P]` task that can start now in its own worktree, beside NEXT. A task
     of an unmerged spec PR has no such line, and starting it refuses until that PR merges.
   - If tasks have **no issue**, say so, run `bash .specify/extensions/landspec/scripts/next.sh <FEATURE>` first
     (`issues.sh` takes no feature, so this makes it the active one), and suggest `/speckit-landspec-issues`.
   - If `NEXT` is empty and `IN_PROGRESS` is not 0, nothing is left to start: list the open PRs
     to merge, and stop.
   - If `NEXT` is empty and `IN_PROGRESS=0`, every task's issue is closed. Suggest
     `/landspec:implement <FEATURE>`: it checks the whole feature on the base against the spec (gaps
     become new tasks), audits the base and makes the release (each step once; a confirmed critical or
     high holds it and names `/landspec:security <report>`). Then `/speckit-specify` for the next
     feature. Stop.
3. Make sure the working tree is clean. If it isn't, stop and say so; never stash or discard.
   - If it printed `RUN=/landspec:implement <feature>`, two or more tasks can start: ask once "Run
     the whole feature with `/landspec:implement <feature>` (every startable task in parallel, each
     through review and PR)?" On yes, run that command, and stop here. On no, go on with step 4.
4. If it printed `parallel` lines, those `[P]` tasks can start now beside NEXT. Ask once: "Also
   start <ids> in their own worktrees?" On yes, run each line exactly as printed, one at a time,
   never two at once: each makes a worktree beside the repository (`<repo>-<feature>-<task>`) and
   claims its task on origin before the next one runs. If a line fails (a leftover folder, a
   parent folder that is not writable, scripts not committed on the base branch), show its message
   as is and skip that task. A line that exits 3 (`… was claimed elsewhere`) lost the race to
   another clone: remove the worktree it made (`git worktree remove <path after --detach>`) and say
   "started elsewhere, skipped". A refused claim (`landspec: warning: could not claim …`) only warns: the
   task started, but other clones may start it too; say so. Then list, per started task: open a
   Claude Code session in the path after `--detach` and run `/speckit-implement <feature> <id>`
   (install dependencies there first: a new worktree has no git-ignored files).
5. Run `/speckit-implement <FEATURE> <NEXT>`, with the printed `FEATURE=`, so a named feature beats
   the current task branch. It switches to the task's branch, implements it, runs the
   pre-PR checks and opens the PR.
