# Feature Specification: Resolve the open issues (#184, #185, #186)

**Feature Branch**: `spec/005-resolve-open-issues`

**Created**: 2026-11-16

**Status**: Draft

**Input**: User description: "lets resolve all the issues at https://github.com/iamalisson/landspec/issues/". On 2026-11-16 two issues are open: #185 (a dependency found after the issues exist cannot be added without rewriting the linked task line) and #184 (tool pins behind: osv-scanner, semgrep, trivy). Added the same day (user): #186 (review: `record --plan` accepts an old report after `tasks.md` changed).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add a dependency to a task that already has its issue (Priority: P1)

A developer's tasks already have their GitHub issues (each task line ends in `— #N`). A later
review shows that one task also depends on another one. Today the rules forbid editing a linked
task line, and the line is the only place a dependency is read from. So the developer either
breaks the rule or leaves the dependency out. Breaking the rule has side effects too: when the
line has no ` in <path>` part, the task's summary still includes the `(depends on …)` clause,
so the issue title, the branch name and the text `next` shows all change when a dependency is
added. If an earlier issue run failed before it wrote `— #N` back, the next run then creates a
duplicate issue.

With this feature the developer may change the `(depends on …)` clause of a linked task, runs
the issue sync, and the same issue's body follows. The issue title, the branch name and the text
`next` shows stay the same.

**Why this priority**: it is a reported bug, it blocks a normal step of the workflow (a review
finding a missing dependency), and it can create a duplicate issue.

**Independent Test**: link a task such as `T007 Show the class (depends on T004)` to an issue,
change it to `(depends on T004, T005)`, run the sync, and check that the same issue's body changed,
its title did not, no new issue was created, and the task's branch name is the same as before.

**Acceptance Scenarios**:

1. **Given** a task line, **When** its summary is computed with no dependency clause, with
   `(depends on T004)`, or with `(depends on T004, T005)`, and with or without ` in <path>`,
   **Then** the summary is the same in all cases.
2. **Given** a linked task (`— #N`) whose dependency clause changes, **When** the plan review is
   run again and recorded and the issue sync runs, **Then** the body of issue #N shows the new
   dependencies, its title is unchanged, and no issue is created. Without that new review the sync
   is refused, as for any plan change.
3. **Given** a task whose issue was created but whose `— #N` was never written back, and whose
   dependency clause changed afterwards, **When** the issue run runs again, **Then** it finds
   the existing open issue by title, reports it as existing, and creates no duplicate.
4. **Given** a task that has not started, **When** it gains a dependency, **Then** the branch
   name landspec gives it does not change.
5. **Given** the rules that tell Claude how to handle linked tasks (every copy of the issues
   command and the parallel implement skill), **When** they are read, **Then** they allow changing
   only the `(depends on …)` clause of a linked line, followed by a sync, and still forbid
   renumbering or changing the description.

---

### User Story 2 - Scanner pins on current, settled releases (Priority: P2)

A developer installs landspec and gets CI scans. Today the pinned osv-scanner (2.7.0), semgrep
(1.183.0) and trivy (0.76.1) are older than the latest releases (2.7.1, 1.185.0, 0.76.2). With
this feature each pin moves to a newer release that has been out for a few weeks, together with
its verified checksum or image digest.

**Why this priority**: it is upkeep, not a broken flow; the older versions still work.

**Independent Test**: read the pins file and check that each of the three versions is the newest
release at least a few weeks old, and that its checksum or digest matches the one the release
publishes.

**Acceptance Scenarios**:

1. **Given** the pins file, **When** a bump is done, **Then** each bumped tool names a release
   out at least three weeks, with the matching SHA-256 (or, for semgrep, the matching image
   digest); on 2026-11-16 no release qualifies, so no pin moves in this feature.
2. **Given** the project copy of the extension (`.specify/extensions/landspec/`), **When** the
   test suite runs, **Then** it agrees with the extension's own pins, and the drift checks pass.
3. **Given** the weekly pin check, **When** a tool's only newer releases are younger than the age
   rule, **Then** it reports nothing behind and opens no issue; it reports a release only once it
   is old enough to bump to. (Added in planning: #184 was opened for releases 6 to 11 days old,
   which the rule forbids bumping to.)

---

### User Story 3 - A plan review counts only for the text it read (Priority: P1)

A developer records a plan review that ended "ready", then edits `tasks.md` (say, to fix the
round's Low findings). Today recording the same report again passes, because the plan's state is
taken when the report is recorded, not when the reviewer read it, and plan edits stay uncommitted
until the spec PR, so no commit pins the text either. The issues and the spec PR then go out with
text no reviewer read. In the reported case, a new round found a Medium in exactly that edited text.

With this feature the reviewer writes the state of the plan it read into its report, and recording
refuses a report whose state is missing or differs from the current plan, the same way a branch
review must name the commit it reviewed.

**Why this priority**: it is a hole in a gate landspec promises ("no PR opens without a review of
the exact content"), and it let a real defect through to the edge of the issues.

**Independent Test**: record a ready plan review, edit a sub-bullet in `tasks.md`, record the same
report again, and see it refused with "the plan changed since this review: run the review again";
append only ` — #N` to a task line instead, and see it still accepted.

**Acceptance Scenarios**:

1. **Given** a plan review report that states the plan state it read, **When** it is recorded and
   the plan is unchanged, **Then** it is recorded as before.
2. **Given** a recorded ready report, **When** `plan.md` or `tasks.md` changes and the same report
   is recorded again, **Then** recording refuses with "the plan changed since this review: run the
   review again", and the plan gate does not pass.
3. **Given** a report with no plan state line, **When** it is recorded, **Then** recording refuses
   and says the reviewer must state it.
4. **Given** a change that only appends or removes ` — #N` on task lines (what the issue run
   does), **When** the report is recorded, **Then** it still matches.
5. **Given** the reviewer's instructions for a plan review, **When** the reviewer finishes, **Then**
   its report carries the plan state, printed by the same command the gate uses, run against the
   plan it read.

---

### Edge Cases

- A task line with ` in <path>` and a dependency clause: the summary is cut at ` in ` and the
  clause is removed too, so the result is the same as before this change.
- A task line with no dependency clause: its summary does not change.
- An open issue created before this change, with the dependency clause in its title, whose
  `— #N` was never written back: after the change it no longer matches by title. This only
  happens after a run that failed, and the changelog says so in one line.
- A dependency clause in the middle of a line, not at its end: it is left as is (only a trailing
  clause is removed).
- A plan review recorded with a version of landspec from before this change, whose report has no
  plan state line: refused once after the upgrade; one new review round fixes it. The changelog
  says so.
- A plan state line written with bold markers or extra spaces: read like the report's other fields
  (`Model:`, `Reviewed:`).
- A latest release that is newer than a few weeks (for example, trivy 0.76.2): the pin moves to
  the newest release that is old enough, or stays where it is if none is.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A task's summary (used for the issue title, the branch name and the text `next`
  shows) MUST NOT include a trailing `(depends on …)` clause, whether or not the line names a
  file path.
- **FR-002**: The rules in every copy of the issues command and in the parallel implement skill
  MUST allow changing the `(depends on …)` clause of a task line that already ends in `— #N`,
  MUST require an issue sync after that change, and MUST still forbid renumbering a task or
  changing its description.
- **FR-003**: After a linked task's dependency clause changes, the issue sync MUST update that
  same issue's body and MUST NOT create an issue.
- **FR-004**: An issue run that finds a task with no `— #N` MUST match an existing open issue whose
  title is the task's summary, even when the dependency clause changed after the issue was
  created, and MUST NOT create a duplicate.
- **FR-005**: The branch name given to a task MUST be the same before and after it gains or loses
  a dependency.
- **FR-006**: Dependencies MUST still be declared only on the task's own line; no second place to
  declare them is added.
- **FR-007**: The osv-scanner, semgrep and trivy pins MUST move only to a release that has been
  out at least three weeks, with the SHA-256 or image digest that release publishes. On 2026-11-16
  none qualifies (research R3); the bump is a small fix made when the weekly check reports one.
- **FR-008**: Each new behavior MUST ship with a test that was seen to fail when the behavior is
  disabled, and the docs and changelog MUST describe the change in the same PR.
- **FR-009**: A plan review report MUST state the plan state the reviewer read, computed the
  same way as the gate's own (plan and task text, without the issue numbers).
- **FR-010**: Recording a plan review MUST refuse a report whose plan state is missing or differs
  from the current plan, with a message that says to run the review again.
- **FR-011**: landspec MUST give the reviewer a way to print the plan state, and the plan review
  instructions MUST tell it to put that value in the report.
- **FR-012**: The weekly pin check MUST compare each pin with the newest release that is at least
  as old as the age rule, and MUST NOT open an issue for younger releases.

### Key Entities

- **Task line**: one checkbox line in `tasks.md`: ID, description, optional file path, optional
  `(depends on …)` clause, and `— #N` once linked to an issue.
- **Task summary**: the description without its file path and dependency clause; the issue
  title, the branch name and the text shown by `next` all come from it.
- **Plan state**: a fingerprint of the plan and task text without issue numbers; the reviewer
  writes the one it read into its report, and recording compares it with the current one.
- **Tool pin**: a scanner's version and its checksum or image digest, kept in one pins file.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Adding or removing a dependency on a linked task changes 0 issue titles, 0 branch
  names, and creates 0 issues, in every case covered by the tests.
- **SC-002**: A repeated issue run after a failed one creates 0 duplicate issues when only the
  dependency clause changed in between.
- **SC-003**: No pin points to a release younger than three weeks, every pinned checksum matches
  its release, and the weekly check opens an issue only for releases old enough to bump to.
- **SC-004**: The whole test suite passes on both CI jobs (Linux bash 5 and bash 3.2).
- **SC-005**: Issues #184, #185 and #186 are closed by the merged PRs.
- **SC-006**: A plan review report recorded after any edit to the plan or task text (other than
  issue numbers) is refused in 100% of the tested cases.

## Assumptions

- Only the English keyword `depends on` is recognized, because that is the only one the
  dependency parsers (`next.sh`, `implement.sh`) read. Supporting other languages would need
  those parsers to change too, and nobody asked for that.
- The `Depends on:` sub-bullet suggested in #185 is out of scope: two places to declare a
  dependency would mean two parsers that can disagree (FR-006).
- "A few weeks" means at least 3 weeks before the bump date, the same rule `pins.sh` already
  states for trivy.
- The constitution allows a pin bump as a small fix with no spec. It is kept in this feature only
  because the request was to resolve every open issue together. It can still ship as its own
  task and PR.
- Issues opened after 2026-11-16 are not covered.
