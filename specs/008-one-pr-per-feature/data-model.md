# Data model: One issue and one pull request per feature

landspec keeps no database: state lives in git (branches, commits, `tasks.md`), in GitHub (one
issue, one PR) and in local run records under `$(git rev-parse --git-common-dir)`.

## Feature

| Field | Where | Notes |
|---|---|---|
| folder | `specs/<NNN>-<short-name>/` | spec, plan, research, data model, contracts, quickstart, tasks |
| branch | `<branch_prefix>/<NNN>-<short-name>` | created by `branch.sh <feature>` (after_specify); holds the folder and all code |
| issue | `**Issue**: #N` line at the top of `tasks.md` | one per feature; created or updated by `issues.sh` |
| PR | the open PR whose head is the branch | one per feature; draft until ready |

Rules: one branch, one issue, one PR per feature, whatever the number of tasks (SC-001). A feature
whose `tasks.md` has a line ending in ` — #N` is a per-task (legacy) feature: no new-flow action runs
on it (R11).

## Task

A line of `tasks.md`: `- [ ] Tnnn [P?] [USn?] <summary> in <files> (depends on Tnnn, …)` and its
sub-bullets (`Comes from`, `What`, `Impact`, `Completed when`). No ` — #N` suffix.

| State | Means | Read from |
|---|---|---|
| pending | not built, its dependencies done | `tasks.md`, no landing commit |
| waiting | a dependency is not done | `depends on` + landing commits |
| building | an implementer is in flight on its task ref | the main session's in-flight list |
| built | its tests are green on the task ref | run record `landspec-run/<feature>/<task>` (`phase=implemented`) |
| in review / changes | its Opus review is running / asked for changes | run record (`phase=ready` or `changes`, round count) |
| done | its landing commit is on the feature branch | `git log --grep '^Landspec-Task: Tnnn$' <branch>` |
| failed | tests red twice, or review still `changes needed` after the fix rounds | run record (`failed=<reason>`); `implement.sh retry` lifts it |

Transitions: pending → building → built → in review → (changes → building → built → in review)* →
done; built or in review → failed. waiting → pending when its last dependency is done. Only done
is shared with other clones; the rest is local and rebuilt from scratch when lost (a task with no
landing commit is simply built again from the feature head).

## Task ref

`refs/heads/landspec/<NNN>-<tnnn>-task`, local only, never pushed. Starts at the feature branch head when
the task starts; `branch.<ref>.landspec-parent` = the feature branch, so `base_ref` and the review
records diff it against the feature head. Deleted after landing. When a task starts again with its
ref present (an interrupted run, a lost run record), the implementer resumes on it (`git switch
<ref>`, `RESUME=yes` on the `START` line); `status` runs `git worktree prune` first, and a ref still
checked out in a locked worktree makes the task `waiting` with `REASON=locked worktree <path>`.
After a failure the ref is kept for the developer to read; `implement.sh retry` deletes it, so the
retried task starts fresh from the feature head.

## Landing commit

A `--no-ff` merge of the task ref into the feature branch, made by the main session only.

```
Tnnn: <task summary>

Landspec-Task: Tnnn
Landspec-Review: ready <patch id of the reviewed diff>
```

Before the merge, `land` commits the tick (`- [X] Tnnn` in `tasks.md`) on the task ref, so the merge
brings the code and the tick together. The merge commit's presence on the branch is what "done"
means (R3); a tick without it is not done. The plan review's state ignores ticks and the
`**Issue**:` line (`review.sh` `plan_text`), so neither makes the plan review stale.

## Task review

The Opus review of the task ref's diff against the feature head: a full `review.sh record --branch
<task ref>`, then `record --delta` for each fix round (a full record when the delta refuses). Its
`ready` patch id goes into the landing commit's trailer.

## End check

One record per feature, `landspec-review/feature-<feature>`, never deleted (the developer's
answer to the plan review, 2026-11-18); `implement.sh check`, `check-result` and `review.sh record
--feature` each write their fields, and `pr.sh feature` and `review.sh check --feature` read only it.

| Field | Written by | Notes |
|---|---|---|
| head | `check` | the feature branch commit checked (also `refs/landspec/check/<feature>`) |
| heads | `check` | every head checked so far; the round is their count, at most `feature_rounds` (default 3); a new head starts a new round, nothing is reset |
| tests | `check` (`pending`), `check-result` (`green` / `red`) | the test command on that head |
| verdict, lines, reviewed | `review.sh record --feature` | Opus, feature mode, base `origin/<base>`: the assessment, one `met` / `not met` / `not verifiable` line per FR, scenario and SC, and `reviewed:` the head it reviewed. A verdict counts only for `reviewed`: a new head has no verdict until it is reviewed (no stale `ready` passes, no stale `changes needed` blocks) |

Each `not met` line becomes a new task appended to `tasks.md` on the branch (`Comes from:` the
line). The check passes when the tests are green and the review has no `not met` line.

## Feature issue

| Field | Value |
|---|---|
| title | `[NNN] <spec.md H1 title>` |
| body | the spec path and branch, then `- [ ] Tnnn <summary>` per task, `[x]` once done |
| labels / milestone / project | `issue_labels` (default `type:feature`), `milestone`, `project` |
| closed by | the feature PR's `Closes #N` on merge |

## Feature PR

| Field | Value |
|---|---|
| head / base | the feature branch / the base branch |
| state | draft until every task is done and the end check passed (`pr.sh feature --ready`) |
| body | the developer's summary, `## Evidence`, a generated `## Tasks` table (each task's state, landing commit and review assessment), `## End check` from the latest feature record (its assessment, its met / not met lines, the test result and the head it checked, noting when the branch has moved since), `Closes #N` |
| review gate | a draft needs no branch-wide review record: every landed commit carries its task's ready review (`land` refuses otherwise). one record decides the PR: `--ready` needs the latest Opus feature review to be `ready` for the current head, and every task done; that review of the whole diff is the PR's independent review |
