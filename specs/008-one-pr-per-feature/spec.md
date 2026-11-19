# Feature Specification: One pull request per feature

**Feature Branch**: `008-one-pr-per-feature`

**Created**: 2026-11-18

**Status**: Draft (revised 2026-11-18)

**Input**: User description: "I don't want to create 1 issue per task and 1 PR per issue/task anymore. This takes too much time for reviewing, too complex and little advantages. The same flow as the original spec-kit, but 1 issue per feature/spec. Instead of a PR for each task, merging, coming back, implementing a new task in a loop, I want the feature on 1 PR only. On the execution of each feature a review runs with Claude Opus, and at the end the code is checked against the spec, plan and tasks, and the tests run. 1 PR to review, approve and merge."

**Revision (2026-11-18, the developer)**: remove the issues altogether, keep the process simpler and
more efficient, run the tasks in parallel by default when possible, and optimize the reviewer and
the security checks. So: no GitHub issue at all (not even one per feature), tasks run in parallel
by default, the plan review and the task review each run one pass with only serious findings
blocking, tests run once per tree, and the security scan and mutation testing run once per feature.

## Context

Today landspec gives every task of a feature its own GitHub issue, branch and pull request, plus a
separate spec PR for the spec, plan and tasks. A feature of eleven tasks means a spec PR, eleven
task PRs, and another spec PR each time the whole-feature check finds a gap, each one merged by
hand before the next run can go on. The developer spends most of the time going back and forth
between merges and reruns, and waiting on review rounds and scans that repeat on every task. This
feature replaces that with the spec-kit flow the developer already knows: one feature, one branch,
one pull request, reviewed and merged once, with no GitHub issue and every check run once.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A whole feature in one pull request (Priority: P1)

A developer plans a feature with spec-kit (specify, plan, tasks) and runs the implement step once.
Every task whose dependencies are done is built at the same time, each in its own copy, and lands on
the same feature branch as soon as it is reviewed. When the last one is done a single pull request
holds the spec, the plan, the tasks and all the code. The developer reviews, approves and merges
that one PR. Nothing has to be merged before implementation can start, and no run has to be
repeated because a PR was waiting.

**Why this priority**: it is the whole point of the change: the time lost today goes into the
loop of per-task PRs and merges.

**Independent Test**: plan a small feature with three tasks in a test repository, run implement
once, and confirm that exactly one branch and one open PR exist for it, that the PR contains the
spec folder and the code of all three tasks, and that no other PR, task branch or issue was created.

**Acceptance Scenarios**:

1. **Given** a feature with a spec, plan and tasks on its feature branch, **When** the developer
   runs implement, **Then** every task whose dependencies are done starts at once (up to the
   configured limit), each lands on that branch as its own merge, and one PR is opened (or
   updated) for the feature.
2. **Given** a feature whose PR is already open, **When** implement runs again (after a fix or a
   new task), **Then** the same PR is updated; no second PR is opened.
3. **Given** a task depends on another, **When** implement runs, **Then** it starts only once the
   other task has landed, and no task waits for any merge of a PR.
4. **Given** two tasks built at the same time change the same lines, **When** the second one lands,
   **Then** the landing stops, that task gets one round to take in the feature branch and resolve,
   is checked again, and lands; a second conflict marks it failed.
5. **Given** the PR is opened, **When** the developer reads it, **Then** its body lists every task
   with its state, the review results (with the low findings), the end check's result and the test
   evidence.

---

### User Story 2 - Progress without issues (Priority: P1)

landspec creates no GitHub issue for a feature or its tasks. Progress is read from the feature
branch (a task is done when its landing commit is there) and shown by the next-task command and in
the PR's task table.

**Why this priority**: issues per task were half the overhead, and one issue per feature would only
repeat what the PR's task table already shows; the developer asked for no issues at all.

**Independent Test**: run the tasks step and implement on a feature with five tasks and confirm
that no issue is created, that the next-task command shows each task's state, and that the PR body
lists the five tasks.

**Acceptance Scenarios**:

1. **Given** a new tasks.md, **When** the tasks step finishes, **Then** the plan review runs once and
   the spec folder is committed on the feature branch; no issue is created.
2. **Given** a task is built and passes its review, **When** progress is read (by the developer or
   by the next-task command), **Then** that task shows as done from its landing commit.
3. **Given** the feature PR is open, **When** the developer reads it, **Then** its task table is the
   progress view: each task, its state and its landing commit.

---

### User Story 3 - One Opus review per plan and per task (Priority: P1)

Before the build, one independent Opus review reads the spec, the plan and the tasks; only a high
finding stops the build. As each task is built, one independent Opus review reads that task's change
before it lands; only a high or medium finding stops it, and the task gets one fix round, checked
by a review of the fix alone. A task still blocked after that is marked failed, and every task that
does not depend on it goes on.

**Why this priority**: one large PR is only safe to merge if each part was reviewed as it was
built; one pass with a clear bar keeps that quality without rounds that do not change the outcome.

**Independent Test**: build a feature with one task that has a planted defect and confirm that the
Opus review of that task reports it, that one fix commit follows on its task ref, that a review of
the fix runs, and that the task lands only after; then plant a defect the fix does not cure and
confirm the task is marked failed while an independent task still lands.

**Acceptance Scenarios**:

1. **Given** the tasks step finished, **When** the plan review runs, **Then** it runs once; the
   build may start when it has no high finding, and its medium and low findings are shown to the
   developer without forcing another round.
2. **Given** a task has just been built and its tests pass, **When** its review runs, **Then** it
   is done by a fresh reviewer on Claude Opus, which sees the task's change and the code around
   it, not the builder's reasoning.
3. **Given** the task review has a high or medium finding, **When** the fix is made, **Then** it is
   committed on the task's ref and only the fix is reviewed again (with the earlier findings).
4. **Given** the task review has only low findings, **When** it is recorded, **Then** the task lands
   and its low findings are listed in the PR body.
5. **Given** a task is still blocked after its one fix round, **When** that review is recorded,
   **Then** the task is marked failed with the review's findings, tasks that depend on it do not
   start, independent tasks go on, and the run report lists it for the developer.
6. **Given** a reviewer launch asks for a model other than Opus, **When** it is started, **Then** it
   is refused.

---

### User Story 4 - The end check before the PR is ready (Priority: P2)

When every task is built and reviewed, landspec checks the whole feature once, on the feature
branch: the full test suite runs, and a fresh Opus reviewer reads the code against the spec, the
plan and the tasks and reports each requirement, scenario and success criterion as met, not met or
not verifiable. Anything not met becomes a new task of the same feature, built in the same run, and
checked again; the PR becomes ready for review only when the check passes or its attempts are used
up.

**Why this priority**: it replaces the whole-feature check and its gap-task spec PRs with a check
that needs no merge.

**Independent Test**: build a feature where one requirement is left out on purpose and confirm that
the end check reports it not met, that a new task for it is added to the same tasks.md and built
on the same branch, and that the check then passes and the PR is marked ready.

**Acceptance Scenarios**:

1. **Given** every task is built and reviewed, **When** the end check runs, **Then** the full test
   suite runs on the branch and the feature review reports each item of the spec.
2. **Given** the end check finds items not met, **When** it finishes, **Then** a new task per item is
   appended to tasks.md on the same branch, given one plan review pass, built, reviewed, and the end
   check runs again; no separate spec PR is opened.
3. **Given** the end check passes, **When** the PR is updated, **Then** it leaves draft and is ready
   for review, with the check's report in its body.
4. **Given** the end check is still failing after the allowed attempts, **When** the limit is
   reached, **Then** the PR stays a draft, its body lists what is not met, and the developer is told
   what is left.

---

### User Story 5 - The existing gates hold, each run once (Priority: P2)

The checks landspec runs today before a PR opens (tests green, the security scan of the changed
files, the Terraform plan gate where it applies, mutation testing where configured, secret checks
on every commit and push, the guard on every command) all still run, each once: the tests once per
tree, reused by every step that needs them; the security scan and mutation testing once on the
feature's whole diff, right before the PR is marked ready. The audit and the release run after the
feature PR is merged, as today.

**Why this priority**: the change must make the flow faster without removing a safety check.

**Independent Test**: on a feature with a failing test, a changed workflow file and a `.tf` change,
confirm that the PR is refused while the test is red, that a tree already tested green is not
tested again, and that the scan and the plan gate report on the feature's whole diff before the PR
is marked ready.

**Acceptance Scenarios**:

1. **Given** the feature's tests are red, **When** the PR would open, **Then** it is refused, as
   today.
2. **Given** a tree was tested green by the task's builder, **When** the main session or the PR step
   needs that tree tested, **Then** the recorded run is reused and the tests do not run again.
3. **Given** the feature's diff changes files the scanners cover, **When** the PR is marked ready,
   **Then** the scan of the whole feature diff ran once and is in its body; a high finding refuses
   the ready step, other findings and scanners that are not installed are listed.
4. **Given** the feature PR is merged, **When** implement runs again, **Then** the audit and release
   steps run as they do today, with the feature PR as the release's PR.

---

### User Story 6 - Moving to the new flow (Priority: P3)

A developer who already uses landspec upgrades. A feature already in progress under the old flow
(task issues, task PRs open) is reported with what to do to finish it; every new feature uses the
new flow. The documentation, the help and the scaffolded constitution describe only the new flow.

**Why this priority**: needed for the upgrade, but it affects only features in flight at that
moment.

**Independent Test**: upgrade a project with one feature that has open task PRs and one new
feature, and confirm that the first is reported with what to do and the second runs as one PR.

**Acceptance Scenarios**:

1. **Given** a feature whose tasks already have issues or PRs, **When** the developer runs
   implement or next after the upgrade, **Then** landspec says the feature was started under the
   old flow and what to do (merge its open PRs, or move its remaining tasks to one branch), and
   never creates per-task issues or PRs for it again.
2. **Given** a new feature, **When** its tasks are generated, **Then** only the new flow is used.
3. **Given** the upgrade, **When** the developer reads the README, the reference, the help or a new
   project's constitution, **Then** none of them describes GitHub issues for tasks or features, or
   one PR per task.

### Edge Cases

- A feature with a single task: one branch, one PR, as for any feature.
- More startable tasks than the parallel limit: the first ones in task order start, the rest start
  as slots free up.
- A task's tests stay red after its builder says it is done twice: the task is marked failed, the
  tasks that depend on it do not start, independent tasks still run, and the PR stays a draft that
  lists the failed task.
- Two parallel tasks change the same lines: the one that lands second gets one conflict round
  (US1 scenario 4). A merge that is clean but breaks the tests is caught by the end check's test run
  and becomes a gap task.
- The run stops midway (the session ends, a tool crashes): the next run reads each task's state from
  the branch's commits and the review records and goes on; a task whose ref exists resumes on it;
  no task is built twice.
- The feature branch falls behind the base branch while tasks are built: the branch is updated from
  the base before the end check; a conflict stops the run and is reported with its files.
- The developer pushes their own commit to the feature branch between runs: it is kept, and the
  next review and the end check see it.
- Opus is not available to the session (model not offered, quota): the review does not silently fall
  back to another model; the run stops and says which review could not run.
- A security scanner or the mutation tool is not installed: it is listed in the PR body and never
  blocks.
- A project on level lite (no CI gate, no branch protection): one PR per feature still, with the same
  per-task review and end check.
- A large feature: the PR keeps each task as its own landing merge, so the developer can read it
  task by task.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: landspec MUST NOT create any GitHub issue for a feature or its tasks; progress MUST be
  shown by the next-task command and the PR's task table. *(Superseded 2026-11-18 by the developer:
  replaces "one issue per feature".)*
- **FR-002**: After the tasks step (and after converge), landspec MUST run the plan review once
  (FR-019) and commit the spec folder on the feature branch. *(Superseded 2026-11-18: replaces
  "update the feature issue".)*
- **FR-003**: A feature MUST be built on one branch, holding its spec folder (spec, plan, tasks and
  the other planning files) and the code of all its tasks; landspec MUST NOT create a branch or a PR
  per task, and MUST NOT require a separate spec PR to be merged before implementation.
- **FR-004**: The implement step MUST build the feature's tasks on the feature branch, each landing
  as one merge whose message names the task, without waiting for any merge of a PR; tasks run in
  parallel by default (FR-018).
- **FR-005**: After each task is built and its tests pass, a fresh reviewer running on Claude Opus
  MUST review that task's change before it lands; a reviewer launch on any other model MUST be
  refused.
- **FR-006**: When a task's review has a high or medium finding, the task MUST get one fix round,
  committed on its task ref and checked by a review of the fix alone (FR-020); when it is still
  blocked after that, the task MUST be marked failed, the tasks that depend on it MUST NOT start,
  and every independent task MUST go on.
- **FR-007**: A task MUST count as done when its landing commit is on the feature branch (built,
  tests green, review without a high or medium finding); the progress shown by the next-task and
  implement commands MUST come from this state.
- **FR-008**: When every task is done, landspec MUST run an end check on the feature branch: the full
  test suite, then a feature review that reports each functional requirement, scenario and success
  criterion of the spec as met, not met or not verifiable, against the spec, the plan and the tasks.
- **FR-009**: Each item the end check reports not met MUST become a new task appended to the same
  tasks.md on the same branch, given one plan review pass, then built, reviewed and checked again,
  without a separate spec PR; the end check MUST stop after a configurable number of attempts.
- **FR-010**: landspec MUST open one PR per feature, as a draft while tasks or the end check are
  pending, and mark it ready for review only when every task is done and the end check passed;
  later runs MUST update the same PR.
- **FR-011**: The feature PR's body MUST show every task with its state, the result of each task's
  review and its low findings, the end check's report, the test evidence and the scanner results.
- **FR-012**: The gates that apply before a PR opens today (green tests, the security scan of the
  changed files, the Terraform plan gate where it applies, mutation testing where configured, the
  refusal of a PR on red checks) MUST apply to the feature PR's whole diff before it is marked ready,
  the scan and the mutation testing once (FR-022); the secret checks and the guard MUST keep running
  on every commit, push and command.
- **FR-013**: After the feature PR is merged, the audit and release steps MUST run as they do today,
  taking the feature PR as the PR the release covers.
- **FR-014**: A run that stops midway MUST be resumable: the next run reads each task's state from
  the feature branch and the review records and goes on, without building a done task again.
- **FR-015**: For a feature started under the per-task flow (task issues or task PRs exist),
  landspec MUST say so and what to do, and MUST NOT create new per-task issues or PRs for it.
- **FR-016**: landspec MUST remove the per-task flow and the issues: per-task issues, the issue
  step, per-task branches and PRs, stacked PRs, and the gap-task spec PRs; its documentation, help,
  reference and scaffolded constitution MUST describe only the one-PR-per-feature flow.
- **FR-017**: Every rule this feature adds or changes MUST have a test that was seen failing with
  the rule disabled, and the suite MUST pass on bash 3.2 and bash 5 (constitution).
- **FR-018**: Every task whose `depends on` tasks are done and which is not done, failed or in flight
  MUST start at once, each from the feature head in its own copy, up to a configurable limit
  (default 4); tasks MUST land as each becomes ready, in any order; a landing that conflicts MUST
  stop and give that task one round to take in the feature branch and resolve, checked by a review
  of that round; a second conflict marks it failed.
- **FR-019**: The plan review MUST run once per plan; it MUST block the build only on a high
  finding, and MUST list medium and low findings for the developer without forcing another round.
  Gap tasks from the end check get the same single pass on their new lines.
- **FR-020**: The task review MUST block landing only on a high or medium finding; low findings MUST
  go to the PR body. The review of a fix round MUST always read only the fix (a delta), whatever its
  size.
- **FR-021**: Tests MUST run at most once per tree and test command: a green run recorded by the
  task's builder MUST be reused by the main session and the PR step, never run again on the same
  tree.
- **FR-022**: The security scan of the changed files and the mutation testing MUST run once on the
  whole feature diff (from the base), right before the PR is marked ready, not per task; a scanner
  or tool that is not installed MUST be listed, never blocking; a high finding MUST refuse the ready
  step, other findings MUST be listed in the PR body.

### Key Entities

- **Feature**: one spec folder (spec, plan, tasks and the other planning files); has one branch and
  one PR, and no issue.
- **Task**: one line of tasks.md; built on its own task ref from the feature head, in parallel with
  the other startable tasks; its state is pending, waiting, building, built, in review, changes,
  done or failed; done means its landing commit is on the feature branch.
- **Plan review**: the single Opus review of spec, plan and tasks; passes without a high finding.
- **Task review**: the Opus review of one task's change, with at most one fix round reviewed as a
  delta; blocks on a high or medium finding; recorded so a later run can see it.
- **Test record**: the recorded green run of the test command on one tree, reused by every later
  step that needs that tree tested.
- **End check**: the full test run and the feature review of the whole branch against the spec,
  plan and tasks; its not-met items become new tasks of the same feature.
- **Feature PR**: the single PR of a feature; draft until every task is done and the end check
  passed; its body carries the task states, reviews, low findings, end check, tests and scans.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A feature of N tasks produces exactly 1 pull request and 0 issues, for any N, including
  when the end check adds tasks (today: N issues and N task PRs, plus one spec PR per round with
  gaps).
- **SC-002**: From tasks generated to a PR ready for review, the developer merges nothing; a feature
  needs exactly one human merge, and implement is run once more only for each time a run was
  interrupted.
- **SC-003**: Every task in a merged feature PR has a recorded Opus review with no high or medium
  finding, and the PR carries an end check report with no not-met item, or the PR stayed a draft.
- **SC-004**: A feature that took a spec PR, eleven task PRs, three gap spec PRs and a config PR
  under the old flow (feature 006 in this repository) would take one PR and one merge.
- **SC-005**: No safety check is lost: every gate listed in FR-012 runs on every feature PR before
  it is ready, and the existing tests for those gates still pass.
- **SC-006**: In a feature with K independent tasks, min(K, the parallel limit) builders run at the
  same time.
- **SC-007**: Each tree is tested at most once per test command; the security scan and the mutation
  testing run once per feature head marked ready; each task gets at most two reviews (one full, one
  delta), plus one delta for a conflict round.

## Assumptions

- "The same flow as the original spec-kit" means specify, plan, tasks and implement as spec-kit
  defines them, with landspec adding the single branch and PR, the reviews, the end check and the
  existing gates; spec-kit's own commands are not changed.
- The feature branch is created when the spec is written, so the spec folder lives on it from the
  start and the base branch receives the feature only through its PR.
- Tasks are built in parallel by default, each on its own local task ref in its own copy, and land
  on the single branch as they become ready. *(Superseded 2026-11-18 by the developer: replaces "one
  at a time".)* The limit keeps the `parallel_tasks` key (default 4), which no longer means stacked
  PRs.
- The task review and the end check's feature review both run on Claude Opus; the builders keep the
  model setting they have today.
- Fix rounds per task: `task_rounds`, default 2 (the first review and one delta). End-check
  attempts: `feature_rounds`, default 3, as today.
- The plan review before implementation is kept as one pass, and it gates the implement step on the
  feature branch instead of issue creation and a spec PR.
- The audit and release behave as today; only the source of the release's PR list changes (one PR
  per feature, no issue to close).
- Per-task PRs already open in other projects are finished under the old flow; this feature does not
  convert existing PRs.
- This repository's own feature 006 finishes its 2.9.0 release under the current flow before this
  feature is implemented.
