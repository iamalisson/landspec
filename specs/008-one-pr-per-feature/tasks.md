---

description: "Tasks for feature 008: one pull request per feature"
---

# Tasks: One pull request per feature

**Input**: Design documents from `/specs/008-one-pr-per-feature/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/scripts.md, quickstart.md

**Revised 2026-11-18 by the developer**: no GitHub issues, tasks in parallel by default, one pass
for the plan review, one review plus one fix round per task, tests once per tree, the scan and
mutation testing once per feature. T001, T007 and T002 are landed; T003 and T006 are built and land
as they are (their text is corrected; T005 removes the issue code they carry). T005 is now the
removal of the issues; T004 and T008–T016 are rewritten; T017–T021 are new.

**Tests**: every task ships its own tests, in the same task as its code, from its *Completed when*
and the spec's scenarios. Each new check is run once with its rule disabled and seen to fail
(constitution, FR-017). After every task the whole suite passes (`tests/run.sh`) on bash 3.2 and
bash 5 (CI jobs `linux`, `bash32`, `macos`): a task fixes every test and static check its change
breaks, not only the ones it names.

**Add first, remove once** (the developer's answer to the plan review, 2026-11-18): the adding
tasks put the new paths beside the old ones and delete nothing another file still calls; T005
removes the issues, T011–T013 remove the per-task modes, one script each. Impact lists name files
and symbols, not line numbers.

**One negative check** (the developer's answer, 2026-11-18): the text tasks rewrite their text;
T016 adds the single static check, with one allow-list, that no shipped file names a per-task mode
or the issue step.

**Every script task** edits `extension/scripts/<script>` and its copy in
`.specify/extensions/landspec/scripts/` identically (`tests/static.test.sh` fails on drift).

**This feature's own build** (research R12): one branch, one PR, tasks in the parallel waves of
"Build order".

## Format: `[ID] [P?] [Story] Description`

- **[P]**: touches no file another task of its wave touches
- `(depends on Tnnn)`: needs that task landed first; a task with all its dependencies landed can
  start, alongside every other such task
- **[Story]**: the user story of spec.md (US1–US6)

---

## Phase 3: User Story 1 - A whole feature in one pull request (Priority: P1) 🎯 MVP

**Goal**: one feature branch made at specify time; tasks built in parallel on local task refs and
landed on the branch as each is ready; one draft PR per feature.

**Independent Test**: quickstart L2, L5, L6 and Q1, Q3.

- [X] T001 [US1] Make the feature branch when the spec is written, in extension/scripts/branch.sh
  - Comes from: FR-003, FR-015, US1 scenario 1, US6 scenario 1; research R1, R11; contracts/scripts.md "branch.sh"
  - What: `branch.sh <feature>` with no task id (the feature mode, beside today's task mode, which
    a later task removes): branch `<branch_prefix>/<NNN>-<short-name>` (the folder name); switch if local,
    track if on origin, else create from `origin/<base>` (else the local base, else today's die)
    carrying the spec folder's current content (the save, `git checkout`/`clean`, switch, restore
    and EXIT trap that `pr.sh spec` has, moved into a `lib.sh` helper both use), commit it as
    `docs(specs): add <feature> spec` when it changed, push with `-u`; refuse uncommitted changes
    outside the spec folder (today's message, excluding `.claude/worktrees`); refuse a legacy
    feature (any `tasks.md` line ending in ` — #N`) with `LEGACY=<feature>` and the R11 message;
    write `.specify/feature.json`; print `BRANCH=<name> FEATURE=<NNN> BASE=<base>`. New helpers in
    `extension/scripts/lib.sh`: `feature_branch <fdir>` and `legacy_feature <fdir>`;
    `branch_feature` (used by `feature_dir`) also reads `<prefix>/NNN-<name>`. Register
    `after_specify` → `speckit.landspec.branch` in `extension/extension.yml` (same shape as
    `before_implement`); `extension/commands/branch.md` runs the feature mode.
  - Impact: `tests/branch.test.sh` (new cases; task-mode cases stay); `pr.sh` (uses the
    moved carry helper); `docs/reference.md`; `.specify/extensions.yml` gets the hook when
    the extension is reinstalled.
  - Completed when: `bash tests/branch.test.sh` passes: a new feature with an uncommitted spec
    folder gets `feat/001-x` from the base with the folder committed and on origin, and the base
    unchanged; a rerun switches without a new commit; a branch only on origin is tracked; an
    uncommitted file outside the folder is refused before any switch; a legacy `tasks.md` prints
    `LEGACY=` and exits non-zero; `feature_dir` resolves both branch shapes; `bash tests/pr.test.sh`
    passes unchanged (the carry helper); `tests/run.sh` passes.

- [X] T002 [US1] Report task states from landing commits and land a reviewed task on the feature branch, in extension/scripts/implement.sh (depends on T001)
  - Comes from: FR-004, FR-006, FR-007, FR-014, FR-015, US1 scenarios 1-3, edge cases (red twice, run stopped midway, developer commit); research R2, R3, R7, R11; data-model "Task", "Task ref", "Landing commit"; contracts/scripts.md "implement.sh", "review.sh"
  - What: on a feature branch (`feature_branch` matches), `status` per contracts/scripts.md: refuse
    without `review.sh check --plan`, a legacy feature, or (level `full`) the analyzed marker; one
    `TASK=<id> STATE=pending|waiting|building|built|review|changes|done|failed [ROUND=n]` line per
    task, then at most one of `START=<id> REF=landspec/<NNN>-<tnnn>-task FROM=<feature head> [RESUME=yes]`,
    `REVIEW=`, `FIX=`, `LAND=` (T017 makes it one line per startable or ready task), then `CHECK=yes|no`, `PR=<url|->`, `ORDER=`, `DONE=x/y`; done from
    `task_done` (new in `lib.sh`: the feature branch's history holds a commit whose message has the
    line `Landspec-Task: <NNN>/<id>`, the feature's number and the task id, so another feature's
    landings never count and this feature's count in every merge shape); `waiting` while a `depends on` task is not done; `git worktree prune`
    first, `RESUME=yes` when the ref exists, `waiting REASON=locked worktree <path>` when it is
    checked out in a locked worktree. `changes` at `cfg task_rounds 3` fix rounds (T017 lowers the default to 2) (replacing the
    `MAX_ROUNDS` constant) marks the task failed and prints `FAILED=<id>` (dependants stay
    `waiting`, independent tasks go on). The task ref has today's per-task key shape (`landspec/<NNN>-<tnnn>-task`, the developer's
    answer to the plan review), so `mark`, `fail`, `task_branch` and `branch_feature` find it unchanged. `retry` also deletes the task
    ref. New `land <task>`:
    refuse unless the task is `ready` and `review.sh check --branch <ref>` passes for the ref's head,
    and refuse uncommitted changes to the feature folder; commit `- [X] <id>` in `tasks.md` on the
    ref; merge it `--no-ff` into the feature branch with message `<id>: <summary>` and trailers
    `Landspec-Task: <NNN>/<id>` and `Landspec-Review: ready <patch id>`; push; delete the ref and its
    `branch.<ref>.*` settings; print `LANDED=<id> COMMIT=<sha>`; a conflict aborts the merge and
    dies naming the files. In `extension/scripts/review.sh` `plan_text`, also drop the
    `**Issue**: #N` line and read `- [X]`/`- [x]` as `- [ ]`, so ticks and the issue line never
    make the plan review stale. Today's status for task branches stays for now.
  - Impact: `tests/implement.test.sh` (new cases); `tests/review.test.sh` (plan-state cases);
    `skills/implement/SKILL.md` drives these actions; `docs/reference.md`.
  - Completed when: `bash tests/implement.test.sh` passes: with three tasks (T002 depends on T001)
    `status` prints `START=T001` only; after `mark T001 ready` with a recorded review, `land T001`
    makes one merge commit with both trailers whose tree has `[X] T001`, and `status` then shows
    T001 `done` and `START=T002`; `land` refuses a task not `ready`, one whose ref moved after its
    review, and an uncommitted `tasks.md`; the third `changes` prints `FAILED=T001`, T002 stays
    `waiting`, an independent T003 starts; `retry T001` deletes the ref and the next `START=T001`
    has no `RESUME=`; with the ref present and no run record, `START=T001 … RESUME=yes` (nothing
    landed twice); a developer commit on the branch is kept by `land`, a conflicting one aborts with
    the file named; a legacy feature and a missing plan review are refused; `bash tests/review.test.sh`
    passes with a plan review that stays `ready` after a tick and an added `**Issue**:` line, and
    goes stale after a changed task line; a merged-in commit carrying another feature's
    `Landspec-Task: 007/T001` (through a PR merge or a squash) leaves T001 `pending`, this feature's
    landing reached only through a merge's second parent (a pull merge) shows `done`, and a bare
    `Landspec-Task: T001` does not count; `tests/run.sh` passes.

- [X] T003 [US1] Open one draft PR per feature with the task table and the latest end check, in extension/scripts/pr.sh (depends on T002)
  - Comes from: FR-010, FR-011, FR-012, US1 scenarios 2 and 4, US4 scenario 4, US5 scenarios 1-2; research R9; data-model "Feature PR"; contracts/scripts.md "pr.sh"
  - What: `pr.sh feature "<title>" <body-file>` is the existing `task|fix` arm of `pr.sh` with mode
    `feature` (the developer's answer to the plan review), on the feature branch only (else die
    naming `branch.sh <feature>`): every gate of that arm runs unchanged on the diff from
    `origin/<base>`, except the review read (`review.sh report`) and the `## Review` check, which the
    `feature` mode skips (one record decides the feature PR: the feature review, research R9); refuse a task ticked `[X]` with
    no landing commit (`T00n is ticked but was never landed: untick it or run /landspec:implement`);
    append a generated `## Tasks` table (id, summary, state, landing commit, review assessment),
    `## End check` from the feature's end-check record when one exists (data-model "End check": its
    head, round, tests, verdict and lines, with `checked at <reviewed>; the branch is now at <sha>` when
    the reviewed head differs; until `check` writes the record, a test makes one by hand); no
    `Closes #N` (superseded 2026-11-18: the `Closes #N` code T003 was built with is removed by
    T005; T009 moves the scan and mutation gates to `--ready`); open the PR as a draft: `open_pr` drafts when the mode is `feature`
    (as it does for a stacked task today), and where drafts are not available it warns
    `drafts are not available: do not merge this PR before pr.sh feature --ready` and opens a normal
    PR, or replace the open one's body; print
    `PR=<url> READY=no`.
  - Impact: `tests/pr.test.sh` (new cases); `extension/commands/pr.md`; `docs/reference.md`.
  - Completed when: `bash tests/pr.test.sh` passes: on a feature branch with two landed tasks
    `pr.sh feature` opens one draft PR whose body has the `## Tasks` table, with no
    review record of the branch; a second run updates that PR's body and opens no other; red tests,
    an unrun scan and a ticked-but-unlanded task are each refused (proving the `feature` mode
    reaches the shared gates); where the fake `gh` refuses drafts, the PR opens with the warning; off the feature branch it is
    refused; with a `changes needed` feature record for an older head, the body has `## End check`
    with its not met lines and `checked at`; the `task`, `spec`, `fix` and `state` cases pass
    unchanged; `tests/run.sh` passes.

- [ ] T017 [US1] Start every startable task at once and give a conflicting landing one round, in extension/scripts/implement.sh (depends on T002)
  - Comes from: FR-004, FR-006, FR-018, US1 scenarios 1, 3 and 4, edge cases (more tasks than the limit, parallel tasks on the same lines); research R7; data-model "Task", "Landing commit"; contracts/scripts.md "implement.sh"
  - What: feature-branch `status` prints one `START=<id> REF=… FROM=<feature head> [RESUME=yes]`
    line for every task whose `depends on` tasks are done and which is not done, failed or named
    by a `--running` (repeatable), in `ORDER`, while fewer than `cfg parallel_tasks 4` tasks are in
    flight (`--running` plus `building`); one `REVIEW=`, `FIX=` or `LAND=` line for every task in
    that state and not `--running`. `task_rounds` default becomes 2. `land`: on a merge conflict,
    abort, set the task's run record to `changes` with `conflict=1` (outside `task_rounds`), print
    `CONFLICT=<id> FILES=<files>` and exit 1; `status` then prints `FIX=<id> REASON=conflict`; a
    second conflict for the same task marks it failed and prints `FAILED=<id>`. `land` writes one
    `Low: <file>:<line> <title>` line per low finding of the task's recorded review into the
    landing message, above the trailers.
  - Impact: `tests/implement.test.sh` (T002's one-START cases become many-START cases);
    `docs/reference.md` (`parallel_tasks` row: builders at once, not stacked PRs; `task_rounds` 2).
  - Completed when: `bash tests/implement.test.sh` passes: with T001, T002 (depends on T001) and an
    independent T003, `status` prints `START=T001` and `START=T003`, not T002; with
    `parallel_tasks: 1` only `START=T001`; `--running T001` leaves only `START=T003`; two tasks in
    `ready` give two `LAND=` lines; two tasks editing the same line: the first lands, the second's
    `land` prints `CONFLICT=` with the file, leaves the feature branch at the first landing, and
    `status` prints `FIX=<id> REASON=conflict`; after the ref merges the feature branch and is
    marked ready again it lands; a second conflict prints `FAILED=`; the second `changes` (default
    2) prints `FAILED=`; a review with two low findings gives two `Low:` lines in the landing commit;
    `tests/run.sh` passes.

- [ ] T004 [US1] Rewrite the implement loop to build every startable task at once and land each as it is ready, in skills/implement/SKILL.md (depends on T003, T017, T018, T020)
  - Comes from: FR-004, FR-005, FR-006, FR-010, FR-018, FR-020, FR-021, US1, US3 scenarios 2-5; plan "Design notes" 2; research R7, R9, R13, R14
  - What: `skills/implement/SKILL.md`: the loop of plan design note 2: `status`; for every `START`,
    one background implementer in its own worktree on the task ref (resumed on `RESUME=yes`),
    added to `in flight` and passed back as `--running`; when one returns, `mark implemented`;
    `REVIEW`: one Opus reviewer per task (facts `commit:` the ref's head, `checkout:` its copy,
    `branch:` the ref, `base:` the feature branch), `record --branch`, `mark ready|changes` (a high
    or medium finding is `changes`); `FIX`: one round through SendMessage to its implementer, then
    always `record --delta`; `LAND` as soon as a task is ready, one `land` at a time; on
    `CONFLICT=`, the task's implementer merges the feature branch into its ref, resolves, runs the
    tests, then a delta review and `land` again; `FAILED=`: reported, the run goes on; `status`
    again after every landing. A draft `pr.sh feature` after the first landing and at the end of
    each run; the End report (task states, failed tasks with their findings, the PR, what is left).
    Drop restack, stack, OPEN per task, the stacked-draft rules, the per-task PR handover, the
    "fix grew past its 20 lines" fallback, `issues.sh`, `SIMPLIFY=` and the per-task scan and
    mutants. `agents/implementer.md`: step 1 becomes `git switch -c <REF> <FROM>` (or
    `git switch <REF>` on `RESUME=yes`) in its copy and `git config branch.<REF>.landspec-parent
    <feature branch>`; the tests run through `run_tests` after the last commit; no `branch.sh`, no
    push, no `security-scan.sh`, no `mutants.sh`, no `Elsewhere:`; on a conflict round, `git merge
    <feature branch>` into the ref and resolve; it returns `Copy:` and `REF=`.
    `preset/commands/speckit.implement.md`: build the feature's tasks as `/landspec:implement` does;
    ticking is done by `land`, never by hand. `extension/commands/pr.md`: the feature PR
    (`pr.sh feature`), not a task PR.
  - Impact: `tests/static.test.sh` checks of `skills/implement/SKILL.md`, `agents/implementer.md`,
    `extension/commands/pr.md` and the preset implement command are rewritten to the new steps;
    `skills/help/SKILL.md`.
  - Completed when: `bash tests/static.test.sh` passes with checks that the skill names `land`,
    `CONFLICT=`, `pr.sh feature`, `record --delta`, `model: opus` for the reviewer and the task ref
    as the review's branch, and names none of `restack`, `pr.sh task`, `issues.sh`, `SIMPLIFY`,
    `20 lines`; that `agents/implementer.md` runs `git switch -c <REF> <FROM>` and `run_tests`, and
    never `branch.sh`, `git push`, `security-scan.sh` or `mutants.sh`; each check fails when its
    line is reverted; `tests/run.sh` passes.

---

## Phase 4: User Story 2 - Progress without issues (Priority: P1)

**Goal**: no GitHub issue; progress from the landing commits, in `next.sh` and the PR's task table.

**Independent Test**: quickstart L4 and Q2.

- [ ] T005 [US2] Remove the GitHub issues: issues.sh, its command and config keys; the tasks hooks run the plan review, in extension/scripts/issues.sh, extension/commands/issues.md and extension/extension.yml (depends on T003, T006)
  - Comes from: FR-001, FR-002, FR-016, US2 scenario 1, SC-001; research R5 (superseded), R6; contracts/scripts.md "issues.sh (removed)", "lib.sh", "extension.yml hooks"
  - What: (replaces "one issue per feature", superseded 2026-11-18; the issues.sh work built for
    the old T005 is not landed.) Delete `extension/scripts/issues.sh` and `tests/issues.test.sh`.
    Rename `extension/commands/issues.md` to `extension/commands/plan-review.md`
    (`speckit.landspec.plan-review`): keep its step 1 (ground the plan in the code) and one plan
    review pass (`review.sh record --plan`; only a high finding sends the plan back for a fix and
    one more pass; medium and low findings shown to the developer; no Simplify step), then commit the spec folder on
    the feature branch (`docs(specs): <feature> plan and tasks`) and push; no issue, no ` — #N`, no
    spec PR. `extension/extension.yml`: `after_tasks` and `after_converge` run
    `speckit.landspec.plan-review`; the command list and descriptions follow. Config: `level.sh`
    stops writing `issue_labels`; `add_meta` assigns only (no `milestone`, no `project`). Remove the
    `Closes #N` code T003 added to `pr.sh feature` and the `ISSUE=` field (and any issue read) T006
    added to `next.sh`. `preset/templates/tasks-template.md` drops "one task = one issue" and the
    ` — #N` note. `agents/reviewer.md`'s description names the plan-review command instead of
    `/speckit-landspec-issues`; `extension/commands/analyzed.md` stops pointing at `issues.md`.
  - Impact: `tests/setup.test.sh` (the registered skill `speckit-landspec-issues` becomes
    `speckit-landspec-plan-review`); `tests/level.test.sh` (`issue_labels` no longer written);
    `tests/pr.test.sh` (`add_meta` milestone/project cases; T003's `Closes #N` case);
    `tests/next.test.sh` (`ISSUE=`); `tests/static.test.sh` checks of `issues.md` and the tasks
    template; `tests/helpers.sh`'s fake `gh` keeps its issue branch for the legacy release cases;
    `docs/reference.md`.
  - Completed when: `issues.sh` and `tests/issues.test.sh` are gone and no shipped file runs
    `issues.sh`; `bash tests/setup.test.sh` passes with the plan-review skill registered;
    `bash tests/level.test.sh` passes with no `issue_labels` line in a new project's config;
    `bash tests/pr.test.sh` passes with no `Closes #` in a feature PR body and no `--milestone` in
    the fake `gh` log; `bash tests/next.test.sh` passes with no `ISSUE=`; `bash tests/static.test.sh`
    passes with checks that `plan-review.md` names `review.sh record --plan` and no `gh issue`, and
    that the hooks name `speckit.landspec.plan-review`; `tests/run.sh` passes.

- [ ] T006 [P] [US2] Show progress from the landing commits, in extension/scripts/next.sh (depends on T002)
  - Comes from: FR-007, FR-015, US2 scenario 2, US6 scenario 1; research R3, R11; contracts/scripts.md "next.sh"
  - What: `next.sh [feature]` per contracts/scripts.md: one `done|failed|pending|waiting Tnnn
    <summary>` line per task from `task_done` and the run records, read from the feature branch
    (local, else origin's); then `FEATURE= BRANCH= PR=` and `DONE=x/y NEXT=` (no `ISSUE=`:
    superseded 2026-11-18; the field T006 was built with is removed by T005); no issue
    reads, no branch-key claims, no `parallel` or `RUN=` lines; a legacy feature named explicitly
    prints `LEGACY=` and the R11 message, exit 1; with no argument, legacy features are left out of
    the scan; `CHOOSE=` kept. Rewrite `skills/next/SKILL.md` (progress list, then
    `/landspec:implement <feature>`; no parallel offer, no `/speckit-implement <task>`).
  - Impact: `tests/next.test.sh` is rewritten; `tests/static.test.sh` checks of the next skill;
    `docs/reference.md`.
  - Completed when: `bash tests/next.test.sh` passes: with one landed task of three, it prints
    `done T001`, `pending T002`, `waiting T003` (depends on T002), `DONE=1/3 NEXT=T002`, and makes no
    `gh issue` call (the fake `gh` logs none); a branch only on origin is read; a legacy feature
    named explicitly prints `LEGACY=` and exits 1; with two finished legacy features and one new
    feature, no argument serves the new feature with no `CHOOSE=` and no `LEGACY=`; two new features
    with work print `CHOOSE=`; `tests/run.sh` passes.

---

## Phase 5: User Story 3 - One Opus review per plan and per task (Priority: P1)

**Goal**: every review runs on Opus, once: the plan blocks only on high, a task only on high or
medium, one fix round checked by a delta.

**Independent Test**: quickstart L3, L7 and Q4.

- [X] T007 [P] [US3] Run every review on Opus only, in hooks/guard-review.sh and extension/scripts/lib.sh
  - Comes from: FR-005, US3 scenario 4, edge case (Opus not available); research R4; contracts/scripts.md "review.sh", "hooks/guard-review.sh"
  - What: `lib.sh` `review_model` always prints `opus` (the `review_model` config key is no longer
    read); `hooks/guard-review.sh` refuses a reviewer launch whose `model` is not `opus` with
    `landspec: reviews run on Opus only (model: opus)`; an empty model passes only when
    `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` contains `opus`; fork and isolation rules unchanged.
    `extension/commands/review.md` says the call's `model` is `opus` (no config key, no refusal
    line); `agents/reviewer.md` frontmatter `model: opus`; `review.sh` keeps warning when the
    recorded model family is not `opus`.
  - Impact: `tests/guard-review.test.sh` (sonnet and fable pass cases become refusals);
    `tests/review.test.sh` and `tests/pr.test.sh` (model-warning cases: an Opus record no longer
    warns); `tests/static.test.sh` checks of
    `agents/reviewer.md` (`model: sonnet`) and `review.md` (`review_model:` and its refusal line);
    the reference row and README.
  - Completed when: `bash tests/guard-review.test.sh` passes: `model: sonnet`, `fable` and `haiku`
    are refused with the Opus message; `opus` passes; empty passes only with the force variable
    naming an Opus model; a fork and a missing isolation are still refused; `bash tests/review.test.sh`
    passes with a record whose model is not Opus warned about; `bash tests/static.test.sh` passes
    with checks that `agents/reviewer.md` has `model: opus` and that `review.md` names `opus` and
    not `review_model`, each seen failing on the old text; `tests/run.sh` passes.

- [ ] T018 [P] [US3] Gate the plan review on high findings and the task review on high and medium, with deltas of any size, in extension/scripts/review.sh and extension/commands/review.md (depends on T002)
  - Comes from: FR-006, FR-019, FR-020, US3 scenarios 1, 3 and 4, SC-003; research R6, R13; contracts/scripts.md "review.sh"
  - What: `review.sh check --plan` passes when the plan record is current and its findings count
    has no high (was: `Assessment: ready`); `check --branch` passes when the branch record is
    current and has no high or medium finding; `record --delta` drops its "at most 20 lines outside
    the previous findings' files" refusal (the other refusals stay). `extension/commands/review.md`:
    the Assessment rule: a plan review ends `changes needed` only with a high finding, a task
    review only with a high or medium; a delta of a conflict round reads the merge's resolution
    (`git show --remerge-diff <merge>`) and the commits after it, not the other tasks' code; the
    20-line paragraph goes.
  - Impact: `tests/review.test.sh` (plan and branch gate cases, the 20-line delta refusal case
    goes); `tests/pr.test.sh` (`pr.sh fix` reads `review.sh report`, whose gate follows);
    `tests/static.test.sh` checks of `review.md`; `docs/reference.md`.
  - Completed when: `bash tests/review.test.sh` passes: `check --plan` passes on a record with
    `Findings: 0 high, 2 medium, 3 low` and fails on `1 high`; `check --branch` fails on `1 medium`
    and passes on `0 high, 0 medium, 2 low`; a delta whose fix changes 40 lines outside the earlier
    files is recorded; `bash tests/static.test.sh` passes with checks that `review.md` states both
    Assessment rules and has no "20 lines", each seen failing on the old text; `tests/run.sh` passes.

- [ ] T019 [P] [US3] Remove the Simplify sections and answers from the plan review, in extension/scripts/review.sh and extension/commands/review.md (depends on T018)
  - Comes from: FR-019, US3 scenario 1; research R6
  - What: delete `review.sh answer --plan`, the areas state, the `due`/`asked` refusals in `record
    --plan` and `check --plan`, and the `SIMPLIFY=` lines; `review.md` drops "A Simplify section"
    and the `simplify:` facts (T005's `plan-review.md` already has no Simplify step).
  - Impact: `tests/review.test.sh` (Simplify and answer cases go); `tests/stats.test.sh` if it
    reads the areas; `tests/static.test.sh` checks of `review.md`; `docs/reference.md`.
  - Completed when: `review.sh answer --plan x y` exits non-zero with the usage error; a plan area
    found in three rounds prints no `SIMPLIFY=` and `check --plan` passes on a record without a
    high; `bash tests/static.test.sh` passes with a check that `review.md` names no `## Simplify:`;
    `tests/run.sh` passes.

---

## Phase 6: User Story 4 - The end check before the PR is ready (Priority: P2)

**Goal**: tests and an Opus feature review on the branch head; gaps become tasks on the same
branch with one plan pass; the PR turns ready on that one record, after one scan of the feature
diff.

**Independent Test**: quickstart L5 (check cases), L6 (ready cases) and Q5.

- [ ] T008 [US4] Run the end check on the feature branch itself and file gaps as tasks on it, in extension/scripts/implement.sh (depends on T004)
  - Comes from: FR-008, FR-009, FR-019, US4 scenarios 1-2 and 4, edge cases (branch behind the base, a clean merge that breaks the tests); research R8; data-model "End check"
  - What: new `implement.sh check` (beside `check-copy`, which a later task removes): refuse while a task
    is not done; update the feature branch from `origin/<base>` (merge; a conflict aborts and dies
    with the files); point `refs/landspec/check/<feature>` at the head; print
    `CHECK=<head> ROUND=<n>`, or `UNCHANGED=<n>` for a head whose own tests or review already failed, or
    `ROUNDS_EXHAUSTED=<n>` past `cfg feature_rounds 3`; `UNCHANGED` only when this head's own tests
    or own review (`reviewed:` equal to the head) failed. It writes the end-check record
    (data-model "End check": `head`, `heads`, `tests: pending`); `check-result green|red` sets
    `tests:` in it; `review.sh record --feature` adds `verdict:`, `reviewed: <the check ref it reviewed>` and the
    lines to the same file and no longer deletes anything on a green `ready` (the round file goes; the round is the count of
    `heads:`). `review.sh` feature mode reads the check ref when no check copy exists. In
    `skills/implement/SKILL.md`, "The end check": the tests on the head through `run_tests` in a
    detached worktree (a tree already green is not run again), the Opus feature review (facts:
    `feature review`, the folder, `commit:` the head, `base: origin/<base>`), `review.sh record
    --feature`, then each `not met` line (and red tests, as one task) appended to `tasks.md` as a
    task (`Comes from:` the line), one plan review pass of the new lines (`review.sh record
    --plan`), commit and push them on the branch, and back to the loop; on a pass,
    `security-scan.sh --changed` and `mutants.sh` on the feature branch, then `pr.sh feature
    --ready`; at the limit, the PR stays a draft and its body keeps the record's not met lines.
  - Impact: `tests/implement.test.sh`; `tests/review.test.sh` (feature record from the check ref);
    `tests/static.test.sh` checks of the skill's end check; `docs/reference.md`.
  - Completed when: `bash tests/implement.test.sh` passes: `check` with a pending task is refused;
    with all done it prints `CHECK=<head> ROUND=1` and the ref points at the head; `check-result red`
    then `check` on the same head prints `UNCHANGED=1`; a new commit gives `ROUND=2`; past
    `feature_rounds` it prints `ROUNDS_EXHAUSTED=`; a base commit is merged in first, and a
    conflicting one stops with the file named; after `check`, `check-result green` and a `ready`
    `record --feature`, the record still holds `tests: green`, the verdict and the lines;
    `bash tests/review.test.sh` passes with a feature record made from the check ref;
    `bash tests/static.test.sh` passes with checks that the skill's end check names
    `implement.sh check`, `record --feature`, `record --plan` for the appended tasks,
    `security-scan.sh --changed` before `pr.sh feature --ready`, and no `check-copy` and no
    `issues.sh`; `tests/run.sh` passes.

- [ ] T009 [US4] Mark the feature PR ready on the latest feature review, after one scan and mutation run of the feature diff, in extension/scripts/pr.sh and extension/scripts/review.sh (depends on T003, T008, T018, T021)
  - Comes from: FR-010, FR-011, FR-012, FR-020, FR-022, US1 scenario 5, US4 scenario 3, US5 scenario 3, SC-005, SC-007; research R9, R13, R15; data-model "Feature PR"; contracts/scripts.md "pr.sh", "review.sh"
  - What: `review.sh check --feature` and `report --feature` (today `--feature` takes only
    `record`): pass when the end-check record has `verdict: ready`, `tests: green`, and `reviewed`
    and `head` both equal to the feature branch's head. `pr.sh feature` (draft) no longer requires
    the mutants and scan records, and appends `## Low findings` from the landing commits' `Low:`
    lines. `pr.sh feature --ready`: refuse unless every task is done, `review.sh check --feature`
    passes, and the scan record (and with a mutate command the mutants record) exists for this
    diff; refuse on a `findings high` line naming the scanner; list other findings, `missing`
    scanners and `mutants unavailable` in the body without refusing; surviving mutants keep
    today's `## Evidence` rule; then `gh pr ready`; print `PR=<url> READY=yes`.
  - Impact: `tests/review.test.sh`; `tests/pr.test.sh` (the T003 draft cases that wrote scan and
    mutants records may drop them); `docs/reference.md`.
  - Completed when: `bash tests/review.test.sh` passes: `check --feature` fails with no record, with
    a `changes needed` record, with `tests: red`, and after a new commit on the branch, and passes on
    a `ready`, green record for the head; a `ready` verdict whose `reviewed` is an older head, with
    green tests on the new head, fails; `bash tests/pr.test.sh` passes: a draft opens with no scan
    or mutants record and lists two landed `Low:` lines under `## Low findings`; `--ready` is
    refused with a pending task, without a ready feature review for the head, without a scan record,
    and on `semgrep findings high`; with a `missing` scanner and `mutants unavailable` it marks the
    PR ready (the fake `gh` logs `pr ready`) and lists both, with `## End check` in its body;
    `pr.sh fix` still requires both records (unchanged); `tests/run.sh` passes.

---

## Phase 7: User Story 5 - The existing gates and the release on the single PR (Priority: P2)

**Goal**: the release lists the feature PR; tests once (T020), scan and mutants once (T009, T021).

**Independent Test**: quickstart L5 (release cases), L9 and Q6.

- [ ] T020 [US5] Run the tests once per tree, in extension/scripts/lib.sh and extension/scripts/implement.sh (depends on T017)
  - Comes from: FR-021, US5 scenario 2, SC-007; research R14; data-model "Test record"; contracts/scripts.md "lib.sh", "implement.sh"
  - What: `run_tests`' record key becomes the tree and the command only (drop the copy's path), so
    a tree tested green in the builder's worktree counts in the main checkout and in a detached
    worktree of the same tree. New `tests_green <tree>` in `lib.sh` (true when that record exists,
    or there is no test command). `implement.sh mark <task> implemented` refuses unless
    `tests_green` holds for the task ref's head tree: `no green test run for <ref> at <sha>: the
    implementer runs the tests through run_tests after its last commit`.
  - Impact: `tests/pr.test.sh` (the `run_tests` record cases: a record from another worktree now
    counts); `tests/implement.test.sh` (`mark implemented` setups record a green run first);
    `docs/reference.md` (tests run once per tree).
  - Completed when: `bash tests/pr.test.sh` passes with a case where a tree tested green in one
    worktree is not run again from another (the test command's side file is written once);
    `bash tests/implement.test.sh` passes: `mark implemented` is refused with no record for the
    ref's tree and accepted after `run_tests` on it; with no test command it is accepted;
    `tests/run.sh` passes.

- [ ] T021 [P] [US5] Record a high scanner finding as such, in extension/scripts/security-scan.sh
  - Comes from: FR-022, US5 scenario 3; research R15; contracts/scripts.md "security-scan.sh"
  - What: a scanner whose report has a high or critical finding prints `<tool> findings high
    <detail>` (gitleaks: every finding; osv-scanner, semgrep, zizmor, trivy: their own severity
    field in the report they already write), others `<tool> findings <detail>`; the `--changed`
    record keeps the same lines. Header comment: the record is read by `pr.sh feature --ready`.
  - Impact: `tests/security-scan.test.sh` (fixture reports with a high and with a low finding);
    `docs/security.md` and `docs/reference.md` (the line format).
  - Completed when: `bash tests/security-scan.test.sh` passes: a fake semgrep report with an
    `ERROR`-severity result gives `semgrep findings high`, one with only `INFO` gives `semgrep
    findings` without `high`, any gitleaks finding gives `findings high`, a missing scanner stays
    `missing`; `tests/run.sh` passes.

- [ ] T010 [US5] Key the release and the stats on the feature PR, in extension/scripts/implement.sh and extension/scripts/stats.sh (depends on T002)
  - Comes from: FR-013, FR-015, US5 scenario 4, SC-004; research R10, R11
  - What: `release-plan`: PRs merged whose head starts with `<branch_prefix>/<NNN>-` (not
    `/<NNN>-t`), the merge commit of the feature PR as `M`; no issue read; a legacy feature
    (`legacy_feature`) keeps today's path (task PRs, every task issue closed through
    `closed_issues`); patch bump when the feature PR's title starts with `fix`. `stats.sh`: group by
    the feature PR instead of task and spec PRs; the PLAN line drops `first->issues` (no issues
    event any more).
  - Impact: `tests/implement.test.sh` (release-plan cases); `tests/stats.test.sh`;
    `tests/static.test.sh` release-plan text; `docs/reference.md` ("Measurements").
  - Completed when: `bash tests/implement.test.sh` passes: a merged feature PR gives
    `RELEASE=bump … PRS=<that PR>` with no `gh issue` call; an open one gives no bump and says why;
    a fix feature gives a patch bump; a legacy feature with its task PRs merged and issues closed
    still gives `RELEASE=bump`; `bash tests/stats.test.sh` passes with one line per feature PR and a
    PLAN line without `first->issues`; `tests/run.sh` passes.

---

## Phase 8: User Story 6 - Moving to the new flow (Priority: P3)

**Goal**: the per-task modes are gone, and docs, help, levels, scaffolds and templates describe
only one PR per feature, with no issues.

**Independent Test**: quickstart L8 and US6 scenario 3.

- [ ] T011 [US6] Remove pr.sh's task and spec modes, in extension/scripts/pr.sh (depends on T004, T005, T009)
  - Comes from: FR-003, FR-012, FR-016, SC-005; research R9; plan "Design notes" 3
  - What: delete `pr.sh task` and `pr.sh spec`, the stacked-parent logic, the issue lookup and its
    `Closes #N`, and the spec PR body (`pr_skips_base` stays in `lib.sh`: `level.sh` uses it for
    init's warning). Every `pr.sh task T001` call in `tests/pr.test.sh` becomes `pr.sh fix`, which
    runs the same arm, so every gate and review-record case keeps passing unchanged (SC-005), except
    these, named here: the dirty-tree cases get a body file (`fix` needs one); the task-branch
    refusal and the `Closes #N` cases go with task mode, except the case that checks the recorded
    review's folded block reaches the body (`Independent review recorded for this diff`,
    `Assessment:`): it stays, running through `pr.sh fix`, and drops only its clause that the block
    sits before `Closes #N`; the spec and stacked cases go. `open_pr` keeps its draft branch for
    `feature` when the stacked-parent logic goes. `extension/scripts/guard.sh`'s block message names
    `pr.sh feature` and `pr.sh fix`; `extension/commands/analyzed.md` drops the level-`full` spec PR
    step; the header comments of `extension/scripts/mutants.sh` and `security-scan.sh` name
    `pr.sh feature --ready`.
  - Impact: `tests/pr.test.sh`; `tests/guard.test.sh`; `tests/static.test.sh` checks of
    `analyzed.md`.
  - Completed when: `pr.sh task …` and `pr.sh spec …` exit non-zero with the usage error;
    `bash tests/pr.test.sh` passes with every former task-mode gate and review-record case running
    through `pr.sh fix`; `bash tests/guard.test.sh` passes with the new message; `tests/run.sh`
    passes.

- [ ] T012 [US6] Remove branch.sh's task mode, in extension/scripts/branch.sh (depends on T011)
  - Comes from: FR-003, FR-016; research R1
  - What: delete the task id, the issue check, "merge the spec PR first", `--from`, the claim push
    and exit 3, and the parent-head file; a task id refuses with `branch.sh takes a feature, not a
    task: tasks are built on the feature branch`. The setups that run `branch.sh <feature> T001`
    in `tests/review.test.sh`, `tests/mutants.test.sh`, `tests/tfplan.test.sh`, `tests/next.test.sh`
    and `tests/pr.test.sh` move to the feature branch (and a task ref where a test needs one).
  - Impact: `tests/branch.test.sh` (task, `--from` and claim cases go); the five test files above.
  - Completed when: `branch.sh 001 T001` exits non-zero with the "takes a feature" message and
    changes nothing, and `branch.sh 001 --from x` is refused (`tests/branch.test.sh`);
    `tests/run.sh` passes.

- [ ] T013 [US6] Remove implement.sh's per-task actions, in extension/scripts/implement.sh (depends on T008, T012, T017)
  - Comes from: FR-004, FR-016; research R7, R8
  - What: delete `restack`, `stack`, `move`, `check-copy` and their helpers, and the task-branch
    `status` with its slot arithmetic (the feature-branch `status` of T017 keeps `parallel_tasks`);
    `review.sh`'s check-copy wording names `implement.sh check`.
  - Impact: `tests/implement.test.sh` (restack, stack, check-copy and task-branch status cases go);
    `tests/review.test.sh` (feature cases that built a check copy).
  - Completed when: `implement.sh <f> restack`, `stack`, `move` and `check-copy` exit non-zero with
    the usage error (`tests/implement.test.sh`), and T017's parallel `status` cases still pass;
    `tests/run.sh` passes.

- [ ] T014 [P] [US6] Describe one branch and one PR per feature, with no issues, in the generated constitution text, templates and scaffolds, in extension/levels/lite.md (depends on T005, T013)
  - Comes from: FR-016, US6 scenario 3
  - What: the "Way of working" block of `extension/levels/lite.md` (the only level file with one;
    `standard.md` and `full.md` add rules with no task or PR bullet): one feature = one branch = one
    PR, no issues; tasks run in parallel and a task is done when it lands on the feature branch with
    its review; the review bullet: each task's diff is reviewed before it lands (high and medium
    block), and a feature PR is marked ready only after its feature review, recorded for its head,
    and one scan of the feature diff; any other PR goes through `pr.sh fix`; the PR merges once.
    `preset/templates/constitution-template.md`: the same. `extension/scaffold/*/.github/pull_request_template.md`:
    no `Closes #` line. `extension/scaffold/lite/.github/copilot-instructions.md`: one feature PR,
    no issue, no spec PR. `skills/init/SKILL.md` (its task-PR and issue lines).
    `extension/scripts/level.sh`'s workflow warning ("never runs on the feature PR").
    `extension/scripts/review.sh`'s comment on `outside --plan` (outside reviewers of the feature
    PR). `extension/extension.yml`'s description and tags (no `issues`). The comment of
    `extension/scaffold/standard/.github/workflows/close-linked-issues.yml` (it closes issues a PR
    names itself, when it merges into a non-default base; landspec creates none). In the same task,
    run `level.sh` to regenerate this repository's own block in `.specify/memory/constitution.md`
    (never edited by hand), so the rules the next reviewer reads describe the new flow.
  - Impact: `tests/level.test.sh` (generated text and the warning); `tests/static.test.sh` (the
    warning wording); `tests/setup.test.sh` if it checks the scaffold text.
  - Completed when: `bash tests/level.test.sh` passes with the new "Way of working" text in a
    generated lite constitution and no "One task = one issue"; this repository's generated block
    says one PR per feature; `tests/run.sh` passes.

- [ ] T015 [P] [US6] Rewrite the design, reference and security docs for one PR per feature, in docs/design.md, docs/reference.md and docs/security.md (depends on T013, T019)
  - Comes from: FR-016, US6 scenario 3; constitution "Docs are the source of truth"
  - What: `docs/design.md`: replace the sections "One task = one issue = one branch = one PR", "The
    spec is its own PR" and "Parallel tasks, stacked PRs" with one section on one PR per feature
    (why: the merge loop and the issue overhead; how: parallel task refs, landing commits, one Opus
    review per task with one fix round, the end check, one record deciding the PR, each check run
    once); `docs/reference.md`: every section that describes the per-task flow or the issues
    ("Stack detection", "Several features at once", "What happens automatically", "Mutation
    testing", "Terraform plan", "Measurements", the plan review's Simplify part) and the
    "Configuration" table (remove `review_model`, `issue_labels`, `milestone`, `project`; add
    `task_rounds` default 2; `parallel_tasks` = builders at once); `docs/security.md` "Before a PR
    opens" (scan and mutants once, before ready; high blocks) and review-hook rows (Opus only, one
    PR per feature); `docs/GUIDELINES.md` (its task-PR line).
  - Impact: `tests/static.test.sh` checks on these docs are updated to the new text.
  - Completed when: `bash tests/static.test.sh` passes with checks that design, reference and
    security name `pr.sh feature`, parallel tasks and Opus reviews, that reference has a
    `task_rounds` row and no `issue_labels` row, each seen failing on the old text; `tests/run.sh`
    passes.

- [ ] T016 [US6] Rewrite the README, help and examples for one PR per feature, in README.md, skills/help/SKILL.md and examples/ (depends on T014, T015)
  - Comes from: FR-016, US6 scenario 3
  - What: `README.md` (the tagline, the loop, the review model, the per-task PR and issue lines);
    `skills/help/SKILL.md`; and the one negative check: a `tests/static.test.sh` case that runs
    `grep -rnE 'pr\.sh (task|spec)|branch\.sh [^ ]+ T[0-9]|restack|check-copy|review_model|issues\.sh|landspec\.issues|issue_labels|SIMPLIFY|answer --plan|task PR|spec PR|one task = one issue|one issue per (task|feature)|feature issue'`
    over `README.md docs skills agents extension preset hooks examples` and fails on any line
    outside one allow-list (release notes under `docs/releases/`, the history rows of
    `docs/GUARDRAILS.md`, the legacy R11 messages, the legacy release-plan text `implement.sh`
    keeps for per-task features, and the check itself); before it, the leftovers it would find are
    rewritten: `review_model()` in `lib.sh` becomes `reviewer_model()` (it returns `opus`; its
    caller in `review.sh` follows), and the comments in `lib.sh`, `review.sh`, `next.sh` and
    `stats.sh` that name task or spec PRs or issues; `examples/README.md` and `examples/github/*`
    (one feature PR replaces `issue-T001.md` and `task-pr-T001.md`; `spec-pr.md` is removed);
    remove `assets/flow-*.svg` that show task PRs, or redraw them with the README's new loop.
  - Impact: `tests/static.test.sh` README and help checks; `extension/scripts/lib.sh`,
    `review.sh`, `next.sh`, `stats.sh` (the renamed helper and comments); `/landspec:help` answers
    from these files.
  - Completed when: `bash tests/static.test.sh` passes with checks that README and help name
    `pr.sh feature`, parallel tasks and Opus reviews, and with the negative check, which is seen
    failing once with one old line put back (in a doc, and in a script comment); `tests/run.sh`
    passes.

---

## Dependencies & order

- Landed: T001, T007, T002. Built, landing first: T003 (T002), T006 (T002).
- T017, T018, T010 need T002; T021 needs nothing; T019 needs T018; T020 needs T017; T005 needs
  T003, T006; T004 needs T003, T017, T018, T020; T008 needs T004; T009 needs T003, T008, T018,
  T021.
- T011 needs T004, T005, T009; T012 needs T011; T013 needs T008, T012, T017; T014 needs T005,
  T013; T015 needs T013, T019; T016 needs T014, T015.

## Build order (parallel waves)

Every task of a wave starts at once; a wave starts as soon as its tasks' dependencies have landed
(a task may start before its whole wave's neighbours finish).

| Wave | Tasks | Notes |
|---|---|---|
| 0 | T001, T007, T002 | landed |
| 1 | T003, T006, T010, T017, T018, T021 | T003 and T006 are built: review and land; T010 and T017 both edit `implement.sh` (different functions: a conflict gets its round) |
| 2 | T005, T019, T020 | T005 and T020 both edit `lib.sh` (different functions) |
| 3 | T004 | |
| 4 | T008 | |
| 5 | T009 | |
| 6 | T011 | |
| 7 | T012 | |
| 8 | T013 | |
| 9 | T014, T015 | |
| 10 | T016 | |

## Implementation strategy

- MVP = US1 (T001–T004, T017, T020) plus T007 and T018: a feature builds in parallel on one branch
  into one draft PR with one Opus review per task. US2 (no issues) and US4 (end check, ready PR,
  one scan) complete the flow; T011–T013 remove the per-task modes; US6 finishes the docs.
- Not a task: the constitution's **Project** paragraph is amended through `/speckit-constitution`
  in its own PR, merged before this feature's PR (plan, Complexity Tracking).
