---
name: implement
description: "Run every startable task of a spec-kit feature at once: each in its own copy as a background implementer on its task ref, then through the independent review and one fix round, and land each on the feature branch as soon as it is ready; one draft PR for the feature. Never merges. Use for /landspec:implement, or when the user asks to run a feature's tasks in parallel."
argument-hint: "[feature]"
---

# Implement a feature's tasks in parallel

You are the main session: you start every agent, and no agent starts another. `I` below is
`bash .specify/extensions/landspec/scripts/implement.sh <feature>`, with the feature the user named
(or the one `next.sh` serves). If `.specify/extensions/landspec/` does not exist, tell the user to
run `/landspec:init` first, and stop. Make sure the working tree is clean; if it isn't, stop and say
so: never stash or discard. Then put this checkout on the feature's branch, where every task lands:
`bash .specify/extensions/landspec/scripts/branch.sh <feature>`. Ask nothing while the loop runs:
every question waits for the end.

Keep, for the whole run, the tasks whose agents (implementers and reviewers) are in flight (`in flight`), and for each task its
copy (`Copy:`), its task ref (`REF=`), its implementer (to SendMessage it), the `REVIEWED=` sha its last review record printed, and
the `Skills:` line its implementer returned.

## The loop

Each pass:

1. `I status --running <id> --running <id> …`, one `--running` per implementer in flight (left out
   when none is): only implementers take `parallel_tasks:` slots, and a task under review is kept
   from a second review by `in flight`, not by `status`. It prints one `TASK=` line per task, then
   one `START=`, `REVIEW=`, `FIX=` or `LAND=` line per task in that state, then `CHECK=`, `PR=`,
   `ORDER=` and `DONE=`.
2. One step per listed task, in the order printed, skipping any task that is in `in flight` (a task
   under review is listed in `REVIEW=` again until its reviewer returns):
   - **`START`** → launch an implementer: the Agent tool with `subagent_type: "landspec:implementer"`,
     `isolation: "worktree"`, `run_in_background: true`, and `model` from `implement_model:` in
     `.specify/extensions/landspec/landspec-config.yml` (`sonnet`, `opus` or `fable`; left out when
     empty, so it is the session's; any other value: say `implement_model must be sonnet, opus or
     fable` and stop). Its prompt: the feature, the feature branch, the task id, its line with the
     sub-bullets from `tasks.md`, the project's test command, the line's `REF=` and `FROM=`, and
     `RESUME=yes` when the line has it (the ref exists: the implementer goes on from its last
     commit). Add the task to `in flight`.
   - **`REVIEW`** → the independent review, exactly as `.specify/extensions/landspec/commands/review.md`
     says: one `landspec:reviewer` with `model: opus` and `isolation: "worktree"`, in the background,
     with the facts: `commit:` the task ref's head (`git rev-parse <REF>`), `checkout:` the task's
     copy, `branch:` the task ref (`REF=`), `base:` the feature branch, the task's line with its
     sub-bullets, and the test command. A fix or conflict round (the task has a review recorded
     before) is a **delta**, as review.md says: add the `REVIEWED=` sha you hold (in a new run, the
     `head:` line of `$(git rev-parse --git-common-dir)/landspec-review/task-<REF with each / as __>`)
     and the last round's report. Add the task to `in flight`, so the next pass does not review it
     again. When it returns, remove it from `in flight`, then record it: the first review with
     `review.sh record --branch <REF> <report>`, a fix or conflict round always `review.sh record
     --delta --branch <REF> <report>`. When `record` refuses, `I fail <task> "<its message>"`. Then
     `I mark <task> ready <report>` or `I mark <task> changes <report>` from its Assessment: a high
     or medium finding is `changes`; low ones never hold a task (`land` copies them into the landing
     commit).
   - **`FIX`** → one fix round, through SendMessage to the task's implementer, with the review that
     asked for it, the file `$(git rev-parse --git-common-dir)/landspec-run/<feature dir name>/<task>.report`
     (`mark … changes` keeps it there). With `REASON=conflict`, the round is the landing conflict
     instead: the implementer merges the feature branch into its ref, resolves the conflict, runs the
     tests, then a delta review and `land` again; send it the feature branch and the `FILES=` of
     `CONFLICT=`. Either way, if SendMessage is not available, or the agent is gone, launch a new
     implementer as in `START`, with `RESUME=yes` and the report (or the conflict). The task is in
     flight again until it returns.
   - **`LAND`** → as soon as a task is ready, `I land <task>` here, on the feature branch, one `land`
     at a time. `LANDED=<id> COMMIT=<sha>`: when it is the first landing of this run and `status` had
     `PR=-`, open the draft (below). `CONFLICT=<id> FILES=<files>`: the next `status` lists the task
     in `FIX=` with `REASON=conflict`. `status` again after every landing: a landing can make
     another task startable.

   Any `FAILED=<id>`: reported, and the run goes on with every task that does not depend on it (its
   dependants stay `waiting`); `mark`, `land` and `fail` print it.
3. Wait for the next agent to return, then go back to 1. Stop when `status` lists nothing in
   `START`, `REVIEW`, `FIX` and `LAND`, and nothing is in flight (no implementer and no reviewer).

## The draft PR

One draft PR for the whole feature: opened after the first landing, and updated at the end of each
run in which a task landed. Here, on the feature branch, write the body to a `mktemp` file: one or
two sentences on what the feature does, and `## Evidence`: the test result and each implementer's
`Skills:` line, as it returned it, under its task id; an implementer that returned none, or a run
resumed after the line was lost, gives `Skills: not reported`, never `none matched`. Then
`pr.sh feature "<title>" <body-file>` (`bash .specify/extensions/landspec/scripts/pr.sh`), the title
a conventional one for the feature (`feat(<scope>): <what it does>`), as
`.specify/extensions/landspec/commands/pr.md` says for the feature PR: no scan and no mutation
testing here (they run once, on the whole feature diff, before `pr.sh feature --ready`). It adds the
task table and prints `PR=<url> READY=no`. When it refuses, report its message; the run goes on.

## The whole-feature check

When the loop has stopped and every task is `pr` or `merged`, check them together, at most
`feature_rounds:` rounds (`check-copy` counts them, across runs). When every task is `merged`, the
check runs on the base itself, once per base commit, and only from "The release" below: after
`release-plan`, on `RELEASE=bump` or `RELEASE=none`, never on `pending`, `tag`, `publish` or `done`.

1. `I check-copy`. It prints one of:
   - `SPEC_PR=<url>`: the feature has an open spec PR (gaps already filed wait for it); skip the
     check, and the report says `merge <url> first`.
   - `UNCHANGED=<n>`: the same task heads as the last attempt that was not green (the fix round
     changed nothing, or the test is flaky); `ROUNDS_EXHAUSTED=<n>`: `feature_rounds:` attempts are
     used up. Either way, stop, and ask the developer at the end.
   - `CONFLICT=<task> WITH=<earlier task> FILES=<paths>`: stop, and report both tasks and the files.
   - `CHECKED=<sha>`: every task is merged and that base commit was already checked (green, and a
     `ready` feature review); go on with the release.
   - `CHECK=<path> ROUND=<n>`, with `FROM=<sha>` when every task is merged: go on.
2. In `<path>`, the project's test command. Red: `I check-result red`, then a fix round on the task
   branch whose files the failing test covers, and back to the loop. With every task merged (`FROM=`), there is no task branch to fix:
   `I check-result red`, the failing test becomes a gap task (step 5), and there is no release. Green:
   `I check-result green`.
3. After a green run only: the **feature review**, as `review.md` says (its feature review mode), with
   the facts: `feature review`, the feature folder, `commit:` `git rev-parse refs/landspec/check/<feature
   dir name>`, `checkout:` the repository root, `base:` `origin/<base>` (with `FROM=`: `base: <FROM>`,
   and the facts say that the diff from `<FROM>` may hold unrelated commits merged meanwhile, so the
   reviewer judges only the feature's FRs and files), the test command and its output.
   Record it with `review.sh record --feature <report>`. Its `not met` lines go into the run report.
4. `I check-copy --remove`.
5. **The gaps**, when the feature review has `not met` lines, or the base's run was red with every
   task merged: each becomes a task (a red run: `Comes from:` the failing test), through a spec PR,
   before anything is merged. The check ran only because the feature has no open spec PR, so this is
   always a new one. Work in the run's worktree `<repo>-<feature>-run` (when it is
   missing, `git worktree add --detach <repo>-<feature>-run origin/<base>`):
   - If `spec/<feature dir name>` is checked out in any worktree (`git worktree list`), print
     `SKIPPED=spec/<feature dir name> (checked out in <path>)`, say so in the report, and stop.
   - There: `git fetch origin`, `git switch --detach origin/<base>`, and `bash
     .specify/extensions/landspec/scripts/next.sh <feature>` (so the feature is the active one).
   - Append one task line per `not met` item to the feature's `tasks.md`, with the next free ids, in
     the format of the others (`- [ ] Tnnn <what> in <files>`, then the sub-bullets `Comes from:`
     the item, `What`, `Completed when`); never change the description of a line that already ends in
     `— #N` (only its `(depends on …)` suffix).
   - A plan review of those lines, as `plan-review.md` step 2 says (`review.sh record --plan`; every
     round is read cold: the next one gets the last report and `review.sh diff --plan`, never
     replies to its findings), then `pr.sh spec "docs(specs): file the whole-feature check's gaps"`.
   - `git switch --detach` there, last.

   Gap tasks are ordinary tasks: the next run starts them from the base, once the developer has
   merged the spec PR, and checks the whole feature again.

## The release

When every task is `merged` and no gaps were filed (on this run or a later one), run `I release-plan`
and act on the **one** `RELEASE=` line it prints, never on anything else; each step happens once, and the
next run reads where it stands from git and GitHub:

- `RELEASE=bump X.Y.Z FILES=… NOTES=<path> PRS=…`: first the whole-feature check on the base (above): go on
  only on `CHECKED=`, or a green run and a `ready` feature review; then the audit (below); only on `AUDIT=done`, in the run's worktree `<repo>-<feature>-run`
  (`git fetch origin`, then `git switch -c chore/release-X.Y.Z origin/<base>` as its own command): `I release-bump X.Y.Z`
  there, then write the notes to `<path>`: grouped by user story, one line per PR in `PRS=` (its
  title and number), an "Upgrading" section when a task changed a config key or a command, and the
  "Known issues" of the audit (below). Commit
  them by name (`chore(release): X.Y.Z`), push, then the review and `pr.sh fix "chore(release): X.Y.Z"
  <body>` as `pr.md` says for a PR that is not a task, then `git switch --detach origin/<base>` there.
  `NOTES=-` (no `release_notes:`): put the notes first in the release PR's body, before its
  `## Review` and `## Evidence` sections (nothing is committed for them; publish reads them there).
- `RELEASE=tag V COMMIT=<sha>`: `git tag vV <sha>` and `git push origin vV`.
- `RELEASE=publish V NOTES=<path>`: `git fetch origin`, `git show origin/<base>:<path> > "$(mktemp)"`
  (the merged notes, never the checkout's copy), then `gh release create vV --title "<project> V"
  --notes-file <that file>`. `NOTES=pr:<n>`: `gh pr view <n> --json body -q .body`, keep its text
  before the first line that is exactly `## Evidence` or `## Review`, whichever comes first (the notes);
  if nothing but blank lines is left, stop and say the release PR has no notes; else write it to a
  `mktemp` file, then `gh release create vV --title "<project> V" --notes-file <that file>`.
- `RELEASE=pending X.Y.Z PR=<n>`: the release PR waits for its merge; say so.
- `RELEASE=done V`: the feature is released; say so.
- `RELEASE=none (no version_files:)`: first the whole-feature check on the base, as for `bump`; then the audit (below); only on `AUDIT=done`, write the notes to a `mktemp` file and say the project has no
  release convention (`version_files:` and `release_notes:` in `landspec-config.yml` set one).

## The audit before the bump

On `RELEASE=bump` and on `RELEASE=none`, once the whole-feature check on the base passed and before anything else, run `I audit-plan` and act on the **one** `AUDIT=` line it
prints. The base is audited once per commit: a later run reuses the recorded result.

- `AUDIT=needed COMMIT=<sha>`: in the run's worktree `<repo>-<feature>-run`, `git switch --detach <sha>`.
  There the main session runs `/code-review high` and `/security-review` (a subagent cannot run them)
  and writes each one's output to a `mktemp` file; one that is not available here gets a file saying so.
  Then launch one background subagent (`general-purpose`) with this prompt: "In `<that path>`, run the
  `full` security audit of `${CLAUDE_PLUGIN_ROOT}/skills/security/SKILL.md` unattended, as its
  'Unattended' mode says. Step 4's `/code-review high` output is in `<code-review file>` and
  `/security-review`'s in `<security-review file>`. Write the report to `<a mktemp file>`." When it returns, take the `HOLD=<n>`
  of its last line (no such line: record nothing, say the audit did not finish, and stop the
  release), run `I audit-record <sha> <file> <n>`, then `I audit-plan` again.
- `AUDIT=done COMMIT=… REPORT=… HOLD=0`: go on with the bump (or, on `RELEASE=none`, the notes). The
  notes get a "Known issues" section from the report's findings table (severity and `confirmed` or
  `plausible` per row), by the repository's visibility (`gh repo view --json visibility -q
  .visibility`; a failed call stops the release here): on a `PUBLIC` one, only a count per severity
  and a neutral category for each (such as "input validation"); on a private or internal one, each
  confirmed medium or low and each plausible finding, with its title and category, the title
  rewritten if it carries more than what is affected. Never an exploit detail, a `file:line` or a
  request, on either. No findings: no section.
- `AUDIT=hold COMMIT=… REPORT=<path> HOLD=<n>`: the release **holds**: no bump, no release PR, and
  nothing filed or posted about the findings (no issue, advisory, PR or comment: the run report gives
  only their count and the report's path, never what they are). `/landspec:security <path>` tracks
  and fixes them without disclosing them; once the fixes are merged, the base has a new commit and
  the next run audits it again.

## When an implementer returns

When it says it is done: its `Copy: <path>` is the task's copy from now on, and its `REF=` the task
ref. A missing `Copy:` (or a path that is gone) is recreated beside the repository:
`git worktree add --detach <repo>-<feature>-<task> <REF>`. Keep its `Skills:` line. Then
`I mark <task> implemented`. It refuses with `no green test run` when the implementer's run of the
tests was not recorded for the ref's head: then, in that copy, run the project's test command as
`bash -c 'source .specify/extensions/landspec/scripts/lib.sh; landspec_cd_root; run_tests'`:

- green: `I mark <task> implemented` (it clears `red=`), then remove it from `in flight`;
- red: `I mark <task> red`. At `RED=2` (it said done twice and the tests are still red):
  `I fail <task> "tests red twice"`, then remove it from `in flight`. At `RED=1`, SendMessage its
  implementer the test output; if SendMessage is not available, or the agent is gone, launch a new
  implementer as in `START`, with `RESUME=yes` and that output. It stays in flight.

Otherwise:

- `worktree_setup` failed: `I fail <task> "worktree_setup: <its output>"`, then remove it from
  `in flight`, and go on with the others.
- Any other failure it reports: `I fail <task> "<what it said>"`, then remove it from `in flight`.
- It returned none of these (no done, no `Failed:`: it crashed or ran out): remove
  it from `in flight`. With a task ref, `I mark <task> red`: at `RED=2`, `I fail <task> "implementer
  returned nothing"`; otherwise the next `status` lists it in `START` with `RESUME=yes`. With no task
  ref, `I fail <task> "implementer returned nothing"` at once.

## End

At the end of each run in which a task landed, update the draft (above). Then show the run report,
then only what is left for the developer:

- each task's state from the last `status`, and `DONE=`; each `waiting` task with its `REASON=` (`waits
  for Tnnn`); for `REASON=locked worktree <path>` (an agent stopped mid-task), the commands to free
  it: `git worktree unlock <path>`, then `git worktree remove <path>`;
- the feature PR, written `[#N](<url>)` (`PR=` of `status`), still a draft;
- each `failed` task with its reason and, when its review rounds failed it, the findings of its last report
  (`landspec-run/<feature dir name>/<task>.report`); `I retry <task>` lifts it, and the next run starts it
  again from the feature head;
- the whole-feature check: its round, the test result, and each `not met` line of the feature review;
- the gap tasks filed, with their issues and the spec PR;
- the release: the `RELEASE=` line and what was done for it (the release PR to merge, the tag, the
  published release), and the `AUDIT=` line when there was one, with the scanners and reviews the
  report's coverage names as missing (they do not hold the release; installing them widens the next audit).

Last line, when gaps were filed: `merge the PRs in ORDER and <spec PR>, then run /landspec:implement
again`. When the release holds: `release held: <n> confirmed critical or high; run /landspec:security
<report path>`. When the release is done or was published by this run: `/speckit-specify` for the next
feature. Otherwise, while a task is not done: "run `/landspec:implement` again" (after `I retry` for a
failed one). Nothing else is left for the developer to run by hand: the whole-feature check stands in for
`/speckit-converge`, and the audit for `/landspec:security`.

The skill never merges a PR: the developer merges.
