---
description: "Create one GitHub issue per task and open the spec PR"
---

# Create task issues (after `/speckit-tasks`)

Every task gets its own GitHub issue, and its number is written at the end of the task's line in
`tasks.md` (`— #12`). This runs automatically after `/speckit-tasks`; running it again only
creates issues for tasks that don't have one yet. A task whose exact title (`[NNN] Tnnn: <summary>`)
is already an open issue, one GitHub created on a run that failed before the number came back,
gets that number written back (`Tnnn → #N (existing)`) instead of a second issue; a closed issue
or one with another summary never matches.

1. **Ground the plan in the code** before anyone reviews it. A plan that was never checked against
   the repo breaks on the first task. Check, and fix `tasks.md`, `plan.md` and `quickstart.md`
   in place:
   - **References:** for every symbol, table, file, route and config key a task adds, renames,
     removes or changes the behaviour of (result, failure, who it lets through), search the code,
     the tests, the docs and data files, and the other tasks; each caller is a hit. Every hit
     must be handled by some task (its *Impact* line). A task must never delete something a
     later or earlier task still uses.
   - **Guards:** find the existing tests and checks the change trips over, for example a test that
     lists every table, a schema snapshot, or a docs-vs-code check. Name them in *Impact*.
   - **Inputs:** every file, data set, URL or credential a task reads is on the base branch, in
     the spec folder, or written out in the task itself. Whoever starts the task has a clean clone
     of the base, not your tree: a file that is only untracked here (`git ls-files --others
     --exclude-standard`) is missing for them. Move it into the spec folder or put its content in
     the task. `pr.sh spec` refuses a `tasks.md` that names an untracked file.
   - **Commands:** for every command in *Completed when* and in `quickstart.md`, read what it
     really runs (the `justfile`/`Makefile`/script, its default arguments, what it logs) and
     confirm it shows what the step claims, run from any clone and directory: `gh` names its
     `--repo`, paths start at the repository root.
   - **Writes:** every step that writes data names its target and refuses production (an
     explicit dev config, a check of the database name or host).
   - **Independent tests:** expected values are literals in the test, never imported from the
     code under test.

   Never renumber tasks, and never rewrite the description of a line that already ends in `— #N`
   (its issue is linked to that ID and title). Its `(depends on …)` suffix may change: add or
   remove a dependency there, run the plan review again (step 2) and record it, then run
   `issues.sh --sync` so the issue body follows. A missing task is appended with the next free ID; a
   linked task gets sub-bullets added or fixed, not a new line. Report what changed in one short
   list.
2. **Independent review of the plan.** Launch the reviewer exactly as `commands/review.md`
   (`/speckit-landspec-review`) says, as a plan review: one `landspec:reviewer` subagent, with `model` and `isolation: "worktree"` as review.md says, given that
   file and the feature folder, nothing of your own conclusions. Save its report to a file outside the repository (`mktemp`) and record it:
   `bash .specify/extensions/landspec/scripts/review.sh record --plan <file>`. Fix what it finds in
   `tasks.md` and `plan.md` under the same rules as step 1, and run it again until it says
   `ready`. Every round is read cold: pass the next one only the facts review.md lists for a plan
   review (the feature folder, the last round's report and the output of `review.sh diff
   --plan`), never your replies to its findings; it checks each earlier finding in its own
   table. When `record --plan` prints `SIMPLIFY=<area>` (an area with 3 findings across rounds),
   pass `simplify: <area>` (every such area, `simplify: <a>, <b>`) to the next round; once its
   report is recorded, show the developer each `## Simplify: <area>` section and record their
   answer, in their words: `review.sh answer --plan <area> '<answer>'`. The round after, and
   `check --plan` (so `issues.sh` and `pr.sh spec`), are refused until every asked area is
   answered. The issue bodies are the task lines, so they must be right
   before any issue exists: `issues.sh` refuses to run without a recorded `ready` plan review for
   the current `tasks.md`. Once the spec PR (step 5) has its outside reviewers' comments, count
   the real findings among them (a comment that changes nothing in the plan is not one) and record
   that number, 0 included: `review.sh outside --plan <n>`; fix them here, as for any round.
3. Then create the issues: run `bash .specify/extensions/landspec/scripts/issues.sh` from the repository root.
   - If it fails (no `gh`, not logged in, no remote), show its message and stop. Do not create
     issues any other way.
   - Show the `Tnnn → #N` lines it printed.
   - When a run follows a fix to tasks that already have issues (a review round, a comment on the
     spec PR), run it with `--sync`: each open issue's body is rewritten from its task's current
     sub-bullets (edits made on GitHub are lost; closed issues stay as they are). Never edit the
     issue by hand instead.
4. Read the level: `level:` in `.specify/extensions/landspec/landspec-config.yml` (default `standard`).
5. Open the spec PR, so the tasks reach the base branch where task branches start from:
   - **lite**: ask "Open the spec PR now?"; on yes run
     `bash .specify/extensions/landspec/scripts/pr.sh spec`.
   - **standard**: run `bash .specify/extensions/landspec/scripts/pr.sh spec`.
   - Give it a title in the language the project's rules (`AGENTS.md`, `CLAUDE.md`) ask for commits
     in, as a Conventional Commit: `pr.sh spec "docs(specs): <what this run adds or changes>"`. It
     names the commit and, the first time, the PR, which becomes the squashed commit on the base.
     A later run updates the open PR, its body and task issues included.
   - **full**: do not open it yet. Tell the user to run `/speckit-analyze` next; the spec PR opens
     after the analysis.
   - If `pr.sh spec` stops on a stale plan review, run the plan review again, record it, and run
     `pr.sh spec` once more.
6. End with one line: the PR URL (if one was opened), and "merge it, then run `/landspec:implement`
   for the whole feature (or `/speckit-implement T001` for one task)".
