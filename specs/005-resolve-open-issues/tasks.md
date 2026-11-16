---
description: "Tasks for resolving the open issues #184, #185 and #186"
---

# Tasks: Resolve the open issues (#184, #185, #186)

**Input**: Design documents from `specs/005-resolve-open-issues/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/changes.md](contracts/changes.md), [quickstart.md](quickstart.md)

**Tests**: every task ships its checks in the same PR (bash, "when …, then …", through `tests/helpers.sh`), each seen failing with its behavior disabled; the PR says so.

**Organization**: one phase per user story. The three stories touch different files and can run at once.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (no dependency on an unmerged task)
- `(depends on T00n)`: needs that task merged first
- One task = one issue = one branch = one pull request; ` — #N` is appended automatically.

## Rules every task follows

- After editing `extension/`, sync the installed copy: `specify extension add --dev extension --force`,
  then `git restore .specify/extensions/.registry` when only its timestamp changed. The project copy
  under `.specify/extensions/landspec/` must end identical (`diff -r extension/scripts .specify/extensions/landspec/scripts` empty).
- Bash 3.2 with BSD or busybox tools: no `sed` `I` flag, no `date -d`, no associative arrays.
- `tests/run.sh` and the lint command from the constitution pass before the PR.
- The release notes line for the next version (`docs/releases/<version>.md`) is written in the task
  that changes the behavior.
- `fix/review-findings` (the external review's fixes) edits `secrets.sh`, `prepush.sh`,
  `guard.sh` and `pr.sh`: no task here touches them.

---

## Phase 3: User Story 1 - Add a dependency to a task that already has its issue (Priority: P1)

**Goal**: a linked task's `(depends on …)` suffix can change without changing its issue title, its branch name or its `next` text, and the rules say so.

**Independent Test**: quickstart Q2, Q3, Q4.

- [ ] T001 [P] [US1] Leave the dependency clause out of the task summary, and allow changing it on a linked line, in extension/scripts/lib.sh — #189
  - Comes from: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, SC-001, SC-002; research R1, R2; issue #185
  - What: `task_summary` (`lib.sh:294`) first removes a trailing `(depends on …)` clause
    (`[[:space:]]*\(depends on[^)]*\)[[:space:]]*$`, any case), then applies today's two ` in ` cuts.
    BSD `sed` has no `I` flag: match the keyword case-insensitively without it (e.g. a bracket
    class per letter, `[Dd][Ee][Pp]…`), and keep a clause in the middle of a line untouched.
    Replace the rule text in all four copies with contracts/changes.md "issues.sh / issues.md rule":
    `extension/commands/issues.md:38`, `.specify/extensions/landspec/commands/issues.md:38`,
    `.specify/extensions/landspec/.specify-dev/agent-commands/claude/speckit-landspec-issues/SKILL.md:43`
    and `skills/implement/SKILL.md:113`.
  - Impact: the three callers, unchanged in code: `issues.sh:56` (title, and the lookup by title at
    `:82`), `branch.sh:49` (slug), `next.sh:63` (shown text). The dependency parsers
    `next.sh:55-56` and `implement.sh:251` read the raw line and must keep working.
    `tests/issues.test.sh`, `tests/branch.test.sh`, `tests/next.test.sh`; `docs/reference.md` (the
    task-summary and dependency paragraphs); release notes: an open issue created with the suffix in
    its title, whose `— #N` was never written back, no longer matches by title; and a task started
    before the upgrade whose short description plus suffix reached the slug (e.g.
    `feat/005-t007-foo-bar-depends`) gets a new branch name, so finish it on its old branch or
    rename that branch first (`branch.sh:52-58` looks branches up by exact name) (two lines).
  - Completed when: `bash tests/issues.test.sh`, `bash tests/branch.test.sh` and `bash tests/next.test.sh` pass with new checks:
    - when `task_summary` reads each line of the table in data-model.md "Task summary", then it
      prints the summary in that table, written as literals in the test;
    - when a linked task's dependency changes from `(depends on T001)` to `(depends on T001, T002)`
      and `issues.sh --sync` runs with no new plan review, then it is refused (the plan gate holds:
      failure path); after a new plan review is recorded (`plan_reviewed`), `--sync` prints
      `T00n → #N (updated)`, the fake gh shows one edit of that issue's body and no create, and the
      title is unchanged;
    - when a create reached GitHub but `— #N` was not written back (`GH_FAIL_CREATE_ONCE`), the
      dependency then changes, and `issues.sh` runs again, then it prints `(existing)` and creates
      no second issue;
    - when a task without ` in <path>` gains a dependency, then `branch.sh` gives the same branch
      name as before;
    - when the clause sits in the middle of a line, then the summary keeps it;
    - `next.sh` still reports a task blocked by its dependency after the change (failure path:
      the dependency is still enforced).

---

## Phase 4: User Story 3 - A plan review counts only for the text it read (Priority: P1)

**Goal**: `review.sh record --plan` accepts a report only for the exact plan text the reviewer read.

**Independent Test**: quickstart Q6.

- [ ] T002 [P] [US3] Record a plan review only for the plan state it read, in extension/scripts/review.sh — #190
  - Comes from: FR-009, FR-010, FR-011, SC-006; research R4, R5; issue #186
  - What: follow the invariant in data-model.md "Plan state" (the reviewer hashes and reads one
    snapshot, in its own copy). A new action `review.sh state --plan [<dir>]` prints `state()` and
    exits 0 without writing anything; with `<dir>` it hashes `<dir>/plan.md` and `<dir>/tasks.md`
    (a missing file dies) and does not look up the active feature. Today `state()` is defined at
    `:43-44`, inside `if $plan`, after the `mkdir -p "$dir"` at `:39`: move the `fdir`/`state()`
    definition above that `mkdir` (or move the `mkdir` below the plan block and the `state` exit),
    so `state` returns before any write and before `tip=` at `:58`. `state` without `--plan` dies
    `usage: review.sh state --plan`.
    In `record` (`:206-218`), for a plan, after the `Model:` check: read the report's last exact
    `Plan state: <64 hex>` line with the existing `field` helper (`:66`, optional bold); missing →
    `die "the report has no Plan state line: run the review again (this landspec version records it)"`;
    different from `st` → `die "the plan changed since this review: run the review again"`.
    Update the usage header (`:2-16`). In `extension/commands/review.md`, "Plan review" (`:132`) and
    the report-fields paragraph (`:202-205`, "A plan report has only `Copy:` and `Model:`"), and
    the subagent's step 2 (`:42`, "A plan review reads `<checkout>/specs/NNN-*/` in place": now it
    reads the copied `plan.md` and `tasks.md`, the other spec files in place): run
    first copy `<checkout>/specs/NNN-*/plan.md` and `tasks.md` into a `mktemp -d` folder, run
    `bash .specify/extensions/landspec/scripts/review.sh state --plan <folder>` in the reviewer's own
    copy, review the copied files, and write `Plan state: <hash>` in the report; if the command
    fails, the report says `Plan state: unavailable (<reason>)` and
    ends `Assessment: changes needed` (record refuses a non-hash value like a missing one).
  - Impact: the project copies `.specify/extensions/landspec/scripts/review.sh`,
    `.specify/extensions/landspec/commands/review.md` and its generated skill under
    `.specify/extensions/landspec/.specify-dev/agent-commands/claude/`; `issues.sh` and
    `pr.sh spec` call `review.sh check --plan` (unchanged: the record now only exists for the read
    text); every existing plan-review fixture must gain the line: `tests/review.test.sh` (10
    `record --plan` calls), `tests/issues.test.sh:7` (`plan_reviewed`), `tests/pr.test.sh:117, 137,
    143, 157, 403, 456, 513` (one shared helper in `tests/helpers.sh` writing the report with the
    current state avoids eight copies); each must gain a `Plan state:` line computed by `review.sh state --plan`; `agents/reviewer.md:13` ("before `Model:` in a plan review": add `Plan state:`, taken first); `docs/reference.md` (plan review); release notes
    (old plan reports are refused once; a project whose plugin is upgraded but whose project copy
    of `review.sh` has no `state` action gets `unavailable` reports until `/landspec:init` updates
    it).
  - Completed when: `bash tests/review.test.sh`, `bash tests/issues.test.sh` and `bash tests/pr.test.sh` pass, with new checks in `review.test.sh`:
    - when a ready plan report carries the current `Plan state:`, then `record --plan` prints
      `REVIEW=ready`;
    - when a sub-bullet in `tasks.md` is edited and the same report is recorded again, then it fails
      with `the plan changed since this review: run the review again` and `check --plan` fails;
    - when only ` — #N` is appended to task lines, then the same report still records ready;
    - when the report has no `Plan state:` line, then it fails with `the report has no Plan state line`;
    - when the line is written `**Plan state:** <hash>`, then it is read;
    - when the line is `Plan state: unavailable (refused)`, then record refuses it as missing;
    - when `review.sh state --plan` runs in a clone with no `.git/landspec-review`, then the folder
      still does not exist afterwards, and `state` without `--plan` fails with its usage;
    - when `state --plan <dir>` runs in a clone with no `.specify/feature.json` on a folder holding
      copies of a feature's `plan.md` and `tasks.md`, then it prints the same hash as `state --plan`
      in the clone that has that feature active; a folder missing `tasks.md` fails;
    - the PR records one real plan review run by the isolated `landspec:reviewer` (any feature):
      the `REVIEW=ready` line `record --plan` printed for a report whose `Plan state:` was taken with
      `state --plan <folder>` (the path the fakes cannot prove; a manual step, shown in the PR).

---

## Phase 5: User Story 2 - Scanner pins on current, settled releases (Priority: P2)

**Goal**: the weekly check reports only releases old enough to bump to; no pin moves today (none is settled).

**Independent Test**: quickstart Q5, Q7.

- [ ] T003 [P] [US2] Report only releases at least three weeks old, in bin/check-tools.sh — #191
  - Comes from: FR-012, User Story 2 scenario 3; research R3; issue #184
  - What: per tool, replace `gh api "repos/$repo/releases/latest" --jq .tag_name` with
    `gh api "repos/$repo/releases?per_page=30"` and a `--jq` that picks the newest release with
    `.prerelease == false` and `(.published_at | fromdateiso8601) <= (now - 21*86400)`, printing its
    `tag_name`, with exactly `first(.[] | select(.prerelease == false and .published_at != null and
    (.published_at | fromdateiso8601) <= (now - 21*86400))) | .tag_name` (no output when none
    qualifies; a draft's null date is skipped). Only gh's exit status means a failed lookup: drop the `[[ -n "$latest" ]]` test from
    the `|| die` chain at `:20-21`, and treat an empty result as "no release old enough: not behind".
    Keep `</dev/null`, `version_newer`,
    the SEMGREP digest note and the one-open-issue rule. The issue body says "newest release out
    for three weeks" instead of "latest". Header comment: the age rule and why (pins.sh, trivy).
  - Impact: `.github/workflows/pins.yml` (comment "compares … with their latest releases");
    the fake gh in `tests/helpers.sh:50-55` (`"api repos/"*)`: today it prints `$GH_API`'s tag for
    `releases/latest`, imitating the `--jq`; it must instead run the call's own `--jq` through real
    `jq -r` over a JSON release list per repo, the way `GH_PR_JSON` does at `tests/helpers.sh:66-68`,
    so the filter the task adds is what the tests exercise; the test writes `published_at` relative
    to the run with `jq -n 'now - 10*86400 | todate'` (no `date -d`), so it does not rot);
    `tests/check-tools.test.sh` (its five checks move to the new format; the failure message `cannot read the latest <tool> release from <repo>` is
    kept as is); `docs/reference.md` if it describes the weekly check. This task closes #184
    (`Closes #184` in the PR besides its own issue): no pin moves in this feature (research R3); the
    checker opens a new issue once a release is settled, and that bump is a small fix PR.
  - Completed when: `bash tests/check-tools.test.sh` passes with new checks:
    - when the only newer release is 10 days old, then it prints `BEHIND=0` and creates no issue;
    - when a newer release is 30 days old and a newer one 5 days old, then it prints
      `behind: <tool> <pin>, latest <the 30-day one>` and opens one issue naming that version;
    - when the newest old-enough release is a prerelease, then it is skipped;
    - when every release is younger than 21 days (an empty result, gh exit 0), then it prints
      `BEHIND=0`, does not fail, and opens no issue;
    - when the list holds a draft with `"published_at": null` beside a settled release, then the
      draft is skipped and no error occurs (the null guard);
    - each of these fails when the filter is broken on purpose (`>=` for `<=`, the `prerelease`
      test removed, the null guard removed): the PR says so;
    - when the release lookup fails, then it exits non-zero with `cannot read the … release`
      (failure path, as today).

---

## Dependencies & order

- T001, T002, T003: independent; start all three at once (`/landspec:implement`). Shared files,
  whichever merges second rebases onto the first: `tests/issues.test.sh` (T001, T002: T002 adds
  `Plan state:` to `plan_reviewed` at `:7`, T001 calls it once more); `docs/reference.md` (T001,
  T002, maybe T003); the next release notes file `docs/releases/<version>.md` (all three: the
  first to merge creates it, the others add their line to it).
- The pin bump itself is not a task: see plan.md Notes.
- MVP: T001 and T002 (both P1, both gate holes in landspec's own flow).

## Parallel example

```text
/landspec:implement 005     # starts T001, T002, T003 together, each in its own copy
```
