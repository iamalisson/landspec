# Data model: One pull request per feature

landspec keeps no database: state lives in git (branches, commits, `tasks.md`), in GitHub (one PR)
and in local run records under `$(git rev-parse --git-common-dir)`. No GitHub issue is part of the
model (superseded 2026-11-18 by the developer: the "Feature issue" entity is removed).

## Feature

| Field | Where | Notes |
|---|---|---|
| folder | `specs/<NNN>-<short-name>/` | spec, plan, research, data model, contracts, quickstart, tasks |
| branch | `<branch_prefix>/<NNN>-<short-name>` | created by `branch.sh <feature>` (after_specify); holds the folder and all code |
| PR | the open PR whose head is the branch | one per feature; draft until ready |

Rules: one branch and one PR per feature, whatever the number of tasks, and no issue (SC-001). A
feature whose `tasks.md` has a line ending in ` — #N` is a per-task (legacy) feature: no new-flow
action runs on it (R11).

## Plan review

One Opus review of spec, plan and tasks, recorded with `review.sh record --plan`. The plan gate
(`review.sh check --plan`) passes when the record is current (the plan text has not changed since)
and has no high finding; medium and low findings are shown to the developer. One pass: no Simplify
sections, no answers. The plan text ignores task ticks and a `**Issue**:` line (`plan_text`), so
landing a task never makes it stale.

## Task

A line of `tasks.md`: `- [ ] Tnnn [P?] [USn?] <summary> in <files> (depends on Tnnn, …)` and its
sub-bullets (`Comes from`, `What`, `Impact`, `Completed when`). No ` — #N` suffix.

| State | Means | Read from |
|---|---|---|
| pending | not built, its dependencies done | `tasks.md`, no landing commit |
| waiting | a dependency is not done | `depends on` + landing commits |
| building | an implementer is in flight on its task ref | the main session's in-flight list (`--running`) |
| built | its tests are green on the task ref | run record `landspec-run/<feature>/<task>` (`phase=implemented`, needs the test record of the ref's tree) |
| in review / changes | its Opus review is running / has a high or medium finding, or its landing conflicted | run record (`phase=ready` or `changes`, round count, `conflict=1`) |
| done | its landing commit is on the feature branch | `git log --grep '^Landspec-Task: NNN/Tnnn$' <branch>` |
| failed | tests red twice, still blocked after its one fix round, or a second landing conflict | run record (`failed=<reason>`); `implement.sh retry` lifts it |

Transitions: pending → building → built → in review → (changes → building → built → in review, at
most once) → done; a landing conflict → changes (one conflict round) → building → … → done; built
or in review → failed. waiting → pending when its last dependency is done. Every pending task starts
at once, up to `parallel_tasks` (default 4). Only done is shared with other clones; the rest is
local and rebuilt from scratch when lost (a task with no landing commit is simply built again from
the feature head).

## Task ref

`refs/heads/landspec/<NNN>-<tnnn>-task`, local only, never pushed. Starts at the feature branch head when
the task starts; `branch.<ref>.landspec-parent` = the feature branch, so `base_ref` and the review
records diff it against the feature head. Deleted after landing. When a task starts again with its
ref present (an interrupted run, a lost run record), the implementer resumes on it (`git switch
<ref>`, `RESUME=yes` on the `START` line); `status` runs `git worktree prune` first, and a ref still
checked out in a locked worktree makes the task `waiting` with `REASON=locked worktree <path>`.
After a failure the ref is kept for the developer to read; `implement.sh retry` deletes it, so the
retried task starts fresh from the feature head. In a conflict round the feature branch is merged
into the ref.

## Test record

`landspec-test/<key>`, written by `run_tests` (`lib.sh`) after a green run on a clean tree. The key
is the tree and the test command (not the copy's path), so a tree tested in the builder's worktree
counts in the main checkout. Every later step that needs that tree tested (`mark implemented`,
`pr.sh feature`, the end check) reuses it. Red records nothing.

## Landing commit

A `--no-ff` merge of the task ref into the feature branch, made by the main session only.

```
Tnnn: <task summary>

Low: <file>:<line> <finding title>        (one per low finding of the task review, if any)

Landspec-Task: NNN/Tnnn
Landspec-Review: ready <patch id of the reviewed diff>
```

The trailer names the feature (`NNN`, its number) as well as the task, because task ids restart at
T001 in every feature: a search of the branch's whole history then finds this feature's landings
however the branch was joined (a PR merge, a pull merge, a squash) and never another feature's.
`Landspec-Review: ready` means the review had no high or medium finding. The `Low:` lines carry the
low findings into git, so `pr.sh feature` lists them from any clone.

Before the merge, `land` commits the tick (`- [X] Tnnn` in `tasks.md`) on the task ref, so the merge
brings the code and the tick together. The merge commit's presence on the branch is what "done"
means (R3); a tick without it is not done.

## Task review

The Opus review of the task ref's diff against the feature head: one full `review.sh record
--branch <task ref>`, then at most one `record --delta` for the fix round (always a delta, whatever
the fix's size) and one for a conflict round. It blocks landing on a high or medium finding
(`review.sh check --branch`); its patch id goes into the landing commit's trailer and its low
findings into the `Low:` lines.

## End check

One record per feature, `landspec-review/feature-<feature>`, never deleted (the developer's
answer to the plan review, 2026-11-18); `implement.sh check`, `check-result` and `review.sh record
--feature` each write their fields, and `pr.sh feature` and `review.sh check --feature` read only it.

| Field | Written by | Notes |
|---|---|---|
| head | `check` | the feature branch commit checked (also `refs/landspec/check/<feature>`) |
| heads | `check` | every head checked so far; the round is their count, at most `feature_rounds` (default 3); a new head starts a new round, nothing is reset |
| tests | `check` (`pending`), `check-result` (`green` / `red`) | the test command on that head, through `run_tests` |
| verdict, lines, reviewed | `review.sh record --feature` | Opus, feature mode, base `origin/<base>`: the assessment, one `met` / `not met` / `not verifiable` line per FR, scenario and SC, and `reviewed:` the head it reviewed. A verdict counts only for `reviewed`: a new head has no verdict until it is reviewed (no stale `ready` passes, no stale `changes needed` blocks) |

Each `not met` line (and red tests, as one task) becomes a new task appended to `tasks.md` on the
branch (`Comes from:` the line), given one plan review pass, committed and pushed. The check passes
when the tests are green and the review has no `not met` line.

## Feature PR

| Field | Value |
|---|---|
| head / base | the feature branch / the base branch |
| state | draft until every task is done and the end check passed (`pr.sh feature --ready`) |
| body | the developer's summary, `## Evidence`, a generated `## Tasks` table (each task's state, landing commit and review assessment; the progress view), `## Low findings` from the landing commits, `## End check` from the latest feature record (its assessment, its met / not met lines, the test result and the head it checked, noting when the branch has moved since), and at `--ready` the scan and mutation results of the feature diff. No `Closes #N` |
| review gate | a draft needs no branch-wide review record: every landed commit carries its task's review (`land` refuses otherwise). One record decides the PR: `--ready` needs the latest Opus feature review to be `ready` for the current head, and every task done; that review of the whole diff is the PR's independent review |
| security gate | at `--ready` only: `security-scan.sh --changed` and `mutants.sh` recorded for the feature diff from `origin/<base>`; a `findings high` line refuses; other findings, missing scanners and an unavailable mutation tool are listed |
