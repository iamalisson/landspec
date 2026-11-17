# Feature Specification: A plan review that can be trusted, and the open bugs (#187, #188, #206, #216, #217, #218)

**Feature Branch**: `spec/007-plan-review-and-fixes`

**Created**: 2026-11-17

**Status**: Draft

**Input**: User description: "there are some issues reported on the repo. mayle related to reviewr process bein really week. and other bugs. let's adress all of 'em and release a new version". On 2026-11-17 the open reported issues are:
- about the review: #187 (the plan review misses contradictions between documents, requirement coverage and rollout boundaries), #188 (the plan review samples instead of enumerating and does not converge: 37 rounds, 10 `ready`, each followed by new real findings), #206 (the Low findings of a `ready` round cannot be applied without a new full round);
- bugs: #216 (a delta record counts lines merged in from the base branch), #217 (a semgrep failure points at an empty log), #218 (adopt does not detect pre-commit formatters that would rewrite most of the existing code).

#200 is a task of feature 006, not a reported issue. #185 and #186 were fixed in 2.7.0 and are only still open on GitHub; they are out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A `ready` plan review means every item was checked (Priority: P1)

A developer finishes `/speckit-tasks`, and the plan review runs until it says `ready`. Today one
reviewer reads the plan once, stops after about 20 tool calls, and "ready" means "this reading
found nothing serious". Nothing in the report shows what was covered. On one feature, every one of
10 `ready` verdicts was followed by a second reviewer on the spec PR finding 2 to 8 more real
problems: two documents stating the same rule differently, a requirement no task proves, a false
claim about existing code, a task whose tests need code from a later task, a rollout that writes
data that can never be corrected, a CI job no task mentioned.

With this feature the plan review is a fixed set of passes. Each pass has one narrow job and
fills in a table with one row per item it must check, so the report shows what was covered:

- **Size**: each task, against about 400 lines of diff and one vertical slice, `holds` or
  `BREAKS`.
- **Requirements → proof**: each functional requirement and each acceptance scenario of the spec,
  with the task whose *Completed when* proves it, or `MISSING`.
- **Rules across documents**: each rule stated in more than one document of the feature folder
  (a field, a filter, a response shape, who may do something, a default, a link between entities),
  one column per document, `SAME` or the difference.
- **Claims about the code**: each claim the plan makes about code that exists ("as today",
  "existing", "callers unchanged", a `file:line`), `TRUE` or `FALSE` with the evidence read.
- **Task inputs**: for each task, everything its tests need (a function, a table, a file, a
  fixture), and the earlier task or the base branch that provides it, or `MISSING`.
- **Repository guards**: each CI job and each check that covers the whole test suite, against the
  files the tasks change: which task handles it, or `MISSING`.
- **Rollout**: for each task that writes data, schedules a job or fixes a value that cannot change
  later: its first day, a start in the middle of a period, the switch from what it replaces, and
  the task running in production alone before the tasks after it.
- **Orderings**: the existing check of states and events that can arrive in any order.

The review's result is refused as `ready` while any table is missing or empty or holds a
failing row (`MISSING`, `FALSE`, a difference, `BREAKS`).

**Why this priority**: it is the reported weakness (#187, #188), it costs most of a working day
per feature, and a `ready` that does not predict the next reviewer gives false confidence.

**Independent Test**: take a small fixture feature folder with one planted defect per pass (a
requirement no task proves, a rule worded differently in two documents, a false claim about a
file, a task needing a later task's function, a CI job no task handles, a task that writes data
on its first day before the task it depends on). Run the plan review: its report names each
planted defect in its pass's table, and recording a report that says `ready` with any `MISSING`
or `FALSE` row is refused.

**Acceptance Scenarios**:

1. **Given** a spec with five functional requirements of which one is proven by no task's
   *Completed when*, **When** the plan review runs, **Then** its requirements table has five rows
   and that requirement's row says `MISSING`.
2. **Given** a rule stated in the data model and in a contract with different values, **When**
   the plan review runs, **Then** the rules table has a row for it naming both documents and the
   difference.
3. **Given** a plan that says a function "is unchanged for its callers" while a task changes what
   it returns, **When** the plan review runs, **Then** that claim's row says `FALSE` with the file
   and line read.
4. **Given** a report whose Assessment is `ready` but whose tables have a `MISSING` or `FALSE` row,
   or an empty table, or a pass left out, **When** it is recorded, **Then** the record is refused
   and says which pass and row.
5. **Given** a feature with no item of a kind (for example no task writes data), **When** the
   review runs, **Then** that pass's table says so in one row (`none: <why>`), which is not empty
   and not refused.

---

### User Story 2 - Fix rounds check the fix as new text, and a troubled area gets simplified (Priority: P1)

After a `changes needed` round the author fixes the findings, and the next round runs. Today that
round is handed the author's one-line answers, so it checks "was finding N addressed?" and reads
the fix through the author's eyes. Twice in a row on one feature, the Medium findings of the next
round were in the text that fixed the previous ones. And when one area of the design keeps
producing findings round after round (four rounds of patches for one rule about who may see a
list), the review asks for another patch instead of saying that the area should be simplified or
moved to a later spec.

With this feature:

- a round after `changes needed` runs every pass in full on the paragraphs the fix changed, and is
  not given the author's answers; whether each earlier finding is resolved is checked against the
  text, in a short table of its own;
- each finding names the area it belongs to (a section of the data model, or a group of tasks);
  when one area has gathered 3 or more findings across the rounds of a feature, the next report
  opens with a **Simplify** section: the simplest design that removes what keeps breaking, or
  moving the area to a later spec. The author answers it (accept, or say why not) before the next
  round.

**Why this priority**: it is why the loop does not converge (#188 points 2 and 3, #187 "rounds
without answers"); without it the passes of User Story 1 still miss what each fix breaks.

**Independent Test**: on a fixture folder, record a `changes needed` round, then edit one paragraph
to fix its finding and plant a new defect in that same paragraph. The next round's report names the
new defect, and the prompt that reviewer received holds no author answer. Then record rounds whose
findings bring one area to three: the next report opens with a Simplify section about that area.

**Acceptance Scenarios**:

1. **Given** a `changes needed` round and a fix that edits two paragraphs, **When** the next round
   runs, **Then** the passes read those two paragraphs as new text, and the reviewer of the passes
   is not given the author's answers.
2. **Given** a fix that resolves its finding but adds a new defect in the same paragraph, **When**
   the next round runs, **Then** the new defect is a finding of that round.
3. **Given** three findings in one area over the rounds of a feature, **When** the next report is
   written, **Then** it opens with a Simplify section for that area, and the next round does not
   start until the author's answer to it is recorded.
4. **Given** findings spread over different areas, two or fewer each, **When** a report is written,
   **Then** it has no Simplify section.

---

### User Story 3 - A plan too big to review well is split first (moved to a follow-up feature)

Proposing a split above 12 tasks, and a second reader on another model for such a plan, were
planned here. Seven plan review rounds of this very feature kept finding new gaps between these
rules, the plan delta and the earlier-findings table, so they move to a follow-up feature, to be
designed on their own once the tables of User Story 1 are in use. In this feature the `size` pass
checks each task's size (User Story 1) and the task count is not a refusal.

---

### User Story 4 - Every document of the feature folder is part of the plan state (Priority: P2)

Some documents of the feature folder (the data model, the contracts, the research) are not part of
the recorded plan state today, so a change there after a `ready` costs nothing while the same
change in `tasks.md` needs a new review: the rule is not the same for every document (#206).

With this feature every document of the feature folder is part of the recorded plan state. The
cheap review of a small fix after a `ready` (the **plan delta**, also asked in #206) moves to the
follow-up feature of User Story 3.

**Why this priority**: it closes the hole in #206 where an unreviewed change reaches public issues.

**Independent Test**: change one line in the data model after a recorded `ready`: the sync refuses.
Write the issue numbers back into `tasks.md`: the state is unchanged.

**Acceptance Scenarios**:

1. **Given** a one-line change to the data model, a contract, the research or the quickstart after
   a `ready`, **When** the issue sync runs, **Then** it refuses until a review of the new state is
   recorded, as for `tasks.md`.
2. **Given** issue numbers (`— #N`) written back into `tasks.md` after a `ready`, **When** the
   state is checked, **Then** it is unchanged.

---

### User Story 5 - The cost of the plan phase is visible (Priority: P2)

Today the statistics report covers task PRs only. Plan rounds, findings per round, the time from
the first plan review to the issues, and the findings that came up after a `ready` never appear,
so nobody can see that the plan phase is where the time goes, or whether a change to the review
helps.

With this feature the statistics report shows, per feature: the number of plan review rounds, the
findings per round by severity, the time from the first plan review to the issues, and the
number of findings a reviewer outside the loop (a person or a PR bot) found after a `ready`,
which the author records.

**Why this priority**: it measures whether User Stories 1-3 work; it fixes nothing on its own.

**Independent Test**: with a recorded log of four plan rounds (two `changes needed` with
findings, two `ready`), an issue run, and two recorded outside findings, the report shows 4
rounds, each round's findings by severity, the time between the first round and the issue run,
and 2 outside findings.

**Acceptance Scenarios**:

1. **Given** recorded plan rounds for a feature, **When** the statistics report runs, **Then** it
   shows the number of rounds and each round's findings by severity.
2. **Given** the author records 3 findings found on the spec PR after a `ready`, **When** the
   report runs, **Then** it shows 3 outside findings after `ready` for that feature.
3. **Given** a feature whose issues were created, **When** the report runs, **Then** it shows the
   time from its first plan round to its issue run.

---

### User Story 6 - A delta review counts only the fix, not a merge of the base (Priority: P2)

A task PR gets review comments, the developer presses GitHub's "Update branch" (which merges the
base into the task branch), then commits a small fix and runs a delta review. Today the delta
record counts every line the base merge brought in (another task's change, already reviewed and
merged) and refuses: "the delta changes 376 lines outside the previous findings (limit 20)".

With this feature, lines that arrive through a merge of the base are not counted; only the
changes the fix round's own commits made are.

**Why this priority**: a reported bug (#216) that forces a full review round for a small fix, on a
step GitHub offers on every PR.

**Independent Test**: record a full review of a task branch; merge an unrelated change into the
base and the base into the task branch; commit a 5-line fix; record a delta review: it is
accepted, and the counted size is the fix's 5 lines.

**Acceptance Scenarios**:

1. **Given** a task branch with a recorded full review, then a merge of the base bringing 300
   lines, then a fix of 5 lines, **When** the delta is recorded, **Then** it is accepted.
2. **Given** the same, but with a fix of 30 lines outside the previous findings, **When** the
   delta is recorded, **Then** it is refused, counting the 30 lines, not the merge.
3. **Given** a merge that brings lines from somewhere other than the base (another task's
   unmerged branch), **When** the delta is recorded, **Then** those lines count.
4. **Given** a merge of the base whose conflict resolution adds lines of its own, **When** the
   delta is recorded, **Then** the resolution's own lines count.

---

### User Story 7 - A failed semgrep run names its real error (Priority: P3)

Today when semgrep fails the scan says "see `semgrep.log`", and that file is empty: semgrep wrote
its error (here, its engine was killed for using too much memory) into its JSON output. The
developer has to find and open the JSON by hand.

With this feature the scan's failure line gives the real error: the first error message semgrep
reported, and the file that holds the rest.

**Why this priority**: a reported bug (#217) with a manual workaround.

**Independent Test**: a fake semgrep that exits 2, writes nothing to its log and puts one error
message in its JSON: the scan's line shows that message and names the JSON file.

**Acceptance Scenarios**:

1. **Given** semgrep exits with a failure, an empty log and an error in its JSON output, **When**
   the scan reports, **Then** the failure line holds that error's message and names the JSON file.
2. **Given** semgrep fails with text in its log, **When** the scan reports, **Then** it keeps
   pointing at the log.
3. **Given** semgrep fails with an empty log and no readable JSON, **When** the scan reports,
   **Then** it says both are empty and names them, instead of pointing at one empty file.

---

### User Story 8 - Adopt warns about a formatter that would rewrite the existing code (Priority: P3)

A repository's pre-commit configuration has a whole-file formatter, but almost none of its
existing files are in that format. The first implementer that touches an existing file cannot
commit: the hook rewrites the whole file, skipping the hook is (rightly) refused by the guard, and
every task touching an old file fails the same way. Today nothing notices this before the tasks
run.

With this feature `/landspec:adopt` runs the configured formatter hooks in check mode on the
repository as it is and, when they would rewrite more than half of the files they cover, says so
and proposes a setup step before any task: format the code once in its own PR, or remove or scope
the hook. An implementer whose commit is blocked by a formatter rewriting lines the task did not
write says that this is the cause, and how to fix it, instead of a generic failure.

**Why this priority**: a reported problem (#218) that blocks every task on such a repository, but
it has a clear manual fix once it is known.

**Independent Test**: in a fixture repository with a formatter hook that would rewrite 9 of 10
files, adopt reports the hook, the count (9 of 10) and the two options; with 1 of 10 it reports
nothing. An implementer whose commit fails because the hook rewrote untouched lines returns a
failure naming the hook.

**Acceptance Scenarios**:

1. **Given** a formatter hook that would rewrite more than half of the files it covers, **When**
   adopt runs, **Then** it names the hook, the count of files, and the two options, and does not
   change the configuration itself.
2. **Given** a formatter hook that would rewrite half of the files or fewer, **When** adopt runs,
   **Then** it says nothing about it.
3. **Given** no pre-commit configuration, or pre-commit not installed, **When** adopt runs,
   **Then** it skips the check and says why in one line.
4. **Given** an implementer's commit refused because a formatter rewrote lines outside the task's
   change, **When** the implementer returns, **Then** its failure names the hook and points at the
   setup step.

---

### User Story 9 - The skills and MCP tools a developer installed are used when a task fits them (Priority: P2)

A developer installs skills and MCP servers for their stack (a UI/UX skill, a framework's own skill,
a design tool's server) and expects landspec's implementer and reviewer to use them when a task
fits. Today nothing asks them to look, and a matching skill fires only about half the time
(issue #234).

**Why this priority**: it decides whether the developer's own tools reach the code landspec writes,
and it costs no setting: what is installed is what the developer chose.

**Independent Test**: on any task, the implementer's return and the PR's Evidence carry a
`Skills:` line naming each skill or MCP server used and why, or `none matched`.

**Acceptance Scenarios**:

1. **Given** a UI skill whose description fits the task's files, **When** the implementer starts,
   **Then** it writes `<skill> - YES - <reason>` and invokes the skill before writing code, and
   the PR's Evidence names it.
2. **Given** no installed skill or MCP server fits the task, **When** the implementer starts,
   **Then** its return and the PR say `Skills: none matched`.
3. **Given** a skill whose instructions say to commit, push or open a PR, **When** it is used,
   **Then** landspec's rules still hold: the task's scope is unchanged and the guard refuses
   anything the implementer may not do.
4. **Given** the single-task path (`/speckit-implement`), **When** the task starts, **Then** the
   same evaluation runs before any code is written.

---

### User Story 10 - A PR is handed over only when it is mergeable and a Copilot review on it is answered, with its CI state shown (Priority: P2)

A repository can have GitHub's Copilot code review on, by a ruleset that asks for it on every PR
and push, or by someone asking for it by hand. It posts inline comments some minutes after a push,
and landspec has never read them: the developer finds a "ready to merge" PR with comments nobody
answered, or a PR still conflicting with its base, and has to open each PR to see its CI. landspec
now reads, before it hands any PR over, whether it conflicts and whether a Copilot review is
coming, done with comments, clean, or could not run, and shows each PR's CI state beside it without
waiting for it; and it treats
Copilot's comments as one more outside review, answering each one.

**Why this priority**: it is the same weakness as the rest of this feature, a review whose findings
are left unread, and a hand-over the developer has to check PR by PR.

**Independent Test**: with a fake `gh` that answers the pull request query, `pr.sh state <pr>`
prints the conflict, CI and Copilot lines for each case, and a reply marks a thread answered and
resolved.

**Acceptance Scenarios**:

1. **Given** a PR with a Copilot review request open, **When** landspec checks it, **Then** it
   reports the PR as waiting for Copilot, never as ready to merge.
2. **Given** a task PR with unanswered Copilot threads, **When** `/landspec:implement` runs, or
   `/speckit-implement` runs again for that task, **Then** the task gets a fix round with those
   comments as its report, each comment is fixed or answered with the reason it is not a defect,
   and every thread gets a reply and is resolved.
3. **Given** a spec PR with unanswered Copilot threads, **When** the comments are handled, **Then**
   the plan is fixed, the plan review runs again, the real ones are counted with `outside --plan`,
   and every thread gets a reply and is resolved.
4. **Given** no Copilot request is open, no Copilot thread is unanswered, and Copilot's newest word on the PR is that it could not review it (for example "unable to
   review this pull request because the user who requested the review has insufficient remaining
   quota"), **When** landspec checks it, **Then** it reports Copilot as unavailable with that
   reason and does not wait: the PR is handed over if the rest holds.
5. **Given** a PR that conflicts with its base, **When** landspec would hand it over, **Then** it
   lists it with that reason instead of among the PRs to merge; **Given** a PR whose CI is still
   running or failed, **Then** it is handed over all the same, with "CI still running" or the failed
   job names beside it: landspec never waits for CI.
6. **Given** a repository without Copilot code review, **When** landspec checks a PR, **Then**
   only the conflict line decides, and the CI state is shown (`COPILOT=none`).

### Edge Cases

- A plan review pass finds no item of its kind: its table says `none: <why>` (User Story 1,
  scenario 5).
- A spec with no functional requirements at all: the requirements pass is `MISSING` for the spec
  itself, and the review is not `ready`.
- A report written by an earlier landspec, without tables: it is refused once, with a message
  saying to run the review again (the same path as the plan state introduced in 2.7.0).
- The Simplify section is declined by the author: the answer is recorded and the rounds go on; the
  area's count restarts from the answer, and a new Simplify section is asked for it only when
  three more findings land there after the answer.
- A base merge with conflicts on a task branch: the lines of the resolution count toward the delta
  (User Story 6, scenario 4).
- semgrep's JSON holds several errors: the first is shown, the file holds the rest.
- A formatter hook whose check mode cannot run (it needs a tool that is not installed): adopt says
  it could not check that hook, and goes on.

## Requirements *(mandatory)*

### Functional Requirements

**The plan review (#187, #188)**

- **FR-001**: The plan review MUST run as eight fixed passes (size, requirements → proof, rules
  across documents, claims about the code, task inputs, repository guards, rollout, orderings),
  each with its own table of one row per item checked.
- **FR-002**: The plan review MUST run on every level (lite, standard, full), so the rules-across-
  documents check no longer depends on `/speckit-analyze`, which runs only on `full`.
- **FR-003**: Recording a plan review as `ready` MUST be refused when any pass's table is missing
  or empty, or holds a `MISSING` or `FALSE` row; the refusal names the pass and the row. A pass
  with nothing to check writes one row `none: <why>`.
- **FR-004**: A round after `changes needed` MUST run every pass on the paragraphs the fix changed
  since the last reviewed state, and MUST NOT be given the author's answers to earlier findings;
  whether each earlier finding is resolved is checked against the text, in a table of its own.
- **FR-005**: Each finding MUST name its area (a data-model section or a group of tasks). When an
  area has 3 or more findings across a feature's rounds, the next report MUST open with a Simplify
  section for it, and the next round MUST NOT start until the author's answer is recorded.
- **FR-008**: The plan review's instructions, the reviewer's own instructions and every installed
  copy MUST describe the same passes, tables and rules.

**The plan state (#206)**

- **FR-009**: The recorded plan state MUST cover every document of the feature folder (spec, plan,
  tasks, data model, contracts, research, quickstart, checklists), without the issue numbers
  written back into `tasks.md`.
**Moved to a follow-up feature** (see User Story 3): FR-006 (a split above 12 tasks), FR-007 (a
second reader for such a plan), FR-010 and FR-011 (the plan delta), and SC-004. Their numbers are
not reused.

**Statistics (#188)**

- **FR-012**: The statistics report MUST show, per feature: plan review rounds, findings per round
  by severity, the time from the first plan review to the issue run, and the number of findings
  recorded as found outside the loop after a `ready`.
- **FR-013**: The author MUST be able to record a number of findings found outside the loop after a
  `ready` (on the spec PR, by a person or a bot), for a feature.

**The delta record (#216)**

- **FR-014**: A task delta record MUST NOT count lines that arrived through a merge of the base
  branch; it MUST count the fix round's own changes, including the lines of a conflict resolution
  and any lines merged from a branch other than the base.

**The scan (#217)**

- **FR-015**: When semgrep fails, the scan's line MUST give the first error message semgrep
  reported and the file holding the rest; when the log has text, it MUST keep naming the log; when
  both are empty, it MUST say so and name both.

**Adopt (#218)**

- **FR-016**: `/landspec:adopt` MUST run the repository's configured formatter hooks in check mode
  and, when one would rewrite more than half of the files it covers, report the hook, the count and
  the options (format once in its own PR, or remove or scope the hook), without changing the
  configuration itself.
- **FR-017**: An implementer whose commit is refused because a formatter rewrote lines outside the
  task's change MUST return a failure naming the hook and the setup step.

**The release**

- **FR-018**: Each changed behavior MUST ship with a test that was seen failing before the change,
  and the release notes MUST describe each reported issue (#187, #188, #206, #216, #217, #218, #234, #244),
  with an "Upgrading" section for anything a project must redo (a plan report written by an earlier
  version is refused once).
- **FR-019**: The release MUST be a new minor version (2.8.0), released by the usual whole-feature
  check, audit and release steps.

- **FR-020**: Before writing code, the implementer (the parallel run's subagent and the
  single-task path) and the reviewer MUST list the installed skills and MCP servers that could bear
  on the task (its files, its domain, its *Completed when*), write `<name> - YES/NO - <reason>` for
  each, and invoke every YES before going on; no setting chooses them. landspec's and spec-kit's
  own workflow skills are never candidates, and a skill that needs the user's answers is not invoked
  in a background agent. A skill never widens the task's scope, never makes the reviewer write or
  change its report's shape, and never bypasses the guard (issue #234). A plan review does not
  evaluate skills.
- **FR-021**: The implementer's return and a task review's report MUST carry a `Skills:` line (each
  skill or MCP server used and what it was used for, or `none matched`), and the PR's Evidence MUST
  show the implementer's line (`not reported` when it returned none).

- **FR-022**: `pr.sh state <pr>` MUST print three lines for the PR's head commit:
  `CONFLICT=no|yes|unknown`; `CI=pass|pending|fail <job> (<conclusion>),…|none` (pending while any
  check has not completed; a cancelled or timed-out job counts as failed, named with its conclusion);
  and `COPILOT=pending|unavailable <reason>|comments <n> REPORT=<file> [RESOLVE=<id>,…]|clean|none`.
  In this order: `pending` while a Copilot review request is open; `comments` when unresolved
  Copilot threads have no reply after Copilot's comment (`RESOLVE=` names those replied to but not
  resolved), so unanswered threads are never hidden by a later message; `unavailable` when Copilot's
  newest review or comment says it was unable to review; `clean` when Copilot reviewed and nothing
  is left; `none` otherwise. No time window and no push record: in the seconds after a push, before
  a ruleset's request appears, a PR can read ready, and the next check sees the request (a named
  limit). It only reads: it never asks Copilot for a review (issue #244).
- **FR-023**: `pr.sh state <pr> --reply <thread id> [<file>]` MUST post the file as a reply in that
  thread and then resolve it; on a thread already replied to, it MUST only resolve it, posting
  nothing; it MUST refuse a thread that is not on the PR, not opened by Copilot, or already
  resolved, and a first reply with no file or an empty one.
- **FR-024**: The implement run, the single-task path (when it runs again on a task with an open
  PR) and the spec PR step MUST act on FR-022's Copilot line: comments on a task PR are a fix round,
  comments on a spec PR are outside plan findings, and every comment is answered (fixed, with the
  commit, or not a defect, with the reason) before its thread is resolved.
- **FR-025**: A PR MUST be handed over as ready to merge (the implement run's End, the single-task
  path's last step, the spec PR step's last line) only when `pr.sh state` reads `CONFLICT=no` and
  `COPILOT=` `none`, `clean` or `unavailable`; otherwise it is listed with the reason (conflict,
  GitHub still computing whether it conflicts, waiting for Copilot, Copilot comments). CI never holds
  a PR back (the developer's decision: waiting for it takes too long): `CI=pending` is shown as "CI
  still running" and `CI=fail` as the failed jobs, beside the PR. Every PR the run lists carries its
  number as a link.

### Key Entities

- **Plan review pass**: one narrow check of the plan, with its kind (one of the eight), its table
  of rows, and each row's status (passing: `proven` / `SAME` / `TRUE` / `provided` / `handled` /
  `safe` / `holds` / `none: <why>`; failing: `MISSING` / a difference / `FALSE` / `BREAKS`).
- **Plan state**: a fingerprint of the whole feature folder, without issue numbers, which a review
  report names and a record checks.
- **Finding area**: the part of the design a finding belongs to; counted across a feature's rounds
  to decide when a Simplify section is due.
- **Outside finding**: a finding about a plan, found after a `ready` by a reviewer outside the
  loop, recorded by number per feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On the fixture with one planted defect per pass, the plan review names 8 of 8
  defects in their passes' tables, in one round.
- **SC-002**: 100% of `ready` reports with an empty table, a missing pass, or a failing row
  (`MISSING`, `FALSE`, a difference, `BREAKS`) are refused when recorded.
- **SC-003**: On the fixture where a fix plants a new defect in the paragraph it changed, the next
  round names it, and its passes' prompt holds no author answer.
- **SC-005**: In the reported reproduction of #216 (a base merge of about 340 lines plus a small
  fix), the counted size of the delta is the fix's own lines.
- **SC-006**: A failed semgrep run's line contains semgrep's own error text in 100% of the fixture
  cases where the JSON holds one.
- **SC-007**: On the fixture repository where a formatter would rewrite 9 of 10 files, adopt reports
  it before any task runs.
- **SC-008**: For the next feature planned after this release, the statistics report shows its plan
  rounds and outside findings; the target is at most 2 outside findings after its first `ready`
  (today: 2 to 8 each time).
- **SC-009**: All existing checks keep passing on every supported shell (bash 3.2 and busybox, BSD
  tools, bash 5).

- **SC-010**: A static check fails when the implementer's, the reviewer's or the single-task
  path's instructions lose the evaluation step or the `Skills:` line, and the PR instructions lose
  the `Skills:` line in Evidence.

- **SC-011**: No landspec PR is listed as ready to merge while it conflicts, while a Copilot
  review is coming, or while a Copilot thread is unanswered, and every listed PR shows its CI state;
  a static check fails when a hand-over step loses the `pr.sh state` rule.

## Assumptions

- The passes are run by reviewers launched by the main session, as reviews are today (a reviewer
  cannot launch another); running them in parallel is a speed choice, not a requirement.
- The size limits (about 400 lines per task, 3 findings per area, more than half of the files) are starting values
  taken from the reports; they may become settings later, and no setting is added now.
- A Simplify section is a recommendation the author answers; the review never changes the spec
  itself.
- The fixtures for SC-001, SC-003 and SC-007 are small feature folders and repositories written for
  the tests; SC-008 is measured on the next real feature, after the release.
- #185 and #186 were fixed in 2.7.0; closing them on GitHub is housekeeping outside this spec.
- The audit findings of the 2.7.0 release are tracked privately with `/landspec:security`, not in
  this spec, because the repository is public.
