---
description: "Review, commit, push and open the task's pull request"
---

# Task pull request (after `/speckit-implement`)

**Not a task** (a small fix, a dependency bump, landspec's own setup or level change): the same
steps 2 to 6 at every level, on its own branch, with no issue. The reviewer gets one line on what
the change does and why in place of the task's line, the commit has no `Refs #`, and step 6 is
`pr.sh fix "<commit title>" <body-file>`. A raw `gh pr create` is blocked by the guard, except a
promotion between long-lived branches (`develop` into `main`), whose PRs were each reviewed.

1. Read the level: `level:` in `.specify/extensions/landspec/landspec-config.yml` (default `standard`).
   - **lite**: ask "Review and open the PR now?" and continue only on yes.
   - **standard** and **full**: continue.
2. **Checks.** Run the constitution's test command, plus lint and build if they exist. If
   anything fails, stop and report it. Never open a PR on red checks: `pr.sh` (step 6) runs the
   test command again before the push and refuses the PR, with its last 20 lines, when it fails.

   **Tests are evidence, not decoration.** Each test comes from the task's *Completed when* and
   the spec's acceptance scenarios, and must fail if the behavior breaks:
   - assert exact values, both sides of every limit (the last allowed value and the first
     refused one), the error paths, and that nothing extra leaks out;
   - when a test fails, fix the code. Never loosen an assertion, add a retry or a skip, widen
     an accepted value ("200 or 405"), or delete the test to get green;
   - if an existing test really must change (the spec changed, or the test was wrong), the PR
     body needs a `## Test changes` section saying why. The script refuses the PR without it.

   The scan and mutation testing run in step 4, before and during the review.
3. **Commit.** Commit the task's changes, and only those. Stage files by name, never
   `git add -A`. Use a Conventional Commit message, `<type>(<scope>): <summary>`, with a body line
   `Refs #<ISSUE>`. Attribution lines (`Co-Authored-By` for Claude, "Generated with") follow the
   project's `.claude/settings.json`: with landspec's default `"attribution"` block there are
   none; if the team removed that block to disclose AI use, keep them. The git pre-commit hook checks for secrets. If it refuses, remove the secret;
   never use `--no-verify`.
4. **Independent review**, the gate that catches what this session cannot see about its own
   work. First the scan, so its fixes are committed before the review reads the diff:
   - **The scanners on the changed files.** Run
     `bash .specify/extensions/landspec/scripts/security-scan.sh --changed` (it also scans uncommitted
     files). Read every finding and fix the real ones (then commit and
     run it again). List the false positives with the reason, and any `missing` scanner. The
     script in step 6 refuses a PR without a scan for this diff; findings and `missing` scanners
     do not refuse, they go in the body.

   Then launch the reviewer exactly as `commands/review.md` (`/speckit-landspec-review`) says: one
   `landspec:reviewer` subagent, with `model` and `isolation: "worktree"` as review.md says, given that file and the facts it lists (`base:` is
   `bash -c 'source .specify/extensions/landspec/scripts/lib.sh; base_ref'`), and nothing of what you
   think about the code. While it runs, run `/security-review` on the branch, then, the reviewer
   still running in its own copy, mutation testing (below); never both at once in this tree, as a
   mutation tool may edit the sources `/security-review` reads. Wait for `mutants.sh` to finish
   before you record the review, edit any file or re-run step 2: until it ends, a mutant may be
   in the tree.

   Record the file the reviewer names on its report's first line (`Report file: <path>`), as it
   is: `bash .specify/extensions/landspec/scripts/review.sh record <file>`. Then fix every **High** and
   **Medium** finding in the code (a test changes only when the test was wrong: then
   `## Test changes`, step 2). Commit the fixes (same rules), re-run step 2, and check them with a
   **delta**: pass the reviewer the `REVIEWED=` sha and the last report, and record it with
   `review.sh record --delta <file>`. It reviews the fixes only, so it ends: a real bug in a fix
   gets one more delta, and a bug it notices elsewhere goes in `## Review` or a follow-up issue. When
   `record --delta` refuses (the fix grew, or the branch was rebased), run a new full review instead.
   A first review that says `ready` needs no second round. **Low** findings and test gaps are
   fixed or listed in `## Review`; they never hold the PR. This step runs at **every level**: the
   script in step 6 refuses a PR without a recorded `ready` review for the exact diff, so a
   commit after the review means one more review. A commit that only adds tests (killing a
   survivor) after a `ready` review is checked with a delta.

   **Mutation testing proves the tests can fail.** Run
   `bash .specify/extensions/landspec/scripts/mutants.sh` (the constitution's `mutate` command on
   this branch's changes). `ok` goes in *Evidence*. `survivors` means a behavior no test checks:
   for each surviving mutant in the changed lines, add the test that kills it (then commit and
   run it again), or write one line in *Evidence* naming the survivor and why it changes nothing
   observable (log or help text). `unavailable` means the command exited 126 or 127 and never
   ran: install it or fix it in the constitution, then run it again; `pr.sh` refuses it. A wrapper
   such as `uv run` exits otherwise, so a tool missing behind one shows as `survivors`: read the
   log. `missing` means the constitution has no `mutate` command: say
   so in *Evidence* and suggest `/landspec:adopt`. With a `mutate` command, the script in
   step 6 refuses a PR without a `mutants.sh` result for this diff, and refuses `survivors` when
   *Evidence* says nothing about them; without one, it adds "Mutation testing: not run" to the
   body.

   The scan and mutation testing are recorded for the exact diff: after any later commit (a fix
   round's too), run both again.
5. **PR body**, written to a temporary file. Keep it short to read: what a reviewer needs is
   visible, the rest folds away.
   - one or two sentences on what changed;
   - `## Review`: your summary of the review, the only place it reaches the PR: what changed, each
     High and Medium finding and the commit that fixed it, the Low ones left with their reason, and
     the final assessment. A security finding is one line, `Security: reported privately (<id>)`,
     and nothing more: no file, no scenario. The script refuses a body without this section, at
     every level, and adds only what it can verify in a folded "Independent review" block: that a
     review was recorded for this diff (its patch id), its `Assessment:` line, the model it ran on
     and any warning about it, and the risk map as paths only (`Risk map (round 1)` and, after a
     delta, `Risk map (fix round)`). It never copies the report's text;
   - `## Evidence`: one visible line per result (e.g. "tests 42/42 · lint clean · scanners: no
     findings"), showing the task's *Completed when* is met. On **full** the script refuses a body
     without this section.
   - anything long (check output, scan details, false positives with their reason, screenshots)
     goes in a collapsible block, one per topic:
     `<details>` / `<summary>Test output</summary>` / blank line / the content / `</details>`;
   - attribution lines only if the project's settings ask for them (see step 3).
6. Run `bash .specify/extensions/landspec/scripts/pr.sh task <TASK_ID> "<commit title>" <body-file>`.
   On an open PR it replaces the body from `<body-file>`, so edits made on GitHub are gone.
   It pushes (the pre-push hook re-checks every commit for secrets), adds `Closes #<ISSUE>` and
   prints `PR=<url>`. The `Security` and `CI` workflows then run on the PR; they are the gate.
7. End with the PR URL.
