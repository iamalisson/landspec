# Feature Specification: One issue and one pull request per feature

**Feature Branch**: `008-one-pr-per-feature`

**Created**: 2026-11-18

**Status**: Draft

**Input**: User description: "I don't want to create 1 issue per task and 1 PR per issue/task anymore. This takes too much time for reviewing, too complex and little advantages. The same flow as the original spec-kit, but 1 issue per feature/spec. Instead of a PR for each task, merging, coming back, implementing a new task in a loop, I want the feature on 1 PR only. On the execution of each feature a review runs with Claude Opus, and at the end the code is checked against the spec, plan and tasks, and the tests run. 1 PR to review, approve and merge."

## Context

Today landspec gives every task of a feature its own GitHub issue, branch and pull request, plus a
separate spec PR for the spec, plan and tasks. A feature of eleven tasks means a spec PR, eleven
task PRs, and another spec PR each time the whole-feature check finds a gap, each one merged by
hand before the next run can go on. The developer spends most of the time going back and forth
between merges and reruns. This feature replaces that with the spec-kit flow the developer already
knows: one feature, one issue, one branch, one pull request, reviewed and merged once.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A whole feature in one pull request (Priority: P1)

A developer plans a feature with spec-kit (specify, plan, tasks) and runs the implement step once.
Every task is built on the same feature branch, one after another, and when the last one is done a
single pull request holds the spec, the plan, the tasks and all the code. The developer reviews,
approves and merges that one PR. Nothing has to be merged before implementation can start, and no
run has to be repeated because a PR was waiting.

**Why this priority**: it is the whole point of the change: the time lost today goes into the
loop of per-task PRs and merges.

**Independent Test**: plan a small feature with three tasks in a test repository, run implement
once, and confirm that exactly one branch and one open PR exist for it, that the PR contains the
spec folder and the code of all three tasks, and that no other PR or task branch was created.

**Acceptance Scenarios**:

1. **Given** a feature with a spec, plan and tasks on its feature branch, **When** the developer
   runs implement, **Then** every task is built in order on that branch, each as its own commit,
   and one PR is opened (or updated) for the feature.
2. **Given** a feature whose PR is already open, **When** implement runs again (after a fix or a
   new task), **Then** the same PR is updated; no second PR is opened.
3. **Given** a task depends on an earlier one, **When** implement runs, **Then** the earlier task
   is built first, and no task waits for any merge.
4. **Given** the PR is opened, **When** the developer reads it, **Then** its body lists every task
   with its state, the review results, the end check's result and the test evidence.

---

### User Story 2 - One issue per feature (Priority: P1)

When the tasks are generated, landspec creates one GitHub issue for the feature, not one per task.
The issue lists the feature's tasks as a checklist, so progress is visible in one place, and the
feature's PR closes it when merged.

**Why this priority**: issues per task are the other half of the overhead; the developer asked for
one issue per feature explicitly.

**Independent Test**: run the tasks step on a feature with five tasks and confirm that exactly one
issue exists for it, that it lists the five tasks, and that merging the feature PR closes it.

**Acceptance Scenarios**:

1. **Given** a new tasks.md, **When** the tasks step finishes, **Then** one issue exists for the
   feature, titled after it, with one checklist line per task.
2. **Given** the feature issue exists, **When** the tasks step runs again (tasks added or
   changed), **Then** the same issue is updated; no second issue is created.
3. **Given** the feature PR is merged, **When** GitHub processes it, **Then** the feature issue is
   closed.
4. **Given** a task is built and passes its review, **When** progress is read (by the developer or
   by the next-task command), **Then** that task shows as done without any issue being closed for
   it.

---

### User Story 3 - An Opus review after each task (Priority: P1)

As each task is built, an independent reviewer running on Claude Opus reviews that task's change
on the feature branch before the next task starts. When it asks for changes, they are made on the
same branch and reviewed again, until it is satisfied or the attempts run out.

**Why this priority**: one large PR is only safe to merge if each part was reviewed as it was
built; the per-task review keeps the quality the per-task PRs gave.

**Independent Test**: build a feature with one task that has a planted defect and confirm that
the Opus review of that task reports it, that a fix commit follows on the same branch, that the
review runs again on the fix, and that the next task starts only after.

**Acceptance Scenarios**:

1. **Given** a task has just been built and its tests pass, **When** its review runs, **Then** it
   is done by a fresh reviewer on Claude Opus, which sees the task's change and the code around
   it, not the builder's reasoning.
2. **Given** the review asks for changes, **When** the fix is made, **Then** it is committed on the
   feature branch and reviewed again (the fix, plus the earlier findings).
3. **Given** a task's review still asks for changes after the allowed fix rounds, **When** the
   limit is reached, **Then** the task is marked failed with the review's findings, later tasks
   that depend on it do not start, and the run report says so.
4. **Given** a reviewer launch asks for a model other than Opus, **When** it is started, **Then** it
   is refused.

---

### User Story 4 - The end check before the PR is ready (Priority: P2)

When every task is built and reviewed, landspec checks the whole feature once, on the feature
branch: the full test suite runs, and a fresh reviewer reads the code against the spec, the plan
and the tasks and reports each requirement, scenario and success criterion as met, not met or not
verifiable. Anything not met is fixed on the same branch, as new tasks of the same feature, and
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
   appended to tasks.md on the same branch, built, reviewed, and the end check runs again; no
   separate spec PR is opened.
3. **Given** the end check passes, **When** the PR is updated, **Then** it leaves draft and is ready
   for review, with the check's report in its body.
4. **Given** the end check is still failing after the allowed attempts, **When** the limit is
   reached, **Then** the PR stays a draft, its body lists what is not met, and the developer is told
   what is left.

---

### User Story 5 - The existing gates still hold on the single PR (Priority: P2)

The checks landspec runs today before a PR opens (tests green, the security scan of the changed
files, the Terraform plan gate where it applies, mutation testing where configured, secret checks
on every commit and push, the guard on every command) all run on the feature's PR, once for its
whole diff. The audit and the release run after the feature PR is merged, as today.

**Why this priority**: the change must make the flow faster without removing a safety check.

**Independent Test**: on a feature with a failing test, a changed workflow file and a `.tf` change,
confirm that the PR is refused while the test is red, and that the scan and the plan gate report on
the feature's whole diff.

**Acceptance Scenarios**:

1. **Given** the feature's tests are red, **When** the PR would open, **Then** it is refused, as
   today.
2. **Given** the feature's diff changes files the scanners cover, **When** the PR opens, **Then**
   the scan of the whole feature diff is in its body.
3. **Given** the feature PR is merged, **When** implement runs again, **Then** the audit and release
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
   project's constitution, **Then** none of them describes one issue or one PR per task.

### Edge Cases

- A feature with a single task: one issue, one branch, one PR, as for any feature.
- A task's tests stay red after its builder says it is done twice: the task is marked failed, the
  tasks that depend on it do not start, independent tasks still run, and the PR stays a draft that
  lists the failed task.
- The run stops midway (the session ends, a tool crashes): the next run reads each task's state from
  the branch's commits and the review records and goes on from the first task not done; no task is
  built twice.
- The feature branch falls behind the base branch while tasks are built: the branch is updated from
  the base before the end check; a conflict stops the run and is reported with its files.
- The developer pushes their own commit to the feature branch between runs: it is kept, and the
  next review and the end check see it.
- Opus is not available to the session (model not offered, quota): the review does not silently fall
  back to another model; the run stops and says which review could not run.
- The tasks step runs again after the feature issue was edited by hand on GitHub: the checklist is
  rewritten from tasks.md (as task issues are rewritten today) and the developer is told.
- A project on level lite (no CI gate, no branch protection): one PR per feature still, with the same
  per-task review and end check.
- A large feature: the PR keeps each task as separate commits, so the developer can read it task by
  task.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: After the tasks step, landspec MUST create exactly one GitHub issue per feature,
  listing every task of tasks.md as a checklist line, and MUST NOT create an issue per task.
- **FR-002**: Running the tasks step again MUST update the feature's existing issue (checklist and
  body) instead of creating another one.
- **FR-003**: A feature MUST be built on one branch, holding its spec folder (spec, plan, tasks and
  the other planning files) and the code of all its tasks; landspec MUST NOT create a branch or a PR
  per task, and MUST NOT require a separate spec PR to be merged before implementation.
- **FR-004**: The implement step MUST build the feature's tasks in dependency order on the feature
  branch, each as one or more commits whose message names the task, without waiting for any merge.
- **FR-005**: After each task is built and its tests pass, a fresh reviewer running on Claude Opus
  MUST review that task's change before the next task starts; a reviewer launch on any other model
  MUST be refused.
- **FR-006**: When a task's review asks for changes, the fix MUST be committed on the feature branch
  and reviewed again; after a configurable number of fix rounds still asking for changes, the task
  MUST be marked failed and the tasks that depend on it MUST NOT start.
- **FR-007**: A task MUST count as done when it is built, its tests pass and its review is ready; the
  progress shown by the next-task and implement commands MUST come from this state, not from closed
  issues.
- **FR-008**: When every task is done, landspec MUST run an end check on the feature branch: the full
  test suite, then a feature review that reports each functional requirement, scenario and success
  criterion of the spec as met, not met or not verifiable, against the spec, the plan and the tasks.
- **FR-009**: Each item the end check reports not met MUST become a new task appended to the same
  tasks.md on the same branch, then built, reviewed and checked again, without a separate spec PR;
  the end check MUST stop after a configurable number of attempts.
- **FR-010**: landspec MUST open one PR per feature, as a draft while tasks or the end check are
  pending, and mark it ready for review only when every task is done and the end check passed;
  later runs MUST update the same PR.
- **FR-011**: The feature PR's body MUST show every task with its state, the result of each task's
  review, the end check's report, the test evidence and the scanner results, and MUST close the
  feature issue when merged.
- **FR-012**: The gates that apply before a PR opens today (green tests, the security scan of the
  changed files, the Terraform plan gate where it applies, mutation testing where configured, the
  refusal of a PR on red checks) MUST apply to the feature PR's whole diff; the secret checks and the
  guard MUST keep running on every commit, push and command.
- **FR-013**: After the feature PR is merged, the audit and release steps MUST run as they do today,
  taking the feature PR as the PR the release covers.
- **FR-014**: A run that stops midway MUST be resumable: the next run reads each task's state from
  the feature branch and the review records and goes on from the first task not done, without
  building a done task again.
- **FR-015**: For a feature started under the per-task flow (task issues or task PRs exist),
  landspec MUST say so and what to do, and MUST NOT create new per-task issues or PRs for it.
- **FR-016**: landspec MUST remove the per-task flow: per-task issues, per-task branches and PRs,
  stacked PRs, and the gap-task spec PRs; its documentation, help, reference and scaffolded
  constitution MUST describe only the one-PR-per-feature flow.
- **FR-017**: Every rule this feature adds or changes MUST have a test that was seen failing with
  the rule disabled, and the suite MUST pass on bash 3.2 and bash 5 (constitution).

### Key Entities

- **Feature**: one spec folder (spec, plan, tasks and the other planning files); has one issue, one
  branch and one PR.
- **Feature issue**: the GitHub issue of a feature; holds the task checklist; closed by the feature
  PR's merge.
- **Task**: one line of tasks.md; built on the feature branch; its state is pending, built, in
  review, done or failed; done means built, tests green and review ready.
- **Task review**: the Opus review of one task's change, with its fix rounds and its final
  assessment; recorded so a later run can see it.
- **End check**: the full test run and the feature review of the whole branch against the spec,
  plan and tasks; its not-met items become new tasks of the same feature.
- **Feature PR**: the single PR of a feature; draft until every task is done and the end check
  passed; its body carries the task states, reviews, end check, tests and scans.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A feature of N tasks produces exactly 1 issue and 1 pull request, for any N, including
  when the end check adds tasks (today: N issues and N task PRs, plus one spec PR per round with
  gaps).
- **SC-002**: From tasks generated to a PR ready for review, the developer merges nothing; a feature
  needs exactly one human merge, and implement is run once more only for each time a run was
  interrupted.
- **SC-003**: Every task in a merged feature PR has a recorded Opus review whose final assessment is
  ready, and the PR carries an end check report with no not-met item, or the PR stayed a draft.
- **SC-004**: A feature that took a spec PR, eleven task PRs, three gap spec PRs and a config PR
  under the old flow (feature 006 in this repository) would take one PR and one merge.
- **SC-005**: No safety check is lost: every gate listed in FR-012 runs on every feature PR, and the
  existing tests for those gates still pass.

## Assumptions

- "The same flow as the original spec-kit" means specify, plan, tasks and implement as spec-kit
  defines them, with landspec adding the feature issue, the single branch and PR, the reviews, the
  end check and the existing gates; spec-kit's own commands are not changed.
- The feature branch is created when the spec is written, so the spec folder lives on it from the
  start and the base branch receives the feature only through its PR.
- Tasks are built one at a time on the single branch, in dependency order; parallel builders in
  separate copies are dropped, because they need per-task branches. Speed comes from removing the
  merge loop, not from parallel builds.
- The task review and the end check's feature review both run on Claude Opus; the builders keep the
  model setting they have today.
- The fix rounds per task and the end-check attempts keep today's defaults and config keys (3 rounds
  for the end check), applied to the new flow.
- The plan review before implementation is kept, but it gates the implement step on the feature
  branch instead of issue creation and a spec PR.
- The audit and release behave as today; only the source of the release's PR list changes (one PR
  per feature).
- Per-task PRs already open in other projects are finished under the old flow; this feature does not
  convert existing PRs.
- This repository's own feature 006 finishes its 2.9.0 release under the current flow before this
  feature is implemented.
