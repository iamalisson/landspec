# Research: One issue and one pull request per feature

Each decision names what was chosen, why, and what else was weighed. Code references are to
`extension/scripts/` unless a path says otherwise.

## R1. When and how the feature branch is made

- **Decision**: a new `after_specify` hook runs `branch.sh <feature>` (no task id). It creates
  `<branch_prefix>/<NNN>-<short-name>` (the spec folder's name, e.g. `feat/008-one-pr-per-feature`)
  from the base branch, carries the new spec folder onto it (the save, switch and restore that
  `pr.sh spec` does today, `pr.sh:184-199`), commits it and pushes it. On a later run it only
  switches to that branch (local, or tracking origin's). `before_implement` keeps calling
  `branch.sh`, now with the feature only.
- **Rationale**: the spec says the spec folder lives on the feature branch from the start, and the
  base receives the feature only through its PR. landspec already has the carry-the-folder logic
  and the base checks; spec-kit's own git extension is not installed in landspec projects.
- **Alternatives**: a `before_specify` hook (rejected: the folder and its short name do not exist
  yet); creating the branch at the tasks step (rejected: spec and plan would sit uncommitted on the
  base checkout for a whole phase).

## R2. Where one task is built before it lands

- **Decision**: each task is built on a local task ref `landspec/<NNN>-<tnnn>-task` that starts from the
  feature branch's head, in the implementer's own worktree. The ref is never pushed. The task's
  parent is recorded with the existing `branch.<ref>.landspec-parent = <feature branch>` setting, so
  `base_ref` (`lib.sh:146-157`), `review.sh record --branch` and `record --delta` review exactly the
  task's change against the feature head, unchanged. The main session lands a task only when its
  tests are green and its review is `ready`: `git merge --no-ff` into the feature branch, with a
  generated message (R3), then push.
- **Rationale**: the feature branch then only ever holds green, reviewed tasks, so the PR can be
  opened or updated at any time without a red tree, and a failed task leaves the branch untouched
  (spec edge case). Reusing the stacking setting means no new review code: a task ref is a stack of
  one on the feature branch.
- **Alternatives**: committing straight onto the feature branch (rejected: a red or rejected task
  would sit on the branch the PR shows, and undoing it means rewriting a pushed branch); pushed
  task branches (rejected: they are what the developer wants gone, and worktrees share refs, so no
  push is needed).

## R3. What marks a task as done

- **Decision**: the landing merge commit. Its message is `<Tnnn>: <task summary>`, and it carries
  the trailers `Landspec-Task: <NNN>/<Tnnn>` (the feature's number, since task ids restart in every
  feature) and `Landspec-Review: ready <patch id>`; the same commit
  brings the task's tick (`- [X] Tnnn` in `tasks.md`, committed on the task ref by `land` just before
  the merge). A task is done when the feature branch holds
  such a commit; `next.sh`, `implement.sh status` and `pr.sh feature` read it with
  `git log --grep '^Landspec-Task: NNN/Tnnn$'` over the branch's whole history (the developer's
  answer at T002's round limit: every merge shape keeps the landing, and no other feature's matches).
- **Rationale**: it is on the branch, so every clone and a resumed run see it (FR-014), it needs no
  GitHub call (today's `closed_issues`, `lib.sh:374-387`, goes away), and the tick is what spec-kit's
  own implement does. A box ticked by hand without a landing commit is not done, and `pr.sh feature`
  says so.
- **Alternatives**: the local run records under `landspec-run/` alone (rejected: another clone or
  a new worktree cannot see them); ticking `[X]` alone (rejected: proves no review happened).

## R4. The review model is Opus, and only Opus

- **Decision**: `review_model()` (`lib.sh:68-73`) returns `opus` and the `review_model` config key
  is removed. `hooks/guard-review.sh:28-35` refuses any reviewer launch whose `model` is not `opus`;
  an empty `model` is allowed only when `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` names an Opus model. The
  reviewer prompt (`extension/commands/review.md:15-22`) says Opus. When Opus is not offered, the
  launch fails and the run stops with that review named (spec edge case); there is no fallback.
- **Rationale**: FR-005 asks for a refusal of other models, and the developer asked for Opus. The
  guard already checks the model; only its allowed list changes.
- **Alternatives**: keep `review_model` with an `opus` default (rejected: FR-005 says other models
  are refused, which a config key would undo).

## R5. One issue per feature

- **Decision**: `issues.sh` creates one issue, titled `[NNN] <the spec's H1 title>`, with a short
  body (the spec's path, the branch) and one checklist line per task (`- [ ] T001 <summary>`, ticked
  for each landed task). Its number is written once at the top of `tasks.md` as
  `**Issue**: #N`, which makes reruns update the same issue (FR-002); an open issue with the exact
  title is reused if the line is missing (today's dedup, `issues.sh:36-40`). `issues.sh --sync`
  (run by the implement loop after each landing) rewrites the body from `tasks.md`. The feature PR
  carries `Closes #N`. The `issue_labels` default becomes `type:feature`; `milestone` and `project`
  stay (`add_meta`, `lib.sh:335-352`).
- **Rationale**: one place to see progress, closed by the one merge.
- **Alternatives**: keep the number in a git config or a run file (rejected: other clones cannot
  read it); one sub-issue per task (rejected: it is the per-task issue under another name).

## R6. The plan review stays, and gates the build instead of a spec PR

- **Decision**: `review.sh check --plan` keeps its rules. `issues.sh` still requires a current
  `ready` plan review (the issue body is the task list), and `implement.sh status` refuses to
  start a task without one. Gap tasks added by the end check get a plan review of the new lines
  before they are built, as today.
- **Rationale**: the plan review found real defects in features 006 and 007 before any code; with
  no spec PR, it is the only review of the plan before the build.
- **Alternatives**: dropping it for speed (rejected: the developer asked for a review during the
  build, not for fewer reviews; it costs no merge).

## R7. Tasks run one at a time

- **Decision**: `implement.sh status` lists at most one task to build: the first task in `ORDER`
  that is not done, not failed, and whose `depends on` tasks are done. `parallel_tasks`, `restack`,
  `stack`, `move`, the claim push and `next.sh`'s `parallel` lines are removed.
- **Rationale**: one branch, one tree; parallel builders would each need their own branch and a
  merge between them, which is the overhead being removed. The spec's assumption.
- **Alternatives**: parallel task refs merged in order (rejected: brings back conflicts, restacks
  and their tests for a speed-up the developer did not ask for).

## R8. The end check runs on the feature branch itself

- **Decision**: `implement.sh check` replaces `check-copy`: when every task is done it first updates
  the branch from the base (a conflict stops with its files), points `refs/landspec/check/<feature>`
  at the feature head (no merge copy), counts the attempt against `feature_rounds` (default 3) and
  refuses an unchanged head that already failed. The main session runs the test command on that
  head (in a detached worktree of it), records the result, then runs the Opus feature review
  (`review.sh` feature mode, base `origin/<base>`) and records it. Not-met items become tasks
  appended to `tasks.md` on the feature branch, plan-reviewed, synced to the feature issue, and built
  in the same run.
- **Rationale**: the existing feature review mode already reports met, not met and not verifiable
  per FR, scenario and SC (`review.sh:315-340`); only the merge copy and the spec PR around it go.
- **Alternatives**: a fresh check worktree with a merge of task branches (rejected: there is one
  branch to check).

## R9. The feature PR

- **Decision**: `pr.sh feature "<title>" <body-file>` replaces `pr.sh task` and `pr.sh spec`. On the
  feature branch it runs today's gates on the whole diff from the base (green tests,
  `## Test changes`, mutants, `security-scan.sh --changed`, `tfplan.sh gate`), refuses a ticked task
  with no landing commit, appends a generated task table (each task: done, failed or pending, its
  landing commit and review assessment) and `Closes #N`, and opens the PR as a draft or updates it.
  `pr.sh feature --ready` also requires a recorded `ready` feature review for the current head and
  every task done, then runs `gh pr ready`. `pr.sh fix` and `pr.sh state` stay as they are.
  The draft does not read `review.sh report` (a branch-wide review record): each landed commit
  already carries its task's ready review, and the independent review of the whole diff is the
  Opus feature review of the end check, which `--ready` requires and whose result the body carries
  in `## End check`. `review.sh check --feature` is added for that. Before each `pr.sh feature`,
  the loop runs `security-scan.sh --changed` and the mutation testing on the feature branch when
  this diff has no record of them (the implementers ran them on task diffs only).
- **Rationale**: `pr.sh fix` already holds every gate without an issue (`pr.sh:79-82`); the feature
  mode adds the task table, the issue and the draft-to-ready step.
- **Alternatives**: opening the PR only once everything passed (rejected: FR-010 wants the draft
  visible while work is pending).

## R10. Release

- **Decision**: `release-plan` lists merged PRs whose head is a feature branch
  (`<branch_prefix>/<NNN>-`; the task key `/<NNN>-t` goes) and requires the feature issue closed;
  `stats.sh` groups by feature PR. Version bump, tag, publish and the audit are unchanged.
- **Rationale**: FR-013; only the PR list's key changes.

## R11. Features started under the per-task flow

- **Decision**: a `tasks.md` with any line ending in ` — #N` is a per-task feature. `next.sh`,
  `implement.sh` and `branch.sh` print `LEGACY=<feature>` and stop with one message: finish its open
  task PRs as ordinary PRs, then delete the ` — #N` suffix (and close the issue) of each remaining
  task to continue it under the new flow. No per-task issue or PR is ever created for it.
  `next.sh` with no argument leaves legacy features out of its scan (finished per-task features,
  such as this repository's 001-007, are never offered or stopped on); named explicitly, it prints
  `LEGACY=`. `release-plan` keeps today's path for a legacy feature (its task issues all closed,
  read with `closed_issues`), so a feature finished under the old flow still releases.
- **Rationale**: FR-015 with no migration code; a project mid-feature at upgrade is rare and the
  manual step is short.
- **Alternatives**: an automatic migration command (rejected: YAGNI; it would have to close issues
  and PRs on the developer's behalf).

## R12. This feature's own build

- **Decision**: 008 is planned with today's landspec, so its tasks step would create per-task
  issues and a spec PR. Its build should instead run on one branch, as a single PR, which also
  exercises the new flow's shape before the scripts exist.
- **How** (chosen by the developer on 2026-11-18): the plan review runs as today; then no per-task
  issues and no spec PR. One issue is created by hand for 008, and the spec folder is committed on
  `feat/008-one-pr-per-feature`. Tasks are built one at a time, and 008 uses each of its own new
  scripts as soon as an earlier 008 task has added it (the developer's answer to the plan review;
  `land` and `check` are never removed):
  1. Every task: the implementer works in its copy on `git switch -c landspec/008-<tnnn>-task
     feat/008-one-pr-per-feature`, then `git config branch.landspec/008-<tnnn>-task.landspec-parent
     feat/008-one-pr-per-feature` (never `branch.sh`, never `pr.sh task`); tests; an Opus review
     recorded with `review.sh record --branch landspec/008-<tnnn>-task` (`--delta` for fix rounds).
  2. Every task that lands before `land` exists (T001, T007, T002 in the build order): the tick committed on the task ref, then on the feature
     branch a `--no-ff` merge of the ref with the landing message and trailers of data-model
     "Landing commit", a push, and the ref deleted.
  3. From T003 on: `implement.sh 008 mark <tnnn> ready <report>`, then `implement.sh 008 land
     <tnnn>`.
  4. The end: from T009 on, `implement.sh 008 check`, `tests/run.sh` on its head, `check-result`,
     an Opus feature review (`record --feature`); then an Opus review of the whole diff against
     `origin/main` recorded with `review.sh record`, and one PR through `pr.sh fix` (every gate, no
     issue) with `Closes #<the issue>`.
- **Rationale**: the new scripts do not exist until 008 is built; the developer wants one PR.
