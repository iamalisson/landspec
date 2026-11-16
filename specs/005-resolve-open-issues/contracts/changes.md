# Contracts: what changes, per interface

## `task_summary <line>` (lib.sh)

Removes `[[:space:]]*\(depends on[^)]*\)[[:space:]]*$` (case-insensitive) from `task_desc`, then
applies today's two ` in ` cuts. bash 3.2 and BSD `sed -E`: the keyword is matched case-insensitively
with a bracket class per letter (`[Dd][Ee]…`), not the `I` flag (GNU only).

## `issues.sh` / `issues.md` rule

- Unchanged commands. The plan gate stays on for the change: a dependency is plan content (a review
  finding one is how #185 started), so `issues.sh --sync` needs a recorded `ready` plan review of the
  changed `tasks.md` first, then prints `Tnnn → #N (updated)`, no create.
- Rule text (all four copies, research R2):
  > Never renumber tasks, and never rewrite the description of a line that already ends in `— #N`
  > (its issue is linked to that ID and title). Its `(depends on …)` suffix may change: add or
  > remove a dependency there, run the plan review again (step 2) and record it, then run
  > `issues.sh --sync` so the issue body follows.
- `skills/implement/SKILL.md`: "never change the description of a line that already ends in
  `— #N` (only its `(depends on …)` suffix)".

## `bin/check-tools.sh`

- Per tool: `gh api "repos/<repo>/releases?per_page=30" --jq '<newest non-prerelease with
  published_at ≤ now − 21 days>.tag_name'`, exactly `first(.[] | select(.prerelease == false and
  .published_at != null and (.published_at | fromdateiso8601) <= (now - 21*86400))) | .tag_name`
  (no output at all when none qualifies; a draft's null date is skipped, not an error). Only gh's exit status means a failed lookup; an
  empty result on success means no release is old enough → not behind (the `[[ -n "$latest" ]]`
  test in today's `|| die` chain goes).
- Output unchanged: `behind: <tool> <pin>, latest <settled>` lines, `BEHIND=<n>`; the issue body
  says "latest release out for 3 weeks" instead of "latest".
- A failed lookup still exits non-zero.

## `pins.sh`

Not changed by this feature (research R3). When the fixed checker reports a settled release, the
bump is a small fix on its own branch and PR (constitution: "a dependency bump … no spec or issue
needed"), each version with the release's own checksum or, for semgrep, the OCI index digest.

## `review.sh state --plan [<dir>]` (new action)

- Prints the plan state hash, exit 0. Writes nothing (returns before the `mkdir -p` of the record
  folder). With `<dir>`: hashes `<dir>/plan.md` and `<dir>/tasks.md` (missing file: `die`), no
  `feature_dir` lookup; without it: the active feature, as `record` does.
- Without `--plan`: `die "usage: review.sh state --plan"`.

## `review.sh record --plan <report>`

New refusals, in this order after the existing verdict and `Model:` checks:
- no `Plan state:` line: `the report has no Plan state line: run the review again (this landspec version records it)`
- a different hash: `the plan changed since this review: run the review again`

## `commands/review.md`, "Plan review" (and its two project copies)

Step added before reading: copy `<checkout>/specs/NNN-*/plan.md` and `tasks.md` into a `mktemp -d`
folder, run `bash .specify/extensions/landspec/scripts/review.sh state --plan <folder>` in your own
copy, and review those copied files. If that command fails, the report says
`Plan state: unavailable (<reason>)` and ends `Assessment: changes needed` (record refuses it). The report's fields for a plan review become `Copy:`, `Model:`
and `Plan state: <hash>` (line 204: "A plan report has only `Copy:` and `Model:`").
