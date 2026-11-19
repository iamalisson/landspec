---
name: next
description: "Show a spec-kit feature's progress (a task is done when its landing commit is on the feature branch) and offer /landspec:implement for the whole feature; with several features, asks which. Use when the user asks what's next or how far a feature is."
argument-hint: "[feature]"
---

# Next task

1. Run `bash .specify/extensions/landspec/scripts/next.sh [feature]`, with the argument when the user
   named a feature (`002` or `002-reports`); it becomes the active feature. With no argument on
   a task ref or the feature branch, it serves that branch's feature.
   - If `.specify/extensions/landspec/` does not exist, tell the user to run `/landspec:init`
     first, and stop.
   - If it prints `LEGACY=<feature>`, that feature was started under the per-task flow: show the
     message under it as is (finish its open task PRs as ordinary PRs, then delete the ` — #N`
     suffix of each remaining task to continue it), and stop.
   - If it stops with `cannot look up the feature's pull request`, show gh's error above it and stop.
   - If it prints `CHOOSE=...`, more than one feature has tasks to build: show the `feature` lines
     with their counts, ask which one, and run it again with that feature.
2. Show the progress as a short list (done / failed / pending / waiting), then the `BRANCH=`,
   `ISSUE=` and `PR=` it printed, and `DONE=x/y`.
   - **done**: its landing commit is on the feature branch (local, else origin's).
   - **failed**: its tests stayed red or its review still asked for changes after the fix rounds;
     `/landspec:implement <FEATURE>` names why, and `implement.sh <FEATURE> retry <task>` lifts it.
   - **waiting**: its line says "depends on Txxx" and that task has not landed yet.
   - **pending**: can be built now; `NEXT` is the first one.
   - If `ISSUE=-`, the feature has no issue yet: suggest `/speckit-landspec-issues` first.
3. Suggest `/landspec:implement <FEATURE>`, with the printed `FEATURE=`: it builds every ready task
   at once, each in its own copy, through its tests and an Opus review, and lands
   each one. When `NEXT` is empty and `DONE=y/y`, it checks the whole feature against the spec
   (gaps become new tasks), audits it and makes the release, then opens or updates the feature's
   one PR (each step once; a confirmed critical or high holds it and names `/landspec:security
   <report>`). Then `/speckit-specify` for the next feature. Make sure the working tree is clean
   first; if it isn't, say so; never stash or discard.
