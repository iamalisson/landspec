# Data model

Everything here lives in `.git` (never committed, never pushed), except the report, which the
reviewer writes outside the repository (`mktemp`).

## Plan state

The SHA-256 of the feature folder: for each file under `specs/NNN-*/`, sorted by path with
`LC_ALL=C sort`, its path relative to the folder, a NUL, its content's byte length, a newline,
then its content (`tasks.md` with each trailing ` — #N` removed), so no two folders hash alike by
moving bytes between files. Left out: files whose name starts with `.` (`.DS_Store`) or ends in
`~`, `.swp` or `.tmp` (`issues.sh:46` writes `tasks.md.tmp` before its `mv`). `# shortcut:` a
name list, not `git ls-files`, because the reviewer hashes a copy outside any repository. The reviewer computes it on its own copy of the folder (`review.sh state
--plan <copy>`); `record`, `check` and `diff` compute it on the feature folder.

## Plan review report

A plan report keeps today's trailer (`Copy:`, `Plan state:`, `Model:`, `Findings: <n> high, <n>
medium, <n> low`, `Assessment:`) and gains, in this order:

1. one `## Simplify: <area>` section per area the author passed as `simplify: <a>, <b>`;
2. one section per pass, exactly `### Pass: <name>`, for `size`, `requirements`, `rules`, `claims`,
   `inputs`, `guards`, `rollout`, `orderings`, each followed by a markdown table;
3. `### Earlier findings`, in a round given an earlier report: one row per earlier finding;
4. the findings, each scenario starting `[area: <name>]`.

A table row is a line starting with `|` that is not the header or its `|---|` line. Its **status**
is its last cell, trimmed:

| Pass | Passing statuses | Failing statuses |
|---|---|---|
| any | `none: <why>` (the pass's only row) | — |
| size | `holds` (one row per task: about 400 lines at most, one vertical slice) | `BREAKS: <why>` |
| requirements | `proven` | `MISSING` |
| rules | `SAME` | `DIFFERENT: <what>` |
| claims | `TRUE` | `FALSE` |
| inputs | `provided` | `MISSING` |
| guards | `handled` | `MISSING` |
| rollout | `safe` | `BREAKS: <how>` |
| orderings | `holds` | `BREAKS: <how>` |
| Earlier findings | `resolved` | `open` |

The first cell of a requirements row is the item's id (`FR-003`, `SC-002`, or `US2-4` for story 2's
scenario 4). A **defined** requirement id is one on a line starting `- **FR-NNN**` or
`- **SC-NNN**` in `spec.md`; an id merely mentioned in prose is not one.

### Validation (`review.sh record --plan`)

- Refused as `ready` when: a pass section is missing; a pass has no row; a row's status is not one
  of its pass's statuses; a row is failing; a defined `FR-NNN` or `SC-NNN` id of `spec.md` has no
  requirements row, or `spec.md` is missing or defines no `FR-NNN` id at all; an `Earlier
  findings` row is `open`. The refusal names the pass and the row.
- A `changes needed` report is recorded even with failing rows (they are its findings), but still
  needs every pass section: an unfinished review is refused whatever it says.
- `### Earlier findings` is required when the last recorded round's `Findings:` total is above 0
  (a 2.7.0 record with no `Findings:` line counts as 0), and holds no `none:` row. Its number of
  rows is not checked: the reviewer writes one per earlier finding it was given.
- Every finding of the report carries `[area: <name>]`, the name one word of `[a-z0-9-]`, and
  their number equals the report's `Findings:` total. A report with no `Findings:` line is
  refused, and so is one whose `Findings:` total is below its number of failing rows (each failing
  pass row, and each `open` row of `Earlier findings`, is also a finding, listed and tagged like
  any other).
- The `size` pass has one row per task id of `tasks.md` (its first cell is the id); a missing
  task is refused, as a missing requirement id is.
- Refused whatever it says when an area is `due` (below) and the report has no `## Simplify:
  <area>` for it, or when an area is `asked` and not answered.
- Nothing is written (record, kept copy, area log, events) until every check has passed: a refused
  report leaves no trace.

## Kept copy of the plan

`.git/landspec-review/plan-<feature>.reviewed/`: the folder as the last recorded round read it (any
verdict), replaced on each record. `review.sh diff --plan` prints `git diff --no-index` of it
against the feature folder, issue numbers stripped on both sides.

## Area log

`.git/landspec-review/plan-<feature>.areas`: one line per finding, `<round number> <area>`, plus
`due`, `asked` and `reset <area>` lines. An area's count is its finding lines since its last
`reset`.

**One open question per area**: `due <area>` is written, and `record` prints `SIMPLIFY=<area>`,
only when the area's count reaches 3 and no `due` or `asked` line is open for it; findings in an
area with an open question are logged but write nothing new. Every due area gets its own
`## Simplify: <area>` section in the next report (then `asked <area>` is written) and its own
`review.sh answer --plan <area> <text>`, which writes `reset <area>`. `answer` is accepted only for
an `asked` area: an area only `due` has no reviewer's section to answer yet. The count restarts at
the answer.

## Events (`.git/landspec-events`)

New or changed lines (`lib.sh event`):
- `review round=plan verdict=<v> feature=<dir name> h=<n> m=<n> l=<n>`;
- `issues feature=<dir name> created=<n>`, once per `issues.sh` run that created or linked issues;
- `outside feature=<dir name> n=<n>`, from `review.sh outside --plan <n>`.

## Task delta count (#216)

`outside <last>` counts the numstat of `<base tree>..<tip>`, where `<base tree>` is `<last>` when
the branch's merge-base with its base is an ancestor of `<last>`, and otherwise the first line of
`git merge-tree --write-tree <last> <merge-base>`. Files of the previous findings and test files
are left out, as today.

## Invariant (the plan review's record)

A plan state is `ready` only when a report recorded for exactly that state says so, with every
pass filled and passing, no `open` row in its `Earlier findings` table, and no open Simplify
question. Every
refusal of `record` and `check` follows from this one rule; in particular `check --plan` (and so
`issues.sh` and `pr.sh spec`) refuses while a Simplify question is open, even when the last
recorded round said `ready`.

## Moved to a follow-up feature

The 12-task split, the second reader, and the plan delta (spec User Story 3; FR-006, FR-007,
FR-010, FR-011). There is one record kind (a full plan round) and one kept copy.
