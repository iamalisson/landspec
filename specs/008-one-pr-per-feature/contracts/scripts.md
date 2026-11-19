# Contracts: scripts and hooks

What each changed entry point takes, prints and refuses. Unchanged entry points (`pr.sh fix`,
`pr.sh state`, `tfplan.sh`, the audit and release-bump actions) keep their contracts.

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

## issues.sh (removed)

Superseded 2026-11-18 by the developer: no issues. `issues.sh`, `extension/commands/issues.md` and
`tests/issues.test.sh` are removed (T005); the plan review they ran moves to the plan-review command.

## next.sh

```
next.sh [feature]
```

- One line per task: `done|failed|pending|waiting Tnnn <summary>`.
- Then `FEATURE=<NNN> BRANCH=<branch> PR=<url|->`, then `DONE=x/y NEXT=<Tnnn|>`. `NEXT` empty and `DONE=y/y`: the end check or the PR is what is left.
- Reads `tasks.md` and the landing commits from the feature branch (local if present, else
  origin's). No GitHub issue reads, no `ISSUE=`, no claim, no `parallel` or `RUN=` lines.
- Legacy feature named explicitly: prints `LEGACY=<feature>` and the R11 message, exit 1. With no
  argument, legacy features are left out of the scan (never in `CHOOSE=`, never a stop).
- `CHOOSE=` with several features is unchanged.

## implement.sh

```
implement.sh <feature> status [--running <task>]…
implement.sh <feature> mark <task> implemented|red|ready <report>|changes <report>
implement.sh <feature> land <task>
implement.sh <feature> fail <task> "<reason>" | retry <task>
implement.sh <feature> check | check-result green|red
implement.sh <feature> release-plan | release-bump X.Y.Z | audit-plan | audit-record <sha> <file> <n>
```

- `status`: refuses without a passing `review.sh check --plan`, a legacy feature (R11), or (level
  `full`) a missing analyzed marker. Prints one `TASK=<id> STATE=<state of data-model> [ROUND=n]`
  line per task, then one `START=<id> REF=<task ref> FROM=<feature head> [RESUME=yes]` line for
  every task whose dependencies are done and which is not done, failed or in `--running`, while
  fewer than `cfg parallel_tasks 4` tasks are in flight; one `REVIEW=<id>`, `FIX=<id> [REASON=conflict]`
  or `LAND=<id>` line for every task in that state and not in `--running`; then `CHECK=yes|no`,
  `PR=<url|->`, `ORDER=…`, `DONE=x/y`.
- `mark implemented`: refuses unless `run_tests` recorded a green run for the task ref's head tree
  (the builder's run; tests are not run again).
- `mark changes`: at the fix-round limit (`task_rounds`, default 2: the first review and one delta)
  marks the task failed and prints `FAILED=<id>`. `mark` and `fail` otherwise as today, on the run
  records.
- `retry`: lifts `failed` and deletes the task ref, so the task starts fresh from the feature head.
- `land`: refuses unless the task is `ready` and `review.sh check --branch <ref>` passes for the
  ref's head (no high or medium finding), and refuses uncommitted changes to the feature folder.
  Commits the tick in `tasks.md` on the task ref, merges it `--no-ff` into the feature branch with
  the landing message (data-model, with the review's `Low:` lines), pushes the branch, deletes the
  task ref and its settings. Prints `LANDED=<id> COMMIT=<sha>`. A merge conflict aborts the merge,
  prints `CONFLICT=<id> FILES=<files>`, sets the task to `changes` with `conflict=1` (its one
  conflict round, outside `task_rounds`) and exits non-zero; a second conflict marks it failed and
  prints `FAILED=<id>`.
- `check`: when every task is done, first updates the branch from the base (a conflict dies with
  the files), then prints `CHECK=<head> ROUND=<n>`, or `UNCHANGED=<n>` (this head's tests or
  review already failed) / `ROUNDS_EXHAUSTED=<n>` (more `heads:` than `feature_rounds`). It writes
  the end-check record (data-model "End check"); `check-result` sets its `tests:` for that head.
- Removed: `restack`, `stack`, `move`, `check-copy`, the task-branch `status`.
- `release-plan`: PRs keyed by the feature branch; no issue read (a legacy feature: its task issues
  closed, as today).

## pr.sh

```
pr.sh feature "<title>" <body-file> [--ready]
pr.sh fix "<title>" <body-file>      (unchanged)
pr.sh state <pr> [--reply …]         (unchanged)
```

- `feature`: the shared `task|fix` arm with mode `feature`, on the feature branch only. Runs on the
  diff from `origin/<base>`: clean tree, `## Evidence` on `full`, `## Test changes` when existing
  tests changed, `tfplan.sh gate`, the test command through `run_tests` (a tree already green is not
  run again). Refuses a task ticked `[X]` without a landing commit. Does not read a branch-wide
  `review.sh report` (each landed commit carries its task review). Appends a generated `## Tasks`
  table (id, summary, state, landing commit, review assessment), `## Low findings` (the `Low:` lines
  of the landing commits) and `## End check` from the latest feature record (assessment, met / not
  met lines, test result, the head it checked and whether the branch moved since). No `Closes #N`.
  Opens a draft PR (`open_pr` drafts on mode `feature`; without drafts it warns not to merge before
  `--ready` and opens a normal PR) or replaces the open one's body. The draft does not require the
  scan or the mutation record.
- `--ready`: also refuses unless every task is done, `review.sh check --feature` passes (a `ready`
  feature review for the current head), and `security-scan.sh --changed` and (with a mutate command)
  `mutants.sh` are recorded for this diff; refuses on a scan line `findings high`; lists other
  findings, missing scanners and an unavailable mutation tool; surviving mutants need their line in
  `## Evidence` (today's rule). Then marks the PR ready (`gh pr ready`). Prints
  `PR=<url> READY=yes|no`.
- Removed: `task`, `spec`.

## review.sh

- `review_model` is `opus`; the config key is gone. `plan_text` drops a `**Issue**: #N` line and
  reads `- [X]`/`- [x]` task ticks as `- [ ]`, so landing a task never makes the plan review stale.
- `check --plan`: passes when the plan record is current and has no high finding (was: assessment
  `ready`). `answer --plan`, the areas state and the `SIMPLIFY=` lines are removed.
- `check --branch`: passes when the branch record is current and has no high or medium finding.
- `record --delta`: the 20-line limit outside the earlier findings' files is removed; the other
  refusals stay (a round recorded on this branch, `<sha>` still on it, something committed since).
- New: `check --feature` and `report --feature` (the feature record for the head of
  `refs/landspec/check/<feature>`). A task ref is reviewed with `record --branch <ref>` and
  `record --delta --branch <ref>`, its base taken from `landspec-parent` (the feature branch).
- Feature mode: `record --feature` adds `verdict:`, `reviewed: <the check ref it reviewed>` and the
  lines to the end-check record (data-model "End check") and deletes nothing; the facts give
  `base: origin/<base>` and the branch head. `check --feature` passes only when `reviewed`,
  `head` and the branch head are the same commit, the verdict is `ready` and the tests are green.

## security-scan.sh

- `--changed` on the feature branch scans the diff from `origin/<base>` (its base ref) and records it
  as this diff's record, as today. A scanner that reports a high or critical finding (gitleaks: any
  finding) prints `<tool> findings high <detail>`; other findings print `<tool> findings <detail>`.
  `missing` and `skipped` unchanged.

## lib.sh

- `run_tests`: the record's key is the tree and the command, not the copy's path; otherwise
  unchanged (green on a clean tree recorded, red records nothing).
- New `tests_green <tree>`: true when a green record exists for that tree and the test command (or
  there is no test command).
- `add_meta pr <url>`: assigns the user only; `milestone` and `project` are no longer read.

## hooks/guard-review.sh

- Refuses a reviewer launch (`landspec:reviewer`, or the reviewer sentinel line) whose `model` is not
  `opus`: `landspec: reviews run on Opus only (model: opus)`. An empty model passes only when
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` names an Opus model. Fork and isolation rules unchanged.

## extension.yml hooks

| Hook | Command | Change |
|---|---|---|
| `after_specify` | `speckit.landspec.branch` | new: create the feature branch |
| `after_tasks` | `speckit.landspec.plan-review` | now: ground the plan, one plan review pass, commit the spec folder on the feature branch; no issue |
| `after_converge` | `speckit.landspec.plan-review` | same, for the lines converge added |
| `before_implement` | `speckit.landspec.branch` | switches to the feature branch (no task) |
| `after_implement` | `speckit.landspec.pr` | the feature PR (`pr.sh feature`) |
| `after_analyze` | `speckit.landspec.analyzed` | unchanged |
