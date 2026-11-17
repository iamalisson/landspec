---
description: "Independent review of the branch (or of the plan, before issues) by a fresh reader grounded in the whole repository"
---

# Independent review

A fresh reader, not the author, in one fast pass, the way GitHub's Copilot code review works: it
reads the diff and the code around it, and reports few findings, each tied to a changed line. It
catches what the author's own session misses, because that session shares the author's assumptions.

**Two roles.** If you are the author's session (`/speckit-landspec-pr`, `/speckit-landspec-issues`, or the
user ran `/speckit-landspec-review`): launch one subagent of type `landspec:reviewer` whose prompt
starts with the line `landspec review: independent reviewer`, then this whole file plus the
facts below, and nothing else: no summary of what you built, no "I already checked X". Pass the
call's `model`: `review_model:` from `.specify/extensions/landspec/landspec-config.yml` when it is `sonnet`,
`opus` or `fable`, `sonnet` when the key is absent or empty. If `review_model:` holds any other
value, print `landspec: review_model must be sonnet, opus or fable` and stop.
Never run the review on `haiku`, and never in a fork of this session. Pass `isolation: "worktree"` on the
call too: the reviewer then runs in its own copy of the repository and never writes to yours. If
the call refuses the type `landspec:reviewer` (the plugin is not installed), launch a
`general-purpose` subagent with the same prompt, the same `model` and `isolation: "worktree"`. The
plugin's hook blocks a review launch without one of those models, without that isolation, or in a
fork.
Wait for its report. The reviewer writes it to a file itself and names it on its first line,
`Report file: <path>`: record that file as it is, never a copy you typed or edited:
`bash .specify/extensions/landspec/scripts/review.sh record <file>` (`record --plan <file>` for a plan
review, `record --delta <file>` for a fix round, `record --feature <file>` for a feature review). The record is tied to the exact diff (or `tasks.md`): `pr.sh` and `issues.sh` refuse to
open anything without a recorded review that said `ready` for the current state, at every level,
so a commit after the review means another review. Recording removes the reviewer's copy (its
`Copy:` line) once it is safe to.

If you are that subagent:
0. **Your own copy, first**, before any command that writes: `git rev-parse --show-toplevel` must
   differ from the `checkout:` fact and be an `agent-*` folder directly under a `.claude/worktrees/`,
   and the facts must carry `commit:`. Otherwise run nothing but read-only commands (`git
   rev-parse`, `git status`, reading files) and `mktemp` for the report, report `Copy: none (<the
   reason>)`, and end `Assessment: changes needed`: "running in <path>" (the isolation was asked for
   but not given), or, with no `commit:` fact, "the project's landspec copy predates the plugin: run
   /landspec:init".
1. `git checkout --quiet --detach <commit>` in your own copy, and check `git rev-parse HEAD` equals
   it; if not, say so and end `Assessment: changes needed`.
2. A plan review first copies the whole feature folder (`cp -R <checkout>/specs/NNN-*/. <folder>`,
   `<folder>` from `mktemp -d`), runs `bash .specify/extensions/landspec/scripts/review.sh state
   --plan <folder>` in your own copy, and reviews those copied files; it copies a spec-folder
   script into your copy only to run it. Write `Plan state: <the printed hash>` in the
   report; if the command fails, write `Plan state: unavailable (<reason>)` and end
   `Assessment: changes needed`.
3. Never write to `<checkout>`: no editing command, no `git checkout`, `reset`, `clean`, `stash` or
   `restore` there, no lock or temp files there. Do not run a command that writes outside your copy,
   except `mktemp` for the report file.
4. Follow the method, write the report to a new file outside the repository (`mktemp`), and return
   `Report file: <path>` on the first line, then the report exactly as written there.

Facts the author passes:
- `commit:` the reviewed commit (`git rev-parse HEAD`) and `checkout:` the repository root
  (absolute), so the reviewer can check it is not in your checkout and move its copy to that commit;
- the base branch and the branch under review, and `base:` the ref the branch is diffed against
  (`base_ref` in landspec's `lib.sh`: `origin/<base>`, or the parent task branch of a stacked
  branch), or, for a plan review, the feature folder `specs/NNN-*/`;
- for a feature review: "feature review", the feature folder, `commit:` the check copy's merge result
  (`refs/landspec/check/<feature>`, a local ref your copy can reach), `base:` `origin/<base>`, and the
  test command's output on that combination;
- the task's line from `tasks.md` with its sub-bullets, "plan review", or, for a PR that is not a
  task (`pr.sh fix`), one line on what it changes and why;
- the path of the PR body draft, if there is one;
- the project's test command (the constitution's **Commands** line or its landspec block);
- for a fix round (a **delta**): the `REVIEWED=<sha>` the last `record` printed and the path of
  that round's report;
- for a plan review: the feature folder; after a recorded round, the path of that round's report
  and the output of `bash .specify/extensions/landspec/scripts/review.sh diff --plan`, and nothing
  the author wrote about the findings. When the last record predates the kept copies (a 2.7.0
  record: `diff --plan` dies "no plan review recorded yet"), the folder and that round's report,
  with no diff: the round reads the whole folder. When the last `record --plan` printed
  `SIMPLIFY=<area>` lines, `simplify: <a>, <b>` naming every one of them.

**A delta** reads `git diff <sha>..HEAD` only: it checks that each previous finding is fixed and
applies step 2 to the fix commits alone, and it never widens, with one exception: a fix commit that
changes how a function fails makes every caller of that function part of the fix (step 2's caller
account applies to them, in the diff or not). A bug it notices outside those
commits is reported at its true severity and does not change the assessment. `record --delta` refuses it unless a round was
recorded on this branch, `<sha>` is still on the branch, something was committed since, and the fix
changes at most 20 lines outside the previous findings' files (test files aside); otherwise run a
new full review. Lines a merge of the base brought in are not counted (a conflict resolution's
lines and a merge of any other branch are).

**A feature review** checks the whole feature, all its task branches merged together, against its
spec: read `spec.md` (every FR, every acceptance scenario, every SC), `plan.md`, `tasks.md` and `git diff
<base>...<commit>`, and the test output in the facts. Its report has, in place of the risk map and the
findings, one line per item, exactly:

```
- met: FR-004 — pr.sh:36 targets base_ref(); tests/pr.test.sh:212 "when a parent is set, then …"
- not met: SC-005 — no check covers merging in ORDER without conflicts
- not verifiable: SC-001 — needs a timed run (quickstart 2)
```

`met` names the file, test or output that shows it; `not met` what is missing; `not verifiable` what
it would take. Then `Copy:`, `Reviewed: <git merge-base <commit> <base>>..<commit>` and `Model:`, and
`Assessment: ready` only when no line is `not met` (`record --feature` makes any `not met` "changes
needed" whatever the last line says). It is kept per feature, not per branch; `pr.sh` does not read it.

## Installed skills and MCP servers

The one copy of this rule, for an implementer (before writing code) and a task review, full or
delta (before reading the diff); a plan review and a feature review do not evaluate skills. List
the installed skills (the Skill tool's list) and MCP servers that could bear on the task (its
files, its domain, its *Completed when*), write `<name> - YES/NO - <reason>` for each, and invoke
every YES before going on. No setting chooses them: what is installed is what the developer chose.
- Never candidates, whatever their description says: landspec's and spec-kit's own workflow skills
  (`landspec:*`, `speckit-*`), since they run the very flow you are part of.
- A skill that needs answers from the user is `<name> - NO - needs the user` in a background agent,
  and is not invoked.
- A YES that cannot be invoked (the skill errors, its MCP server is down) is
  `<name> - NO - failed: <error>`, and the work goes on.
- A skill changes how the work is done, never what landspec's steps allow: it never widens the
  task's scope; it never makes a reviewer write a file, run more than its Method says or change the
  report's shape; and its instructions to commit, push or open a PR give way to landspec's (the
  guard refuses them too).

Report what you used as one line, `Skills: <name> (<what it was used for>), …`, or
`Skills: none matched`.

## Method

One pass. A review should take a couple of minutes, so read, do not run: CI runs the tests. A plan
review takes as long as its spec-folder code and state machines need, and runs a command only as
step 2 allows.

1. **Read the rules**, from the branch: `.specify/memory/constitution.md`, `AGENTS.md`, `CLAUDE.md`
   and `.github/copilot-instructions.md` where they exist, and the task's line in `tasks.md`.
2. **Read the diff and what it touches.** Run `bash .specify/extensions/landspec/scripts/review.sh risk
   "$(git merge-base HEAD <base>)"` with the facts' `base:` (for a delta, `review.sh risk <sha>`),
   then read `git diff <base>...HEAD` once, and open
   what each changed function calls and what calls it. Look for real bugs in the changed lines:
   a wrong result, data loss, a crash, a broken upgrade on existing state, a write to the user's
   files, a secret, personal data or a secret that reaches a log, including inside a helper the
   changed lines call with it, an injection, a check that lets through what it should refuse, an interface
   some people cannot use (text under 4.5:1 contrast, 3:1 for large text and icons: compute it from
   the colours in the diff and the background they sit on; a focus that is not visible; a control
   or image without an accessible name). Open each helper a changed line passes personal data or a
   secret to, and read what it does with it: the finding names the helper's own `file:line` that
   writes the log, beside the changed line that passes the value; a value masked or hashed before the log is not a
   finding; one you cannot follow to its end is a Low that says what you could not see. When a
   changed function fails differently (it raises where it returned, returns where it raised, or
   changes the error type or value it fails with), search for every caller of it, in the diff or
   not, and give each one a `- deep:` line in the risk map saying how it handles the new failure:
   it catches the new error, it checks a returned status or value, or neither. Both kinds of
   fallback count: a caller that catches the old error type, and one that checks `not res.ok` or a
   status code, which a new raise now skips. A caller whose fallback no longer runs is a finding at
   the severity of what it now breaks. Run a command only to settle whether a suspected bug or a
   counterexample is real, and only in your own copy.
3. **Try to break it.** From the task's line (or the one-line fact) and the diff, write what the
   change claims, at most five claims: what it now does, refuses or keeps. For each, build one
   concrete counterexample (an input, a state already on disk or in the database, an ordering:
   twice, out of order, interrupted, or a caller from step 2) and follow it through the changed
   lines to its result. A claim that breaks is a finding, with that counterexample as its scenario.
   One that holds names the `file:line` that stops it. In a delta, the claims are the previous
   findings: follow each one's own scenario through the fix. A plan review or a feature review
   skips this step.

**Plan review** (before the issues are created): review the copy of the feature folder
hashed with `review.sh state --plan <folder>` (subagent step 2), so the recorded state is the text
you read; apply step 1 and read every task in `tasks.md`,
asking what happens where state already exists. Then run the eight passes below, in this order,
on the whole folder. Each pass enumerates its items, never a sample, and fills its own table
under a heading exactly `### Pass: <name>`: a header row, its `|---|` line, then one row per item,
whose last cell is the row's status, one of that pass's statuses. A pass with nothing to check
writes one row, its only row, `none: <why>` (`| none: no task writes data |`). Each failing row is
also a finding. `review.sh record --plan` reads the tables: it refuses any report with a pass
missing, a pass with no row, or a status outside its pass's list, and refuses a `ready` with a
failing row (`MISSING`, `DIFFERENT: <what>`, `FALSE`, `BREAKS: <how>`), with a defined `FR-NNN` or
`SC-NNN` of `spec.md` (a line starting `- **FR-NNN**` or `- **SC-NNN**`) that has no requirements
row, with a task of `tasks.md` that has no size row, or with a `spec.md` that defines no `FR-NNN`.

**Pass `size`**: one row per task of `tasks.md`, its id alone in the first cell, then its
estimated diff with its tests and whether it is one vertical slice with an observable result:
`holds`, or `BREAKS: <why>` when the diff would clearly pass about 400 lines (name the behaviors
to split it by; generated files, lockfiles, and markup or data copied as is from an existing file
do not count) or when it is not one slice.

**Pass `requirements`**: one row per `FR-NNN` and `SC-NNN` that `spec.md` defines and per
acceptance scenario (`US2-4`: story 2, scenario 4), the id alone in the first cell, then the task
whose *Completed when* proves it: `proven`, or `MISSING`. *Completed when* proves it only as a
command that proves the real path, not only a fresh state, at the level the behavior demands
(logic: unit; through the interface: integration against the real database or in-memory HTTP; a
user-visible flow: one end-to-end). Every task names its failure path (what the caller gets, the
one log line, who is refused), and no task is a bare "error handling", "logging" or "hardening"
layer: a task that breaks this makes the rows it proves `MISSING`.

**Pass `rules`**: one row per rule stated in more than one document of the folder (a field, a
filter, a response shape, who may do something, a default, a link between entities), with the
documents compared in one cell and one status cell, last: `| <rule> | <documents compared> | SAME |`,
or `DIFFERENT: <what>` naming both documents.

**Pass `claims`**: one row per claim the plan makes about code that exists ("as today",
"existing", "callers unchanged", a `file:line`), with the evidence you read: `TRUE` or `FALSE`.
*Impact* is a claim: it names every reference the task touches and every caller of a function whose behaviour it changes (search each symbol), and the newest sibling of each file it adds; one it
misses is `FALSE`. **Reuse:** a task that adds a helper, component or package the repository or an
installed dependency already provides is `FALSE`: name the existing one's `file:line`. A new
dependency without the `plan.md` line the constitution asks for is `FALSE`.

**Pass `inputs`**: one row per thing a task's tests need (a function, a table, a file, a fixture,
a data set, a URL, a credential), with the earlier task, the base branch or the spec folder that
provides it: `provided`, or `MISSING` when only a later task provides it, or no task does.
**Inputs:** every file a task reads exists on `origin/<base>` (`git cat-file -e
origin/<base>:<path>`), in the spec folder, or in the task text; one that exists only in the
author's working tree (untracked, ignored) is `MISSING`, since the next person starts from a clean
clone. No task deletes what another task still uses. **Commands** in *Completed when* run from any
clone and directory: a `gh` call without `--repo`, or a path relative to somewhere other than the
repository root, is `MISSING`. **Shape:** a task that is one layer of a behavior another task
completes (a model here, its migration there, the endpoint in a third) is `MISSING`: name the tasks
to merge. **Spec-folder code:** every file under `specs/NNN-*/` that is not markdown is code:
apply the step 2 bug list to it, and a `research.md` claim resting on a script that hides an error
(a failed call read as empty data) is `MISSING`.

**Pass `guards`**: one row per CI job and per check that covers the whole test suite (a static
check over every file, a count, a coverage floor), against the files the tasks change: the task
that handles it, `handled`, or `MISSING`.

**Pass `rollout`**: one row per task that writes data, schedules a job or fixes a value that cannot
change later: its first day, a start in the middle of a period, the switch from what it replaces,
and the task running in production alone before the tasks after it: `safe`, or `BREAKS: <how>`. A
step that writes data names its target and refuses production. **Ships dark:** each task is safe
to reach production alone; a task that makes the feature visible to users before its last task (a
tab, route or menu entry with no flag off by default), a feature with no last task that turns the
flag on, or a migration the production code can't run against, is `BREAKS: <how>`.

**Pass `orderings`**: **Orderings:** for each state machine in
`data-model.md`, or in `plan.md` when there is none (opposite actions on one resource, events
that arrive late, twice or replayed), state its one invariant and give one row per ordering
checked against it: out of order, delivered twice, the original event replayed, opposite actions both pending; `holds`, or
`BREAKS: <how>` for one that breaks it, or for a plan that answers orderings case by case with no
invariant.

**Earlier round:** when the author passes the last round's report, a finding it raised keeps its
severity unless the text it was about changed or you name a fact that round did not have; the
report never narrows the review: read the whole plan again and run every pass, on the paragraphs
the diff changed first. Fill a table under a heading exactly `### Earlier findings`: one row per
finding of that report, its last cell `resolved` (with the line that resolves it, an invariant or
a changed text, in a cell before it) or `open`, never `none:`. An `open` row is also a finding.
`review.sh record --plan` refuses a report without that table when the last recorded round had
findings (its `Findings:` total above 0), and a `ready` with an `open` row. When that report
counted no findings (`Findings: 0 high, 0 medium, 0 low`), leave the table out.

## Report

Written for the author, who fixes it, and for the human who merges:
- **What changed**: three lines at most, in your own words from the code, not from the PR body.
- **Risk map**, before the findings, one line per path you went deep on or skipped as proven:
  `- deep: <path> — <why risky>: <what you checked>`
  `- proven: <path> by <test file>:<n> — <what it asserts>`
  Write each line exactly as shown, from the start of the line, path first. Every `RISK=` path
  needs one; `review.sh record` refuses the report otherwise, and accepts `- proven:` only when
  `<test file>` is a test file at HEAD with a line `<n>`; gate, delete and test paths take
  `- deep:` only. Anything not listed was sampled. The PR shows these paths, never the text after
  them, and only paths in the diff.
- **Claims**, after the risk map and before the findings, one line per claim of step 3:
  `- held: <claim> — <counterexample>: stopped at <file:line>`
  `- broke: <claim> — <counterexample>: finding <n>`
  Before the findings, because `review.sh record` counts every `file:line` after them as a
  finding's file, which a delta may then change freely.
- **Findings**, ranked: **High** (wrong result, data loss, a broken upgrade on existing state,
  security), **Medium** (a real bug: a guard the siblings have, an unhandled real-path
  case, a silent failure path), **Low** (worth a line, not a block: a test gap where the code
  behaves correctly, a test that cannot fail, a test that fakes the component whose behavior it
  asserts, wording). Personal data in a log is **High** when the project's rules forbid it, at
  least **Medium** otherwise. A test that fakes the component whose behavior it asserts is
  **Medium** when it is the only proof of a privacy or security rule; a fake of a component the
  test asserts nothing about is not a finding. Each one: `file:line`, one concrete
  scenario of what goes wrong ("on a database built by `create_all` and stamped at the previous
  revision, `flask db upgrade` stops with 'already exists'"), and the evidence (the sibling's
  `file:line`, the command output). Before you report a finding, try to disprove it: look for the
  guard, test, constraint, caller check or (in a plan review) the task, invariant or plan line that
  already handles it, and report it only if that search fails. A finding you could not verify says so. No style, no naming,
  no nits: they are what gets reviews ignored. Accessibility is not style: a contrast, focus or
accessible-name failure is at least **Medium**, with the computed ratio as evidence. Matching a
sibling is not a defense: a defect copied from an existing file is still a defect in this diff. A **security** finding is listed last, and the PR
  shows it as one line, `Security: reported privately (<id>)`: its detail goes to the author only,
  never into a public PR.
- **A plan report** has no risk map and no claims. In their place, in this order: one section per
  pass, exactly `### Pass: <name>` for `size`, `requirements`, `rules`, `claims`, `inputs`,
  `guards`, `rollout`, `orderings`, each followed by its table; then `### Earlier findings` in a
  round given an earlier report; then the findings, each failing row and each open earlier
  finding among them. Each finding's scenario starts `[area: <name>]`, the part of the plan it is
  about (a data-model section or a group of tasks) as one word of `[a-z0-9-]`, such as
  `[area: area-log]`; reuse the earlier report's names for the same part. `record --plan` refuses
  a report whose tagged findings do not number its `Findings:` total, a tag that is not one word,
  a report with no `Findings:` line, and a total below its failing rows.
- **A Simplify section** opens a plan report given `simplify: <area>`: one section headed exactly
  `## Simplify: <area>` for each area the facts name, before the pass tables. An area that drew
  3 findings across rounds keeps breaking under patches: write the simplest design that removes
  what keeps breaking (fewer rules, one state instead of several), or moving that part to a later
  spec, with the lines of the plan it replaces. It is a recommendation the developer answers,
  never a finding: the rounds go on, the passes run as usual. `record --plan` refuses the report
  without a section for each named area, whatever its verdict.
- Before the last line, each on its own line: `Copy: <git rev-parse --show-toplevel>` (your copy,
  or `Copy: none (<reason>)`), then `Reviewed: <from>..<head>`, the full shas you
  reviewed (`git merge-base HEAD <base>`, with the facts' `base:`, and `git rev-parse HEAD`; for a delta, `<sha>` and
  `git rev-parse HEAD`), and `Model: <your model id>`. A task report (full or delta) then has
  `Skills: <name> (<what it was used for>), …` or `Skills: none matched` (see "Installed skills and
  MCP servers"). A delta report also has `Delta from: <sha>`. A plan report does not evaluate skills
  and has only `Copy:`, `Plan state: <hash>` (or `Plan state: unavailable (<reason>)`) and `Model:`.
  `review.sh record` refuses a report without them, a range that is not the
  branch's (or the delta's), a commit made after the review started, and a plan state that is not
  a hash or not the plan's current one. Then one count line, exactly
  `Findings: <n> high, <n> medium, <n> low` (security ones included; `record --plan` checks it against the tagged findings).
- The last line, exactly: `Assessment: ready`, or `Assessment: changes needed` when there is a
  High or Medium in the lines this review covers (the branch's diff, or a delta's commits). `review.sh record` reads that line; without it the report cannot be recorded.

The PR never shows this report: its "Independent review" block holds only the recorded facts (a
review of this diff, by patch id, the `Assessment:` line, the model and any warning about it, and
the risk map's paths, round 1 and the fix round). The summary is the author's `## Review`, a
security finding as one line.
