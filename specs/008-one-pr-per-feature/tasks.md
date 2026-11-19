---

description: "Tasks for feature 008: one issue and one pull request per feature"
---

# Tasks: One issue and one pull request per feature

**Issue**: #263

**Input**: Design documents from `/specs/008-one-pr-per-feature/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/scripts.md, quickstart.md

**Tests**: every task ships its own tests, in the same task as its code, from its *Completed when*
and the spec's scenarios. Each new check is run once with its rule disabled and seen to fail
(constitution, FR-017). After every task the whole suite passes (`tests/run.sh`) on bash 3.2 and
bash 5 (CI jobs `linux`, `bash32`, `macos`): a task fixes every test and static check its change
breaks, not only the ones it names.

**Add first, remove once** (the developer's answer to the plan review, 2026-11-18): T001–T010 add
the new paths beside the old ones and delete nothing another file still calls; T011–T013 remove the
per-task modes, one script each. Impact lists name files and symbols, not line numbers.

**One negative check** (the developer's answer, 2026-11-18): the text tasks rewrite their text;
T016 adds the single static check, with one allow-list, that no shipped file names a per-task mode.

**Every script task** edits `extension/scripts/<script>` and its copy in
`.specify/extensions/landspec/scripts/` identically (`tests/static.test.sh` fails on drift).

**This feature's own build** (research R12): one branch, one PR.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependencies)
- `(depends on Tnnn)`: needs that task first
- **[Story]**: the user story of spec.md (US1–US6)

---

## Phase 3: User Story 1 - A whole feature in one pull request (Priority: P1) 🎯 MVP

**Goal**: one feature branch made at specify time; tasks built one at a time on local task refs
and landed on the branch; one draft PR per feature.

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
    `REVIEW=`, `FIX=`, `LAND=`, then `CHECK=yes|no`, `PR=<url|->`, `ORDER=`, `DONE=x/y`; done from
    `task_done` (new in `lib.sh`: the feature branch's history holds a commit whose message has the
    line `Landspec-Task: <NNN>/<id>`, the feature's number and the task id, so another feature's
    landings never count and this feature's count in every merge shape); `waiting` while a `depends on` task is not done; `git worktree prune`
    first, `RESUME=yes` when the ref exists, `waiting REASON=locked worktree <path>` when it is
    checked out in a locked worktree. `changes` at `cfg task_rounds 3` fix rounds (replacing the
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
    goes stale after a changed task line; `tests/run.sh` passes.

- [ ] T003 [US1] Open one draft PR per feature with the task table and the latest end check, in extension/scripts/pr.sh (depends on T002)
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
    the reviewed head differs; until `check` writes the record, a test makes one by hand), and `Closes #<feature issue>` when `tasks.md` has the
    `**Issue**: #N` line; open the PR as a draft: `open_pr` drafts when the mode is `feature`
    (as it does for a stacked task today), and where drafts are not available it warns
    `drafts are not available: do not merge this PR before pr.sh feature --ready` and opens a normal
    PR, or replace the open one's body; print
    `PR=<url> READY=no`.
  - Impact: `tests/pr.test.sh` (new cases); `extension/commands/pr.md`; `docs/reference.md`.
  - Completed when: `bash tests/pr.test.sh` passes: on a feature branch with two landed tasks
    `pr.sh feature` opens one draft PR whose body has the `## Tasks` table and `Closes #N`, with no
    review record of the branch; a second run updates that PR's body and opens no other; red tests,
    an unrun scan and a ticked-but-unlanded task are each refused (proving the `feature` mode
    reaches the shared gates); where the fake `gh` refuses drafts, the PR opens with the warning; off the feature branch it is
    refused; with a `changes needed` feature record for an older head, the body has `## End check`
    with its not met lines and `checked at`; the `task`, `spec`, `fix` and `state` cases pass
    unchanged; `tests/run.sh` passes.

- [ ] T004 [US1] Rewrite the implement loop as one task at a time, landed on the feature branch, in skills/implement/SKILL.md (depends on T002, T003, T007)
  - Comes from: FR-004, FR-005, FR-006, FR-010, US1, US3 scenarios 1-3; plan "Design notes" 2; research R9
  - What: `skills/implement/SKILL.md`: the loop of plan design note 2 (`status` → START one
    implementer on the task ref, or resume it on `RESUME=yes` → tests in its copy →
    `mark implemented` → REVIEW one Opus reviewer with facts `commit:` the ref's head, `checkout:`
    its copy, `branch:` the ref, `base:` the feature branch → `record --branch`/`--delta` →
    `mark ready|changes` → FIX → LAND → `issues.sh --sync` → next); before each `pr.sh feature`, run
    `security-scan.sh --changed` and the mutation testing on the feature branch when this diff has
    no record of them; a draft `pr.sh feature` after the first landing and at the end of each run;
    the End report (task states, failed tasks, the PR, what is left). Drop restack, stack, parallel
    slots, OPEN per task, the stacked-draft rules and the per-task PR handover.
    `agents/implementer.md`: step 1 becomes `git switch -c <REF> <FROM>` (or `git switch <REF>` on
    `RESUME=yes`) in its copy and `git config branch.<REF>.landspec-parent <feature branch>`; no
    `branch.sh`, no push, no `Elsewhere:`; it returns `Copy:` and `REF=`.
    `preset/commands/speckit.implement.md`: build the feature's tasks as `/landspec:implement` does;
    ticking is done by `land`, never by hand. `extension/commands/pr.md`: the feature PR
    (`pr.sh feature`), not a task PR.
  - Impact: `tests/static.test.sh` checks of `skills/implement/SKILL.md`, `agents/implementer.md`,
    `extension/commands/pr.md` and the preset implement command are rewritten to the new steps;
    `skills/help/SKILL.md`.
  - Completed when: `bash tests/static.test.sh` passes with checks that the skill names `land`,
    `pr.sh feature`, `issues.sh --sync`, `security-scan.sh --changed`, `model: opus` for the reviewer
    and the task ref as the review's branch, and names none of `restack`, `pr.sh task`,
    `parallel_tasks`; that `agents/implementer.md` runs `git switch -c <REF> <FROM>` and never
    `branch.sh` or `git push`; each check fails when its line is reverted; `tests/run.sh` passes.

---

## Phase 4: User Story 2 - One issue per feature (Priority: P1)

**Goal**: one GitHub issue per feature, its checklist ticked as tasks land, closed by the PR.

**Independent Test**: quickstart L3, L4 and Q2.

- [ ] T005 [US2] Create one issue per feature and tick its checklist as tasks land, in extension/scripts/issues.sh (depends on T001, T002)
  - Comes from: FR-001, FR-002, US2 scenarios 1-3, edge case (issue edited by hand); research R5, R6; data-model "Feature issue"; contracts/scripts.md "issues.sh"
  - What: `issues.sh [--sync]` per contracts/scripts.md: keep the plan-review refusal; refuse off
    the feature branch; one issue titled `[NNN] <spec.md H1 title>`, body = spec path, branch, then
    `- [ ] Tnnn <summary>` per task (`[x]` when `task_done`); reuse an open issue with that exact
    title; write `**Issue**: #N` under the H1 of `tasks.md`, commit the spec folder
    (`docs(specs): <feature> plan and tasks, issue #N`) and push; `--sync` or a changed task list
    rewrites the body (`ISSUE=#N (updated)`), and commits and pushes `tasks.md` when it has
    uncommitted task lines (gap tasks of the end check); labels from `cfg issue_labels` (default
    `type:feature` in `level.sh` and in `issues.sh`'s own fallback), `add_meta` as today;
    `event issues` kept. New helper `feature_issue <fdir>` in `lib.sh`. Rewrite
    `extension/commands/issues.md` (plan review loop kept; no per-task issues, no ` — #N` suffixes,
    no spec PR: step 5 becomes "commit and push on the feature branch");
    `preset/templates/tasks-template.md` drops "one task = one issue" and the ` — #N` note; the
    issues command's description in `extension/extension.yml`.
  - Impact: `tests/issues.test.sh` is rewritten; `tests/level.test.sh` (default label);
    `tests/static.test.sh` checks of `issues.md` and the tasks template; `lib.sh` `task_issue` keeps
    only `legacy_feature`'s use; `docs/reference.md`.
  - Completed when: `bash tests/issues.test.sh` passes: five tasks give exactly one issue with five
    checklist lines and `**Issue**: #N` committed on the branch; a rerun creates none and an added
    task updates the body; `--sync` after one landing ticks that task only; `--sync` with an
    uncommitted appended task commits it on the branch and adds its line; an open issue with the
    title is reused when the line is missing; refused without a ready plan review and off the feature
    branch, creating nothing; `bash tests/level.test.sh` passes with `type:feature` for a new project
    and an existing `issue_labels` kept; `tests/run.sh` passes.

- [ ] T006 [P] [US2] Show progress from the landing commits, in extension/scripts/next.sh (depends on T002)
  - Comes from: FR-007, FR-015, US2 scenario 4, US6 scenario 1; research R3, R11; contracts/scripts.md "next.sh"
  - What: `next.sh [feature]` per contracts/scripts.md: one `done|failed|pending|waiting Tnnn
    <summary>` line per task from `task_done` and the run records, read from the feature branch
    (local, else origin's); then `FEATURE= BRANCH= ISSUE= PR=` and `DONE=x/y NEXT=`; no issue
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

## Phase 5: User Story 3 - An Opus review after each task (Priority: P1)

**Goal**: every review runs on Opus; any other model is refused.

**Independent Test**: quickstart L7 and Q4.

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

---

## Phase 6: User Story 4 - The end check before the PR is ready (Priority: P2)

**Goal**: tests and an Opus feature review on the branch head; gaps become tasks on the same
branch; the PR turns ready on that one record.

**Independent Test**: quickstart L5 (check cases), L6 (ready cases) and Q5.

- [ ] T008 [US4] Run the end check on the feature branch itself and file gaps as tasks on it, in extension/scripts/implement.sh (depends on T002, T004, T005)
  - Comes from: FR-008, FR-009, US4 scenarios 1-2 and 4, edge case (branch behind the base); research R8; data-model "End check"
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
    `skills/implement/SKILL.md`, "The end check": tests on the head in a detached worktree, the Opus
    feature review (facts: `feature review`, the folder, `commit:` the head, `base: origin/<base>`),
    `review.sh record --feature`, then each `not met` line appended to `tasks.md` as a task
    (`Comes from:` the line), a plan review of the new lines (`review.sh record --plan`), then
    `issues.sh --sync`, which commits and pushes them on the branch, and back to the loop;
    on a pass, `pr.sh feature --ready`; at the limit, the PR stays a draft and its body keeps
    the record's not met lines.
  - Impact: `tests/implement.test.sh`; `tests/review.test.sh` (feature record from the check ref);
    `tests/static.test.sh` checks of the skill's end check; `docs/reference.md`.
  - Completed when: `bash tests/implement.test.sh` passes: `check` with a pending task is refused;
    with all done it prints `CHECK=<head> ROUND=1` and the ref points at the head; `check-result red`
    then `check` on the same head prints `UNCHANGED=1`; a new commit gives `ROUND=2`; past
    `feature_rounds` it prints `ROUNDS_EXHAUSTED=`; a base commit is merged in first, and a
    conflicting one stops with the file named; after `check`, `check-result green` and a `ready`
    `record --feature`, the record still holds `tests: green`, the verdict and the lines;
    `bash tests/review.test.sh` passes with a feature record made from the check ref; `bash tests/static.test.sh` passes with checks that the skill's
    end check names `implement.sh check`, `record --feature`, `issues.sh --sync` after the appended
    tasks and `pr.sh feature --ready`, and no `check-copy`; `tests/run.sh` passes.

- [ ] T009 [US4] Mark the feature PR ready on the latest feature review, in extension/scripts/pr.sh and extension/scripts/review.sh (depends on T003, T008)
  - Comes from: FR-010, FR-011, US1 scenario 4, US4 scenario 3; research R9; data-model "Feature PR"; contracts/scripts.md "pr.sh", "review.sh"
  - What: `review.sh check --feature` and `report --feature` (today `--feature` takes only
    `record`): pass when the end-check record has `verdict: ready`, `tests: green`, and `reviewed` and `head`
    both equal to the feature branch's head. `pr.sh feature --ready`: refuse unless every task is done and
    `review.sh check --feature` passes, then `gh pr ready`; print `PR=<url> READY=yes`.
  - Impact: `tests/review.test.sh`; `tests/pr.test.sh`; `docs/reference.md`.
  - Completed when: `bash tests/review.test.sh` passes: `check --feature` fails with no record, with
    a `changes needed` record, with `tests: red`, and after a new commit on the branch, and passes on
    a `ready`, green record for the head; a `ready` verdict whose `reviewed` is an older head, with
    green tests on the new head, fails; `bash tests/pr.test.sh` passes: `--ready` is refused with a pending task and
    without a ready feature review for the head, and with both marks the PR ready (the fake `gh`
    logs `pr ready`) with `## End check` in its body; `tests/run.sh` passes.

---

## Phase 7: User Story 5 - The existing gates and the release on the single PR (Priority: P2)

**Goal**: the release lists the feature PR; the gates already run in `pr.sh feature`.

**Independent Test**: quickstart L5 (release cases) and Q6.

- [ ] T010 [P] [US5] Key the release and the stats on the feature PR, in extension/scripts/implement.sh and extension/scripts/stats.sh (depends on T002, T005)
  - Comes from: FR-013, FR-015, US5 scenario 3, SC-004; research R10, R11
  - What: `release-plan`: PRs merged whose head starts with `<branch_prefix>/<NNN>-` (not
    `/<NNN>-t`), the merge commit of the feature PR as `M`; require the feature issue closed
    (`feature_issue` and one `gh issue view`); a legacy feature (`legacy_feature`) keeps today's
    path (task PRs, every task issue closed through `closed_issues`); patch bump when the feature
    PR's title starts with `fix`. `stats.sh`: group by the feature PR instead of task and spec PRs.
  - Impact: `tests/implement.test.sh` (release-plan cases); `tests/stats.test.sh`;
    `tests/static.test.sh` release-plan text; `docs/reference.md`.
  - Completed when: `bash tests/implement.test.sh` passes: a merged feature PR with its issue
    closed gives `RELEASE=bump … PRS=<that PR>`; its issue open gives no bump and says why; a fix
    feature gives a patch bump; a legacy feature with its task PRs merged and issues closed still
    gives `RELEASE=bump`; `bash tests/stats.test.sh` passes with one line per feature PR;
    `tests/run.sh` passes.

---

## Phase 8: User Story 6 - Moving to the new flow (Priority: P3)

**Goal**: the per-task modes are gone, and docs, help, levels, scaffolds and templates describe
only one PR per feature.

**Independent Test**: quickstart L8 and US6 scenario 3.

- [ ] T011 [US6] Remove pr.sh's task and spec modes, in extension/scripts/pr.sh (depends on T003, T004, T005, T009)
  - Comes from: FR-003, FR-012, FR-016, SC-005; research R9; plan "Design notes" 3
  - What: delete `pr.sh task` and `pr.sh spec`, the stacked-parent logic and the spec PR body
    (`pr_skips_base` stays in `lib.sh`: `level.sh` uses it for init's warning). Every
    `pr.sh task T001` call in `tests/pr.test.sh` becomes `pr.sh fix`, which runs the same arm, so
    every gate and review-record case keeps passing unchanged (SC-005), except these, named here: the
    dirty-tree cases get a body file (`fix` needs one); the task-branch refusal and the `Closes #N`
    cases go with task mode (T003 covers `Closes #N` for the feature PR); the spec and stacked
    cases go. `open_pr` keeps its draft branch for `feature` when the stacked-parent logic goes. `extension/scripts/guard.sh`'s block message names
    `pr.sh feature` and `pr.sh fix`; `extension/commands/analyzed.md` drops the level-`full` spec PR
    step; the header comments of `extension/scripts/mutants.sh` and `security-scan.sh` name
    `pr.sh feature`.
  - Impact: `tests/pr.test.sh`; `tests/guard.test.sh`; `tests/static.test.sh` checks of
    `analyzed.md`.
  - Completed when: `pr.sh task …` and `pr.sh spec …` exit non-zero with the usage error;
    `bash tests/pr.test.sh` passes with every former task-mode gate and review-record case running
    through `pr.sh fix`;
    `bash tests/guard.test.sh` passes with the new message; `tests/run.sh` passes.

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

- [ ] T013 [US6] Remove implement.sh's per-task actions, in extension/scripts/implement.sh (depends on T002, T004, T008, T012)
  - Comes from: FR-004, FR-016; research R7, R8
  - What: delete `restack`, `stack`, `move`, `check-copy` and their helpers, the task-branch
    `status`, `parallel_tasks` (its read and range check) and the slot arithmetic beyond "never list
    a running task again"; `review.sh`'s check-copy wording names `implement.sh check`.
  - Impact: `tests/implement.test.sh` (restack, stack, check-copy and task-branch status cases go);
    `tests/review.test.sh` (feature cases that built a check copy).
  - Completed when: `implement.sh <f> restack`, `stack`, `move` and `check-copy` exit non-zero with
    the usage error, and a `parallel_tasks: 9` line changes nothing (`tests/implement.test.sh`);
    `tests/run.sh` passes.

- [ ] T014 [P] [US6] Describe one issue, branch and PR per feature in the generated constitution text, templates and scaffolds, in extension/levels/lite.md (depends on T005, T013)
  - Comes from: FR-016, US6 scenario 3
  - What: the "Way of working" block of `extension/levels/lite.md` (the only level file with one;
    `standard.md` and `full.md` add rules with no task or PR bullet): one feature = one issue = one branch = one PR; a task is done when it lands on the feature
    branch with its review; the review bullet: each task's diff is reviewed before it lands, and a
    feature PR is marked ready only after its feature review, recorded for its head; any other PR
    goes through `pr.sh fix`; the PR merges once. `preset/templates/constitution-template.md`: the
    same. `extension/scaffold/*/.github/pull_request_template.md`: no per-task `Closes #`.
    `extension/scaffold/lite/.github/copilot-instructions.md`: a feature PR that closes the feature
    issue, no spec PR. `skills/init/SKILL.md` (its task-PR lines). `extension/scripts/level.sh`'s
    workflow warning ("never runs on the feature PR"). `extension/scripts/review.sh`'s comment on
    `outside --plan` (outside reviewers of the feature PR). `extension/extension.yml`'s
    description. The comment of `extension/scaffold/standard/.github/workflows/close-linked-issues.yml`
    (it now closes the feature issue). In the same task, run `level.sh` to regenerate this
    repository's own block in `.specify/memory/constitution.md` (never edited by hand), so the rules
    the next reviewer reads describe the new flow.
  - Impact: `tests/level.test.sh` (generated text and the warning); `tests/static.test.sh` (the
    warning wording); `tests/setup.test.sh` if it checks the scaffold text.
  - Completed when: `bash tests/level.test.sh` passes with the new "Way of working" text in a
    generated lite constitution and no "One task = one issue"; this repository's generated block
    says one PR per feature; `tests/run.sh` passes.

- [ ] T015 [US6] Rewrite the design, reference and security docs for one PR per feature, in docs/design.md, docs/reference.md and docs/security.md (depends on T013)
  - Comes from: FR-016, US6 scenario 3; constitution "Docs are the source of truth"
  - What: `docs/design.md`: replace the sections "One task = one issue = one branch = one PR", "The
    spec is its own PR" and "Parallel tasks, stacked PRs" with one section on one PR per feature
    (why: the merge loop; how: task refs, landing commits, per-task Opus review, end check, one
    record deciding the PR); `docs/reference.md`: every section that describes the per-task flow
    ("Stack detection", "Several features at once", "What happens automatically", "Mutation
    testing", "Terraform plan", "Measurements") and the "Configuration" table (remove `parallel_tasks` and `review_model`, add `task_rounds`,
    `issue_labels` default `type:feature`); `docs/security.md` "Before a PR opens" and review-hook
    rows (Opus only, one PR per feature); `docs/GUIDELINES.md` (its task-PR line).
  - Impact: `tests/static.test.sh` checks on these docs are updated to the new text.
  - Completed when: `bash tests/static.test.sh` passes with checks that design, reference and
    security name `pr.sh feature`, one issue per feature and Opus reviews, that reference has a
    `task_rounds` row, each seen failing on the old text; `tests/run.sh` passes.

- [ ] T016 [US6] Rewrite the README, help and examples for one PR per feature, in README.md, skills/help/SKILL.md and examples/ (depends on T015)
  - Comes from: FR-016, US6 scenario 3
  - What: `README.md` (the loop, the review model, the per-task PR lines); `skills/help/SKILL.md`;
    and the one negative check: a `tests/static.test.sh` case that runs `grep -rnE 'pr\.sh
    (task|spec)|branch\.sh [^ ]+ T[0-9]|restack|parallel_tasks|check-copy|review_model|task PR|spec
    PR|one task = one issue|one issue per task'` over `README.md docs skills agents extension preset
    hooks examples` and fails on any line outside one allow-list (release notes under
    `docs/releases/`, the history rows of `docs/GUARDRAILS.md`, the legacy R11 messages, the
    legacy release-plan text `implement.sh` keeps for per-task features, and the check itself); before it, the leftovers it would find are rewritten: `review_model()` in
    `lib.sh` becomes `reviewer_model()` (it returns `opus`; its caller in `review.sh` follows), and
    the comments in `lib.sh`, `review.sh`, `next.sh` and `stats.sh` that name task or spec PRs;
    `examples/README.md` and `examples/github/*` (one feature issue and one feature PR replace
    `issue-T001.md` and `task-pr-T001.md`; `spec-pr.md` is removed); remove `assets/flow-*.svg`
    that show task PRs, or redraw them with the README's new loop.
  - Impact: `tests/static.test.sh` README and help checks; `extension/scripts/lib.sh`,
    `review.sh`, `next.sh`, `stats.sh` (the renamed helper and comments); `/landspec:help` answers from these
    files.
  - Completed when: `bash tests/static.test.sh` passes with checks that README and help name
    `pr.sh feature`, one issue per feature and Opus reviews, and with the negative check, which is
    seen failing once with one old line put back (in a doc, and in a script comment); `tests/run.sh`
    passes.

---

## Dependencies & order

- T001 → T002 → T003; T007 is independent; T004 needs T002, T003, T007.
- T005 needs T001, T002; T006 needs T002; T008 needs T002, T004, T005; T009 needs T003, T008;
  T010 needs T002, T005.
- T011 needs T003, T004, T005, T009; T012 needs T011; T013 needs T002, T004, T008, T012; T014 needs
  T005, T013; T015 needs T013; T016 comes last.
- Build order on the single branch: T001, T007, T002, T003, T004, T005, T006, T008, T009, T010,
  T011, T012, T013, T014, T015, T016.

## Parallel opportunities

- T006, T007, T010 and T014 touch files their neighbours do not; they are marked `[P]`, but this
  feature is built one task at a time on one branch (research R7, R12).

## Implementation strategy

- MVP = US1 (T001–T004) plus T007: a feature builds on one branch into one draft PR with Opus
  reviews. US2 (one issue) and US4 (end check, ready PR) complete the flow; T011–T013 remove the
  per-task modes; US6 finishes the docs.
- Not a task: the constitution's **Project** paragraph is amended through `/speckit-constitution`
  in its own PR, merged before this feature's PR (plan, Complexity Tracking).
