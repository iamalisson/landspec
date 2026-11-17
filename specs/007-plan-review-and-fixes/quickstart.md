# Quickstart: validating the changes

All local; CI runs the same (`linux`, `bash32` and macOS jobs). The fixtures live in
`tests/fixtures/plan-review/`.

| # | Run | Expect |
|---|---|---|
| Q1 | `tests/run.sh` | all pass |
| Q2 | `tests/review.test.sh` (plan tables) | a `ready` report with every pass filled and passing is recorded; the same report with one `MISSING`, one `FALSE`, one empty pass, one missing pass, or one `FR-NNN` of the fixture spec without a row is refused, naming the pass and row; a `changes needed` report with failing rows is recorded |
| Q3 | `tests/review.test.sh` (state) | a one-line edit of `data-model.md` changes the state; ` — #N` added to `tasks.md` does not; a 2.7.0-style record makes `check --plan` refuse once |
| Q5 | `tests/review.test.sh` (areas) | three recorded findings in one area print `SIMPLIFY=<area>`; the next report without `## Simplify: <area>` is refused; the round after it is refused until `answer --plan`; two findings in each of two areas print nothing; a round after one with findings without `### Earlier findings` is refused |
| Q7 | `tests/review.test.sh` (#216) | full review, then the base gains 300 lines and is merged into the branch, then a 5-line fix: `record --delta` accepted; with a 30-line fix: refused, counting 30; with a conflict resolved by 3 extra lines: those 3 count |
| Q8 | `tests/stats.test.sh` | a log of 4 plan rounds (2 with findings), one issues event and two outside events (1 and 2): `PLAN <f> rounds 4 (2 ready) | findings … | first->issues <m>m | outside 3` |
| Q9 | `tests/security-scan.test.sh` | a fake semgrep exiting 2 with an empty log and one error in its JSON: the line holds that message and names `semgrep.json`; with log text: names the log; both empty: says so |
| Q10 | `tests/formatters.test.sh` | a fixture repo with a local formatter hook rewriting 9 of 10 `.py` files: `REWRITES=<hook> 9/10`, and `git status` of the repo is clean after; 1 of 10: no `REWRITES=`; no config: `FORMATTERS=skipped …` |
| Q11 | `tests/static.test.sh` | the three copies of `review.md` are identical; the eight pass names in `review.md` match the ones `review.sh` checks |
| Q12 | A real plan review of this feature's own folder, after the change is merged (manual) | the report has the eight tables; `record --plan` accepts it only when they pass |
| Q14 | `tests/static.test.sh` (installed skills) | the rule is in review.md once, with the YES/NO evaluation, the `landspec:*`/`speckit-*` exclusion and the reviewer's limits; the implementer, the reviewer and branch.md point to it; `Skills:` is in the report, the return and *Evidence*; removing any one fails the check (SC-010) |
| Q13 | Each new check with its behavior disabled | it fails; the PR says so (constitution) |
