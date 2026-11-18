# Contracts: scripts and hooks

What each changed entry point takes, prints and refuses. Unchanged entry points (`pr.sh fix`,
`pr.sh state`, `security-scan.sh`, `mutants.sh`, `tfplan.sh`, the audit and release-bump actions)
keep their contracts.

## branch.sh

```
branch.sh [feature]
```

- Resolves the feature (argument, else the active one). Refuses a task id
  (`branch.sh takes a feature, not a task: tasks are built on the feature branch`).
- Branch: `<branch_prefix>/<NNN>-<short-name>`. Exists locally: switch. On origin: switch tracking
  it. Neither: create from `origin/<base>` (else the local base; else die as today), carrying the
  spec folder's current content (uncommitted files included), commit it as
  `docs(specs): add <feature> spec` when it changed, push with `-u`.
- Refuses uncommitted changes outside the spec folder before switching (today's message).
- Writes `.specify/feature.json`. Prints `BRANCH=<name> FEATURE=<NNN> BASE=<base>`.
- Refuses a legacy feature (R11) with its message.

## issues.sh

```
issues.sh [--sync]
```

- Refuses without a current `ready` plan review (unchanged).
- Refuses unless on the feature's branch (`run it on <branch>: branch.sh <feature>`).
- No `**Issue**: #N` line in `tasks.md`: reuse an open issue with the exact title, else create one;
  write the line under the H1 and commit `tasks.md` and the rest of the spec folder
  (`docs(specs): <feature> plan and tasks, issue #N`), then push. Prints `ISSUE=#N (created|existing)`.
- With the line: `--sync`, or a task list that differs from the body, rewrites the body (checklist
  from `tasks.md`, `[x]` for each task with a landing commit). Prints `ISSUE=#N (updated|unchanged)`.
- Never creates more than one issue per feature. Logs `event issues` as today.

## next.sh

```
next.sh [feature]
```

- One line per task: `done|failed|pending|waiting Tnnn <summary>`.
- Then `FEATURE=<NNN> BRANCH=<branch> ISSUE=#N PR=<url|->`, then `DONE=x/y NEXT=<Tnnn|>`.
  `NEXT` empty and `DONE=y/y`: the end check or the PR is what is left.
- Reads `tasks.md` and the landing commits from the feature branch (local if present, else
  origin's). No GitHub issue reads, no claim, no `parallel` or `RUN=` lines.
- Legacy feature named explicitly: prints `LEGACY=<feature>` and the R11 message, exit 1. With no
  argument, legacy features are left out of the scan (never in `CHOOSE=`, never a stop).
- `CHOOSE=` with several features is unchanged.

## implement.sh

```
implement.sh <feature> status [--running <task>]
implement.sh <feature> mark <task> implemented|red|ready <report>|changes <report>
implement.sh <feature> land <task>
implement.sh <feature> fail <task> "<reason>" | retry <task>
implement.sh <feature> check | check-result green|red
implement.sh <feature> release-plan | release-bump X.Y.Z | audit-plan | audit-record <sha> <file> <n>
```

- `status`: refuses without a current `ready` plan review, a legacy feature (R11), or (level
  `full`) a missing analyzed marker. Prints one `TASK=<id> STATE=<state of data-model> [ROUND=n]`
  line per task, then at most one of `START=<id> REF=<task ref> FROM=<feature head> [RESUME=yes]`,
  `REVIEW=<id>`, `FIX=<id>`, `LAND=<id>`, then `CHECK=yes|no`, `PR=<url|->`, `ORDER=…`,
  `DONE=x/y`. A task in `--running` is never listed again.
- `mark` and `fail`: as today, on the run records; the task ref's per-task key shape lets them find it unchanged. `changes` at the fix-round limit (`task_rounds`, default
  3) marks the task failed and prints `FAILED=<id>`.
- `retry`: lifts `failed` and deletes the task ref, so the task starts fresh from the feature head.
- `land`: refuses unless the task is `ready` and its recorded review matches the task ref's head,
  and refuses uncommitted changes to the feature folder in the checkout (commit them first).
  Commits the tick in `tasks.md` on the task ref, merges it `--no-ff` into the feature branch with
  the landing message (data-model), pushes the branch, deletes the task ref and its settings.
  Prints `LANDED=<id> COMMIT=<sha>`. A merge conflict (the developer pushed a conflicting commit)
  aborts the merge and dies with the files.
- `check`: when every task is done, first updates the branch from the base (a conflict dies with
  the files), then prints `CHECK=<head> ROUND=<n>`, or `UNCHANGED=<n>` (this head's tests or
  review already failed) / `ROUNDS_EXHAUSTED=<n>` (more `heads:` than `feature_rounds`). It writes
  the end-check record (data-model "End check"); `check-result` sets its `tests:` for that head.
- Removed: `restack`, `stack`, `move`, `check-copy`, and `parallel_tasks`.
- `release-plan`: PRs keyed by the feature branch; requires the feature issue closed (a legacy
  feature: its task issues closed, as today).

## pr.sh

```
pr.sh feature "<title>" <body-file> [--ready]
pr.sh fix "<title>" <body-file>      (unchanged)
pr.sh state <pr> [--reply …]         (unchanged)
```

- `feature`: the shared `task|fix` arm with mode `feature`, on the feature branch only. Runs today's gates on the diff from `origin/<base>`:
  clean tree, `## Evidence` on `full`, `## Test changes` when existing tests
  changed, mutants, `security-scan.sh --changed` for this diff, `tfplan.sh gate`, the test command.
  Refuses a task ticked `[X]` without a landing commit. Does not read a branch-wide `review.sh
  report` (each landed commit carries its task review). Appends a generated `## Tasks` table (id,
  summary, state, landing commit, review assessment), `## End check` from the latest feature record
  (assessment, met / not met lines, test result, the head it checked and whether the branch moved since), and `Closes #N`. Opens a
  draft PR (`open_pr` drafts on mode `feature`; without drafts it warns not to merge before `--ready` and opens a normal PR) or replaces the open one's body.
- `--ready`: also refuses unless every task is done and `review.sh check --feature` passes (a
  `ready` feature review for the current head); then marks the PR ready (`gh pr ready`). Prints
  `PR=<url> READY=yes|no`.
- Removed: `task`, `spec`.

## review.sh

- `review_model` is `opus`; the config key is gone. `plan_text` also drops the `**Issue**: #N` line
  and reads `- [X]`/`- [x]` task ticks as `- [ ]`, so landing a task or writing the issue number
  never makes the plan review stale. New: `check --feature` and `report --feature` (the feature
  record for the head of `refs/landspec/check/<feature>`). Other records are unchanged; a task ref is reviewed
  with `record --branch <ref>` and `record --delta --branch <ref>`, its base taken from
  `landspec-parent` (the feature branch).
- Feature mode: `record --feature` adds `verdict:`, `reviewed: <the check ref it reviewed>` and the
  lines to the end-check record (data-model "End check") and deletes nothing; the facts give
  `base: origin/<base>` and the branch head. `check --feature` passes only when `reviewed`,
  `head` and the branch head are the same commit, the verdict is `ready` and the tests are green.

## hooks/guard-review.sh

- Refuses a reviewer launch (`landspec:reviewer`, or the reviewer sentinel line) whose `model` is not
  `opus`: `landspec: reviews run on Opus only (model: opus)`. An empty model passes only when
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` names an Opus model. Fork and isolation rules unchanged.

## extension.yml hooks

| Hook | Command | Change |
|---|---|---|
| `after_specify` | `speckit.landspec.branch` | new: create the feature branch |
| `after_tasks` | `speckit.landspec.issues` | now: plan review, commit the spec folder, the one feature issue |
| `after_converge` | `speckit.landspec.issues` | unchanged hook, same new behaviour |
| `before_implement` | `speckit.landspec.branch` | switches to the feature branch (no task) |
| `after_analyze` | `speckit.landspec.analyzed` | unchanged |
