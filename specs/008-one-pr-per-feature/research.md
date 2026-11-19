# Research: One pull request per feature

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
  tests are green and its review has no high or medium finding (R13): `git merge --no-ff` into the feature branch, with a
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
  GitHub call (today's `closed_issues`, `lib.sh:374-387`, stays only for a legacy feature's
  release), and the tick is what spec-kit's own implement does. A box ticked by hand without a landing commit is not done, and `pr.sh feature`
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

## R5. One issue per feature (superseded)

- **Superseded 2026-11-18 by the developer**: no GitHub issue at all, not even one per feature.
  The PR's `## Tasks` table and `next.sh` are the progress view. `issues.sh`,
  `extension/commands/issues.md` and the `issue_labels`, `milestone` and `project` config keys are
  removed (T005); `add_meta` keeps only the assignee for the PR. Was: one issue per feature with a
  task checklist, its number in `**Issue**: #N`, closed by the PR's `Closes #N`.

## R6. The plan review: one pass, gating the build

- **Decision**: after the tasks step and after converge, the `after_tasks`/`after_converge` hooks run
  one plan review: the grounding steps of today's issues command, then one Opus review of spec, plan
  and tasks, recorded with `review.sh record --plan`, then the spec folder committed and pushed on
  the feature branch. `review.sh check --plan` passes when the recorded review is current and has no
  high finding; medium and low findings are shown to the developer and never force a second round.
  The `## Simplify:` sections, `review.sh answer --plan` and the areas state are removed.
  `implement.sh status` refuses to start a task while `check --plan` fails. Gap tasks added by the
  end check get the same single pass on their new lines.
- **Superseded 2026-11-18 by the developer**: was "the plan review keeps its rules" (rounds until
  `ready`, Simplify questions after repeated areas).
- **Rationale**: the plan review found real defects in features 006 and 007 before any code; the
  defects that mattered were high. Rounds over medium and low findings cost time without changing
  the build.
- **Alternatives**: dropping it (rejected: with no spec PR it is the only review of the plan).

## R7. Tasks run in parallel by default

- **Decision**: `implement.sh status` prints one `START=<id> REF=landspec/<NNN>-<tnnn>-task
  FROM=<feature head>` line for every task whose `depends on` tasks are done and which is not done,
  failed or in flight (`--running`), up to `cfg parallel_tasks 4` builders at once (the key stays; it
  no longer means stacked PRs). It also prints a `REVIEW=`, `FIX=` or `LAND=` line for every task in
  that state. Each task starts from the feature head in its own worktree. The main session lands
  each task as it becomes ready, in any order, one `land` at a time. When a landing conflicts
  (another task landed first and touched the same lines), `land` aborts the merge and prints
  `CONFLICT=<id> FILES=…`; the task gets one conflict round: its implementer merges the feature
  branch into its ref, resolves, runs the tests, and a delta review checks the round before it
  lands. A second conflict marks it failed. The conflict round does not count against
  `task_rounds`. `restack`, `stack`, `move`, the claim push and `next.sh`'s `parallel` lines are
  removed.
- **Superseded 2026-11-18 by the developer**: was "tasks run one at a time".
- **Rationale**: independent tasks are most of a feature; building them at once is the speed-up
  left once the merge loop is gone. Landing on one branch needs no PR stacking: a conflict is rare
  and costs one round.
- **Alternatives**: one at a time (rejected by the developer); stacked task refs (rejected: brings
  back restacks).

## R8. The end check runs on the feature branch itself

- **Decision**: `implement.sh check` replaces `check-copy`: when every task is done it first updates
  the branch from the base (a conflict stops with its files), points `refs/landspec/check/<feature>`
  at the feature head (no merge copy), counts the attempt against `feature_rounds` (default 3) and
  refuses an unchanged head that already failed. The main session runs the test command on that
  head (in a detached worktree of it), records the result, then runs the Opus feature review
  (`review.sh` feature mode, base `origin/<base>`) and records it. Not-met items (and red tests, as one
  task) become tasks appended to `tasks.md` on the feature branch, given one plan review pass (R6),
  committed and pushed, and built in the same run. The test run goes through `run_tests` (R14), so a
  head already tested green is not run again.
- **Rationale**: the existing feature review mode already reports met, not met and not verifiable
  per FR, scenario and SC (`review.sh:315-340`); only the merge copy and the spec PR around it go.
- **Alternatives**: a fresh check worktree with a merge of task branches (rejected: there is one
  branch to check).

## R9. The feature PR

- **Decision**: `pr.sh feature "<title>" <body-file>` replaces `pr.sh task` and `pr.sh spec`. On the
  feature branch it runs the shared gates on the whole diff from the base (green tests through
  `run_tests`, `## Test changes`, `tfplan.sh gate`), refuses a ticked task with no landing commit,
  appends a generated `## Tasks` table (each task: done, failed or pending, its landing commit and
  review assessment), `## Low findings` (from the landing commits, R13) and `## End check`, and opens
  the PR as a draft or updates it. No `Closes #N`: there is no issue (superseded 2026-11-18).
  `pr.sh feature --ready` also requires every task done, `review.sh check --feature` (a `ready`
  feature review for the current head), and the security scan and mutation testing of the feature
  diff (R15); then it runs `gh pr ready`. `pr.sh fix` and `pr.sh state` stay as they are.
  The draft does not read `review.sh report` (a branch-wide review record): each landed commit
  already carries its task's review, and the independent review of the whole diff is the Opus
  feature review of the end check, which `--ready` requires and whose result the body carries.
- **Rationale**: `pr.sh fix` already holds every gate without an issue (`pr.sh:79-82`); the feature
  mode adds the task table and the draft-to-ready step.
- **Alternatives**: opening the PR only once everything passed (rejected: FR-010 wants the draft
  visible while work is pending).

## R10. Release

- **Decision**: `release-plan` lists merged PRs whose head is a feature branch
  (`<branch_prefix>/<NNN>-`; the task key `/<NNN>-t` goes); no issue is read (superseded
  2026-11-18: was "requires the feature issue closed");
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
  issues and no spec PR. Issue #263 was created by hand for 008 before the issues were dropped; it
  stays a plain issue, closed by hand (or by a `Closes #263` the developer writes in the PR body).
  The spec folder is committed on `feat/008-one-pr-per-feature`. Tasks are built in parallel waves
  (tasks.md "Build order"), and 008 uses each of its own new
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
  4. From T017 on, `implement.sh 008 status` names every task of the next wave; from T004 on, the
     implement skill drives the loop.
  5. The end: `implement.sh 008 check`, `tests/run.sh` on its head, `check-result`, an Opus feature
     review (`record --feature`), then `pr.sh feature --ready` (from T009 on; before it, one PR
     through `pr.sh fix`, every gate, after an Opus review of the whole diff against `origin/main`).
- **Rationale**: the new scripts do not exist until 008 is built; the developer wants one PR.

## R13. Review gates by severity

- **Decision** (the developer, 2026-11-18): the plan review blocks only on a high finding (R6). The
  task review blocks landing only on a high or medium finding: `review.sh check --branch` passes on
  a current record with neither, and the reviewer's `Assessment:` follows the same rule
  (`extension/commands/review.md`: plan `changes needed` only with a high; task only with a high or
  medium). One full review, then at most one fix round (`task_rounds` default 2), always checked by
  a delta: the rule that a fix of more than 20 lines outside the earlier findings' files needs a
  full review is removed (the other delta refusals stay). A delta of a conflict round reads the
  merge's resolution (`git show --remerge-diff`) and the commits after it, not the other tasks'
  code the merge brought in. Low findings do not block: `land` copies them into the landing
  commit's message (`Low: <file>:<line> <text>` lines above the trailers), and `pr.sh feature`
  lists them under `## Low findings`. Still blocked after the fix round: the task is failed, the run
  goes on with every independent task, and the end report lists it.
- **Rationale**: the rounds that mattered in 006 and 007 were over high and medium findings; low
  ones are worth reading, not worth a round. A delta of a fix stays small however many lines the
  fix touches, because it reads only the fix.
- **Alternatives**: keep full-review fallback for large fixes (rejected by the developer); store
  lows only in the local review records (rejected: another clone could not list them in the PR).

## R14. Tests run once per tree

- **Decision**: every test run goes through `run_tests` (`lib.sh`), which records a green run on a
  clean tree. Its key becomes the tree and the command only (today it also holds the copy's path,
  so a tree tested in the builder's worktree ran again in the main checkout). The builder runs the
  tests through it; `implement.sh mark <task> implemented` refuses unless a green record exists for
  the task ref's head tree; `pr.sh feature` and the end check call `run_tests` and reuse the record.
- **Rationale**: the same tree gave the same result three times per task (builder, main session,
  PR). A landing merge with nothing landed in between has the task ref's tree, so even the
  feature head is often already tested.
- **Risk**: ignored files (dependencies, `.env`) can differ between copies; the key already ignored
  them within one copy. The end check's full run on the feature head stays the final word.

## R15. Security scan and mutation testing once per feature

- **Decision**: the secret hook stays on every commit and push. `security-scan.sh --changed` and
  `mutants.sh` run once, on the whole feature diff from `origin/<base>`, right before
  `pr.sh feature --ready`; the implementers no longer run them per task, and the draft PR does not
  require them (they are slow, and the draft is opened after the first landing, when most of the
  diff is still to come). `security-scan.sh` records each scanner's line as `findings high` when the
  tool reports a high or critical finding (gitleaks: every finding), else `findings`. `--ready`
  refuses on a `findings high` line; other findings, a missing scanner and an unavailable mutation
  tool are listed in the body, never blocking. Surviving mutants still need their line in
  `## Evidence`, as today.
- **Rationale**: the scan of the feature diff covers every task's lines once; per-task scans
  repeated the same scanners over overlapping diffs.
- **Alternatives**: scan the first draft too (rejected: not cheap, and the result is stale by the
  ready step).

