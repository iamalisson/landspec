# Contracts: what changes, per interface

Every script below has a project copy under `.specify/extensions/landspec/` that stays identical
(`diff -r extension/scripts .specify/extensions/landspec/scripts` prints nothing), and every
prompt below has its copies kept identical too (`extension/commands/review.md`, its project copy,
and the generated `.specify/extensions/landspec/.specify-dev/agent-commands/claude/speckit-landspec-review/SKILL.md`).

## `review.sh` (plan review)

| Command | New or changed | Prints | Refuses (exit 1, one `landspec:` line) |
|---|---|---|---|
| `state --plan [<dir>]` | changed: hashes the whole folder (data-model "Plan state") | the hash | `<dir>` has no `tasks.md` or no `plan.md` |
| `record --plan <report>` | changed: checks the pass tables, the requirement ids, the earlier findings, the area tags and Simplify, keeps the copy, logs `h= m= l= feature=` | `REVIEW=ready` or `REVIEW=changes needed`; `SIMPLIFY=<area>` when one is due | each rule of data-model "Validation", naming the pass and the row; today's refusals |
| `check --plan` | changed: also refuses while a Simplify question is open | `REVIEW=ready` | today's; "a Simplify question is open for <area>" |
| `diff --plan` | new, read-only | `git diff --no-index` of the kept copy against the folder | no kept copy ("no plan review recorded yet") |
| `answer --plan <area> <text>` | new | `ANSWERED=<area>` | the area is not `asked` ("nothing is asked for <area>") |
| `outside --plan <n>` | new | `OUTSIDE=<n>` | `<n>` not a whole number |

Messages say what to run next, as today ("run the plan review again", "record an answer:
review.sh answer --plan <area> '<text>'").

## `review.sh` (task delta, #216)

`record --delta` is unchanged except for the count: lines brought by a merge of the base are not
counted (data-model "Task delta count"). Its refusal text is unchanged.

## `review.md` (Plan review) and `agents/reviewer.md`

- Subagent step 2: copy the whole feature folder (`cp -R <checkout>/specs/NNN-*/ <tmp>`), hash it
  with `state --plan <tmp>`, review the copy.
- Facts the author passes for a plan review: the feature folder; after a recorded round, that
  round's report and the output of `review.sh diff --plan`; `simplify: <a>, <b>` naming every
  area `record` printed as `SIMPLIFY=`. Never the author's answers.
- "Plan review" is rewritten as the eight passes of research R2, each with what to enumerate and
  the table to fill (data-model "Plan review report"); the existing checks are kept inside their
  pass.

## `issues.md` step 2 and `skills/implement/SKILL.md`

- Rounds until `ready`, each given only what the contract above lists; the "same class → full
  round" rule is removed (every round is read cold).
- On `SIMPLIFY=<area>`: pass it to the next round; once its report is in, show the Simplify section
  to the developer and record their answer with `answer --plan`.
- After the spec PR's outside reviewers: `review.sh outside --plan <n>` with the number of real
  findings they found.

## `issues.sh`

Logs `event issues feature=<dir name> created=<n>` at the end of a run that created or linked an
issue. Output unchanged.

## `stats.sh`

After the per-PR lines and before the totals line, one line per feature with plan events:

```
PLAN <feature> rounds <n> (<r> ready) | findings <h>/<m>/<l> <h>/<m>/<l> … | first->issues <m>m | outside <n>
```

`first->issues` is `?` when no issues event exists; `outside` is the sum of the feature's outside
events (0 when none).

## `security-scan.sh` (#217)

For semgrep only, on an exit other than 0 and 1:
- log has text: `semgrep failed exit <rc> from semgrep: code patterns not scanned; see <dir>/semgrep.log` (today's);
- log empty, JSON has an error: `semgrep failed exit <rc>: <first error message, first line, at most 200 characters>; see <dir>/semgrep.json`;
- both empty: `semgrep failed exit <rc>: semgrep wrote no error (<dir>/semgrep.log and <dir>/semgrep.json are empty)`.

## `formatters.sh` (new, #218)

`bash .specify/extensions/landspec/scripts/formatters.sh`, read-only for the user's files.

| Case | Prints | Exit |
|---|---|---|
| no `.pre-commit-config.yaml` | `FORMATTERS=skipped no .pre-commit-config.yaml` | 0 |
| `pre-commit` not installed | `FORMATTERS=skipped pre-commit is not installed` | 0 |
| no commit yet, or the worktree cannot be made | `FORMATTERS=skipped cannot make a worktree at HEAD: <git's first error line>` | 0 |
| otherwise | `REWRITES=<hook> <changed>/<covered>` per hook that changes more than half of its covered files, `UNCHECKED=<hook> <reason>` per hook that could not run, then `FORMATTERS=checked <n> hooks` | 0 |

It works in a throwaway worktree at `HEAD`, removed on exit (also on an interrupt).

## `skills/adopt/SKILL.md` and `agents/implementer.md`

- Adopt, a new step after reading the project: run `formatters.sh`; for each `REWRITES=` line,
  tell the user the hook and the count, and the two options (format the code once in its own PR,
  or remove or scope the hook); change nothing.
- Implementer: a commit refused because a hook rewrote files outside the task's change returns
  `Failed: formatter <hook> rewrote <n> files outside the task's change: run /landspec:adopt, or
  format the code in its own PR first`.

## `review.md` (Installed skills, #234)

- A section `## Installed skills and MCP servers`, the only copy of the rule, followed by the
  implementer (agents/implementer.md step 3), the single-task path (branch.md step 3) and a task
  reviewer (agents/reviewer.md): list the installed skills and MCP servers that could bear on the
  task, write `<name> - YES/NO - <reason>` for each, invoke every YES. Never candidates:
  `landspec:*` and `speckit-*` workflow skills. A skill that needs the user is `NO - needs the user`
  in a background agent; a YES that cannot be invoked is `NO - failed: <error>`, and the work goes
  on. It applies to an implementer and a task review (full or delta), not to a plan or feature
  review. A skill never widens the scope, never makes a reviewer write, run beyond
  its Method or change the report's shape, and never commits, pushes or opens a PR.
- A task report and the implementer's return carry `Skills: <name> (<use>), …` or
  `Skills: none matched`, after `Model:` in a report. A plan report is unchanged.
- The PR's *Evidence* shows the implementer's line; `Skills: not reported` when it returned none.

## Docs

`docs/reference.md`: the plan review (passes, tables, earlier findings, area tags, Simplify,
`diff`, `answer`, `outside`), the plan state, `stats.sh`'s `PLAN` line, the semgrep line,
`formatters.sh`. `docs/releases/2.8.0.md`: each issue, and "Upgrading": a plan recorded by 2.7.0
is reviewed again once; a project's copy of `review.md` must be updated with `/landspec:init`.
