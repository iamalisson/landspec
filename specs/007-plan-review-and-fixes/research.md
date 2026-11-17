# Research: a plan review that can be trusted, and the open bugs

Each decision names the code it rests on, read at `origin/main` 1a02a82 (2.7.0).

## R1. One reviewer per round fills every pass's table; the record enforces the tables

- **Decision**: a plan review round stays one `landspec:reviewer`. Its report holds one section per
  pass (`### Pass: <name>`, data-model "Plan review report"), each a table with one row per item,
  and `review.sh record --plan` refuses a `ready` whose tables are missing, empty or failing.
  Coverage of the requirements is checked mechanically: every `FR-NNN` and `SC-NNN` id in
  `spec.md` must have a row in the requirements table.
- **Rationale**: #188's root cause is that "ready" never says what was covered. A table per pass,
  checked by the script, turns "I read it" into rows that can be counted; the id check makes the
  one pass whose items are numbered impossible to sample. One reviewer keeps the record and the
  `Report file:` contract (`review.md:24-30`) as they are.
- **Alternatives**: one reviewer per pass, in parallel (#188 proposal 1). Seven agents per round
  multiplies the cost of every round, and `record --plan` would have to merge seven reports with
  one plan state. Kept as a later step if the tables alone do not converge (SC-008 measures it);
  the report format already allows it, since each pass is its own section.

## R2. The passes and their statuses

- **Decision**: eight passes, in this order: `size`, `requirements`, `rules`, `claims`, `inputs`,
  `guards`, `rollout`, `orderings`. The last column of every row is its status:
  - passing: `proven`, `SAME`, `TRUE`, `provided`, `handled`, `safe`, `holds`, or `none: <why>`;
  - failing: `MISSING`, `DIFFERENT: <what>`, `FALSE`, `BREAKS: <how>`.
  The existing checklist items of `review.md:136-170` (Impact, Completed when, Shape, Inputs,
  Reuse, Spec-folder code, Orderings, Commands, Ships dark) are kept and placed in their pass:
  Inputs and Commands in `inputs`, Impact and Reuse in `claims`, Ships dark in `rollout`.
- **Rationale**: a fixed, small vocabulary lets the script refuse a failing row without reading
  prose, and the same report says both what was checked and what failed. `size` comes first so a
  plan too big is caught before the detailed passes (US3).
- **Alternatives**: free-form findings plus a coverage list (what the 2.7.0 report has): it cannot
  be checked, which is the reported problem.

## R3. The reviewed text is kept, so a fix round can be given only what changed

- **Decision**: `record --plan` keeps a copy of the feature folder it recorded (the state matched,
  so the copy is the text the reviewer read): the last reviewed copy, under `.git/landspec-review/`. A new
  read-only `review.sh diff --plan` prints the diff of the feature folder against it.
- **Rationale**: FR-004 (fix rounds read the changed paragraphs as new text) needs the text that
  was reviewed, and today only its hash is kept
  (`review.sh:53-56`). Copies live in `.git`, like every record, so nothing dirties the tree.
- **Alternatives**: git history of the spec branch: the author edits before committing, and the
  review is of the working tree, so a commit does not mark what was reviewed.

## R4. A fix round is never given the author's answers

- **Decision**: after `changes needed` the author passes the earlier round's report and the output
  of `review.sh diff --plan`, never answers. The reviewer runs every pass on the changed paragraphs
  (and reads the rest as in a full round) and fills an `### Earlier findings` table: one row per
  earlier finding, `resolved` with the line that resolves it, or `open`. `review.md:69-71` and the
  "same class" rule of `issues.md:49-53` (a full round without answers, once per class) are
  replaced by this one rule.
- **Rationale**: #187 and #188 both trace the Medium findings that appear right after a fix to the
  answers: the reviewer checks the answer instead of the text. With no answers, there is no special
  "full round" any more: every round is read cold.
- **Alternatives**: answers to a second, separate reviewer: one more agent per round for a check the
  text itself settles.

## R5. Areas and the Simplify section

- **Decision**: every finding line of a plan report starts its scenario with `[area: <name>]`
  (a data-model section or a group of tasks, named as one word of `[a-z0-9-]`, such as `area-log`). `record --plan` appends the
  round's areas to the feature's area log and, when an area reaches 3 findings since its count was
  last reset, prints `SIMPLIFY=<area>`. The author passes `simplify: <area>` to the next round,
  whose report must open with `## Simplify: <area>` (the simplest design that removes what keeps
  breaking, or moving it to a later spec); `record --plan` refuses that round's report without it.
  The round after that is refused until the author records an answer:
  `review.sh answer --plan <area> <text>`, which also resets the area's count.
- **Rationale**: FR-005. Areas are named by the reviewer, so the script cannot know two names mean
  the same thing; an exact name match is the simplest rule, and the reviewer is told to reuse the
  names of earlier rounds (it is given their reports).
- **Alternatives**: fixed areas from the data model's headings: many features have no data model.

## R6. Size check and the second reader (moved to a follow-up feature)

- **Decision**: not in this feature. The `size` pass checks each task (about 400 lines, one
  vertical slice); the 12-task split and the second reader move to a follow-up feature.
- **Rationale**: seven plan review rounds of this feature kept finding gaps between these rules,
  the plan delta and the earlier-findings count; they need their own design once the tables are
  in use.

## R7. The plan state covers the whole feature folder

- **Decision**: the plan state is the SHA-256 of every file under the feature folder, sorted by
  path (`LC_ALL=C sort`), each preceded by its path, with `tasks.md` stripped of ` — #N` as today.
  The reviewer copies the whole folder (`cp -R`) before hashing (`agents/reviewer.md` step 2,
  `review.md` subagent step 2). `state --plan <dir>` takes that copy.
- **Rationale**: #206: a fix in `data-model.md` was free while the same fix in `tasks.md` cost a
  round. Every document now counts the same.
- **Alternatives**: only `tasks.md` (smallest state): lets a contract change contradict a reviewed
  task silently, the exact class #187 reports.
- **Upgrade**: a record written by 2.7.0 holds the old hash, so `check --plan` says the plan
  changed: run the review again once (release notes).

## R8. The plan delta (moved to a follow-up feature)

- **Decision**: not in this feature (see R6). `review.sh:38` keeps refusing `--plan --delta`.

## R9. Statistics of the plan phase

- **Decision**: `record --plan` logs `event review round=plan verdict=… feature=<dir
  name> h=<n> m=<n> l=<n>` (from the report's `Findings:` line); `issues.sh` logs
  `event issues feature=<dir name> created=<n>` once it has run; a new
  `review.sh outside --plan <n>` logs `event outside feature=<dir name> n=<n>`. `stats.sh` adds one
  line per feature: `PLAN <feature> rounds <n> (<r> ready) | findings <H>/<M>/<L> per round … |
  first->issues <m>m | outside <n>`.
- **Rationale**: FR-012 and FR-013 from the log that already exists (`lib.sh:15-18`), so nothing
  leaves `.git`.
- **Alternatives**: none worth it: the log is the project's one place for these numbers.

## R10. A task delta counts the fix, not a merge of the base (#216)

- **Decision**: in `outside` (`review.sh:146-157`), when the base's merge-base with the tip is not
  an ancestor of `<last>` (the base was merged in since), the numstat is taken against a tree that
  merges `<last>` with that merge-base: `git merge-tree --write-tree <last> <merge-base>`. Its first
  output line is the tree even on a conflict (the tree then holds conflict markers), so a
  resolution's own lines count, as do lines merged from any other branch. When `merge-tree
  --write-tree` is not available (git before 2.38), the count stays as today, which only refuses
  more.
- **Rationale**: exactly the lines the fix round's commits made on top of "the last review plus the
  base as it is now". git 2.38 is from 2022; CI's runners and current macOS have newer.
- **Alternatives**: counting only `--first-parent --no-merges` patches: it drops a conflict
  resolution's lines (spec US6 scenario 4) and would count a merge from another branch as nothing.

## R11. semgrep's real error (#217)

- **Decision**: when semgrep exits with anything but 0 or 1 and `semgrep.log` is empty, the reason
  is the first `"message"` of `semgrep.json`'s `errors` (grep and sed, since busybox has neither
  python3 nor jq), cut to its first line and 200 characters, plus "see `semgrep.json`". With text
  in the log, the reason still names the log; with both empty, it says so and names both.
- **Rationale**: semgrep with `--json --output` writes its errors there (#217); the summary line
  is what the developer reads.
- **Alternatives**: dropping `--quiet`: semgrep would print progress to the log but still put the
  error in the JSON.

## R12. Formatters that would rewrite the code (#218)

- **Decision**: a new script `extension/scripts/formatters.sh` (run by `/landspec:adopt`) does
  nothing without `.pre-commit-config.yaml` or `pre-commit`. Otherwise it makes a throwaway
  worktree at `HEAD` (`git worktree add --detach` under `mktemp -d`), runs
  `pre-commit run --all-files <hook id>` there for each hook id in the config, and counts the files
  each hook changed (`git diff --name-only`) against the tracked files sharing their extensions. It
  prints one `REWRITES=<hook> <changed>/<covered>` line per hook above half, `UNCHECKED=<hook>
  <reason>` for a hook that could not run, and removes the worktree. The skill shows them with the
  two options and changes nothing.
- **Rationale**: running the hooks is the only reliable test of "would rewrite", and a worktree
  keeps the user's files untouched (constitution: nothing of the user's is overwritten).
  pre-commit has no command that lists the files a hook covers, so the extensions of the changed
  files stand in for its `types` (a shortcut, noted in the code).
- **Alternatives**: a list of known formatter ids: misses any local hook, and `blue` in #218 is
  one a list would likely not have had.
- The implementer's side is prompt only: `agents/implementer.md` returns
  `Failed: formatter <hook> rewrote <n> files outside the task's change: run /landspec:adopt` when a
  commit is refused that way.

## R13. Installed skills and MCP servers that fit a task (#234)

- **Decision**: a forced evaluation, written once as a section of `commands/review.md` that the
  implementer (`agents/implementer.md`, and `commands/branch.md` for the single-task path) and a task
  reviewer (`agents/reviewer.md`) follow first. They list the installed skills and MCP servers that could bear on the
  task, write `<name> - YES/NO - <reason>` for each, and invoke every YES. Both return a `Skills:`
  line, and the implementer's reaches the PR's Evidence (`skills/implement/SKILL.md` OPEN,
  `commands/pr.md` step 5).
- **Rationale**: a subagent with no `tools:` line inherits the Skill tool and the session's MCP
  tools, and "can still invoke unlisted project, user, and plugin skills through the Skill tool"
  (code.claude.com/docs/en/sub-agents), so access is already there; what is missing is the
  decision. In sandboxed runs of Claude Code, skills fired on 50-55% of matching prompts from their
  descriptions alone and the same with a plain instruction, and on 100% (simple set) and 75% (hard
  set) with a forced YES/NO evaluation, with no false positive on prompts with no matching skill
  (scottspence.com, "Measuring Claude Code Skill Activation With Sandboxed Evals", Feb 2026).
- **Exclusions**: landspec's and spec-kit's workflow skills (`landspec:*`, `speckit-*`) are never
  candidates, since they run the flow the agent is part of (an implementer must never open a PR); a
  skill that asks the user questions cannot run in a background agent. A plan review reads documents
  only and does not evaluate skills, so the plan report keeps its shape.
- **Alternatives**: the agents' `skills:` field preloads named skills, but landspec cannot know the
  user's skill names; a `UserPromptSubmit` hook (the source's own form) does not see a subagent's
  prompt, which comes from the Agent tool; a mapping in `landspec-config.yml` adds a setting the
  user would have to keep in step with what they installed.
- **Limits**: the figures are one author's 22- and 24-prompt sets on Sonnet 4.5. Claude Code drops
  skill descriptions past a listing budget of about 1% of the context (code.claude.com/docs/en/skills),
  so a very large set of skills can hide the right one; the docs say to install what you need.
