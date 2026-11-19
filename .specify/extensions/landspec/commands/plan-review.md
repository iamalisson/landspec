---
description: "Ground the plan in the code, review it once and commit the spec folder on the feature branch"
---

# Plan review (after `/speckit-tasks` and `/speckit-converge`)

Before any task is built, the plan is checked against the real code and read once by an independent
reviewer; then the spec folder is committed on the feature's branch. No GitHub issue is created:
progress is the PR's task table and `/landspec:next`. This runs automatically after
`/speckit-tasks` and after `/speckit-converge` (for the lines it added); running it again reviews the
current plan.

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
   - **Inputs:** every file, data set, URL or credential a task reads is on the feature branch, in
     the spec folder, or written out in the task itself. Whoever builds the task has a clean copy
     of the feature branch, not your tree: a file that is only untracked here (`git ls-files
     --others --exclude-standard`) is missing for them. Move it into the spec folder or put its
     content in the task.
   - **Commands:** for every command in *Completed when* and in `quickstart.md`, read what it
     really runs (the `justfile`/`Makefile`/script, its default arguments, what it logs) and
     confirm it shows what the step claims, run from any clone and directory: `gh` names its
     `--repo`, paths start at the repository root.
   - **Writes:** every step that writes data names its target and refuses production (an
     explicit dev config, a check of the database name or host).
   - **Independent tests:** expected values are literals in the test, never imported from the
     code under test.

   Never renumber tasks. A missing task is appended with the next free ID; an existing task gets
   sub-bullets added or fixed, not a new line. Report what changed in one short list.
2. **One independent review of the plan.** Launch the reviewer exactly as `commands/review.md`
   (`/speckit-landspec-review`) says, as a plan review: one `landspec:reviewer` subagent, with
   `model` and `isolation: "worktree"` as review.md says, given that file and the feature folder,
   nothing of your own conclusions. The reviewer writes its report to a file itself: record the file
   its first line names (`Report file: <path>`) as it is, never a copy you typed or edited:
   `bash .specify/extensions/landspec/scripts/review.sh record --plan <file>`.
   - Only a **high** finding sends the plan back: fix it in `tasks.md` and `plan.md` under the
     rules of step 1, then run one more pass and record it the same way. Every round is read cold:
     pass it only the facts review.md lists for a plan review (the feature folder, the last
     round's report and the output of `review.sh diff --plan`), never your replies to its
     findings; it checks each earlier finding in its own table.
   - If that extra pass still has a **high** finding, the plan is blocked: show its high findings
     and stop, with no commit and no `/landspec:implement` line. The developer fixes the plan and
     runs this command again.
   - **Medium** and **low** findings are shown to the developer, one line each; they never force
     another pass.
3. **Commit the spec folder on the feature branch.** Be on the feature's branch (the
   `after_specify` hook made it; `bash .specify/extensions/landspec/scripts/branch.sh <feature>`
   switches to it). Stage only the spec folder (`git add specs/<feature>/`), commit it as
   `docs(specs): <feature> plan and tasks` (in the language the project's rules, `AGENTS.md` or
   `CLAUDE.md`, ask for commits in), and push the branch (`git push -u origin <branch>`). Nothing
   to commit is fine. On a refusal (a guard, a hook, a rejected push), show its message and stop.
4. End with one line: on level `full` (`level:` in
   `.specify/extensions/landspec/landspec-config.yml`), "run `/speckit-analyze` next"; otherwise
   "run `/landspec:implement <feature>` to build every task", with any medium or low finding of
   step 2 listed above it.
