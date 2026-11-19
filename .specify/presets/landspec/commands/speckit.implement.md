---
description: "Build the feature's tasks and land each on the feature branch (landspec: as /landspec:implement does)"
strategy: append
---

## landspec: the whole feature, as /landspec:implement does

This project uses landspec (one branch and one PR per feature). It **overrides** the instructions
above where they differ:

- Build the feature's tasks as `/landspec:implement` does: run it for this feature. It builds every
  startable task at once, each on its own task ref, reviews it, and lands it on the feature branch
  as soon as it is ready.
- **Do not mark tasks `[X]` in `tasks.md`.** `implement.sh land` ticks a task in its landing commit;
  never by hand (`pr.sh feature` refuses a ticked task with no landing commit).
- The completion check above ("all tasks completed") means: every task is landed (`DONE=` of
  `implement.sh status`), or reported failed by the run.
