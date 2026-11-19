# landspec reference

The details behind the [README](../README.md): updating, what `new` sets up, stack detection
and managed files, what runs automatically, the Claude Code tools that fit, every setting, AI
attribution, and uninstalling. For why things work the way they do, see [design.md](design.md).

## Update

Plugins don't update themselves. From a terminal, one line:

```
claude plugin marketplace update landspec && claude plugin update landspec@landspec
```

Inside a Claude Code session, the same line with a `!` in front runs it there. Then
`/reload-plugins`, or restart Claude Code. **In every project that already uses landspec, run
`/landspec:init` once**: each project keeps its own copy of the extension (hooks, scripts,
review method, scaffold) under `.specify/`, and only `init` refreshes it. It keeps the project's
level, and it re-creates every file that still has the `# landspec: managed file` marker, so
commit your edits to those first, or delete the marker to keep the file as it is. Skip it and the project keeps running the old version, whatever
the plugin says. Its commit goes to the base branch (`develop` on standard and full, through the
PR `init` offers), because that is where task branches start.

From 1.8.0 on, `init` refuses to take a project back to an older version (`this plugin copy is
<plugin>, the project is at <project>; run /reload-plugins (or setup.sh --downgrade)`), for
example from a session still running the old copy. An older copy's own `setup.sh` has no such
check, so after an update run `/reload-plugins` first, then `init`. It also refuses, before it
writes anything, on a branch behind a base that `origin` already has at a newer landspec
(`origin/<base> is at landspec <version>, this branch at <version>; run it from <base>: …`):
run it again from the base. Offline, or with no `origin`, it goes on.

## What `new` does

`new` doesn't decide the critical things for you. It asks who the project is for, whether it
handles personal data or money, where it runs, and so on. Then it recommends the simplest option
that fits, and lets you argue. If your plan skips something important (tests, logging, error
handling, backups) or takes a known risk (secrets in files, weak password storage,
microservices for an MVP), it tells you why and offers the fix. For the serious risks it won't
continue until you explicitly accept them.

`new` writes **no application code**: in a spec-driven project, even the foundations arrive
through a spec. It sets up the tooling, for any stack, with today's versions:
- the stack's own project tool;
- formatter, linter, type checker, tests and mutation testing;
- a lockfile with a release cooldown, and CI;
- a dev container, plus a locked-down container for a service.

It runs the checks on the empty project, then suggests the first spec: the **foundation**
(validated config, one error type whose 500s carry an `error_id`, JSON logs with request IDs,
limits, a health check, tests at three levels). It follows three short files:
- **[GUIDELINES.md](GUIDELINES.md)**: start simple, well done and secure, and add
  complexity only when a real need shows up. Its
  [Starter checklist](GUIDELINES.md#starter-checklist) lists what `new` sets up and what
  the foundation spec covers.
- **[GUARDRAILS.md](GUARDRAILS.md)**: the common, costly mistakes and how to catch them,
  each backed by evidence.
- **[references.yaml](references.yaml)**: the primary source to check for each topic,
  so choices follow current practice, not habits from five years ago.

## Stack detection and managed files

Your stack (Rust, Node with npm/pnpm/yarn, Python with uv/pip, Go) is detected and shapes the CI
and the constitution; the constitution's **Commands** line, once `/landspec:adopt` fills it,
is what the generated CI runs. A repo whose workflows already check pull requests gets no second
CI; one whose `pull_request` filter leaves out the base branch is named
("never runs on a task PR"), so you can add that branch. Your files are never overwritten: the ones landspec generates carry a
`# landspec: managed file` first line and are re-created on `/landspec:level`; delete that
line to make one yours. Repos that run hooks through the pre-commit framework or husky get landspec's
two checks added there.

`/landspec:adopt` also runs `formatters.sh`: each hook of `.pre-commit-config.yaml` (the working
tree's, committed or not) runs with `pre-commit run --all-files <id>` in a throwaway worktree at
`HEAD`, reset before each hook, so your files are never touched. A hook that changes more than half
of the tracked files sharing the changed files' extensions prints `REWRITES=<hook> <changed>/<covered>`,
and adopt offers the two ways out: format the code once in its own PR, or remove or scope the hook.
A hook that could not run prints `UNCHECKED=<hook> <pre-commit's first error line>`; then
`FORMATTERS=checked <n> hooks`, or `FORMATTERS=skipped <why>` without a config, without `pre-commit`
or without a commit. It always exits 0. Such a hook would otherwise refuse every task's commit: an
implementer returns `Failed: formatter <hook> rewrote <n> files outside the task's change`, since
`SKIP=` is refused by the guard.

## Several features at once

Every feature is its own folder (`specs/001-login/`, `specs/002-reports/`), and everything landspec
creates carries its number: issues `[001] T003: ...`, branches `feat/001-t003-...`, the spec PR
`spec/001-login`. They never collide. The **active feature** is per clone (`.specify/feature.json`,
git-ignored): `/speckit-specify` sets it to the new feature, and `/landspec:next 002` or
`/speckit-implement 002 T001` set it explicitly. With no argument, `next` serves the active
feature; when more than one feature has tasks to build, it lists them and asks, and when only one
does, it serves that one without changing the active feature. On a task ref or the feature branch
the branch name decides, for `next` too, so a worktree never follows the main checkout.

`next.sh [feature]` reads `tasks.md` and the landing commits from the feature branch (the local
one, else origin's after a fetch; before the branch exists, the checkout's `tasks.md`) and reads no
GitHub issue. It prints one `done|failed|pending|waiting Tnnn <summary>` line per task, then
`FEATURE=<NNN> BRANCH=<branch> PR=<url|->` and `DONE=x/y NEXT=<Tnnn|>`. A task is
`done` when the branch's history holds its landing commit (`Landspec-Task: <NNN>/<id>`), `failed` while its run
record says so, `waiting` while a task its line depends on has not landed, else `pending`; `NEXT` is
the first pending one, and `/landspec:next` offers `/landspec:implement <FEATURE>`. A feature
started under the per-task flow (a task line ends in ` — #N`) named explicitly prints `LEGACY=` and
stops with the way to continue it (exit 1); with no argument such features (and their per-task branches) are left
out of the scan and never asked about, and `LEGACY=` stops it only when no other feature is left. GitHub closes a PR's `Closes #N` issues only on a merge
into the default branch; on standard and full, the managed `close-linked-issues.yml` closes them on a
merge into `develop` or `staging`, and its job fails, naming `could not close: #N`, when one of them
cannot be closed.

A task whose line says `(depends on T003)` **waits** until T003 has landed, so `next`
never offers work whose prerequisite is not done. The clause is not part of the task's summary:
a trailing `(depends on …)` (any case) is left out of the issue title, the branch slug and the text
`next` shows, before the ` in <path>` part is cut; one in the middle of a line stays. So a task
line may gain or lose a dependency: run the plan review again and record it.

A task branch can also start **stacked** on another task's branch: `branch.sh [feature] T003 --from
<branch>` starts it from that branch's head, only when that head has a recorded `ready` review, and
records the parent (`branch.<new>.landspec-parent`). Until it is moved onto the base, the stacked
branch's diff, review range and risk map are against its parent, not the base, so each task's PR
shows only its own work. `review.sh check|report|record --branch <b>` reads any branch by name, from
any checkout. Its PR (`pr.sh task`) opens into the parent's branch as a **draft**, so GitHub cannot
merge it into the parent, with `Stacked on #<parent's PR> (merge it first)` in the body; it refuses
until the parent has a PR. Where drafts are not available, it opens a normal PR and warns to merge
the parent first. A workflow whose `pull_request` branches leave out the parent never runs on that
PR, and `pr.sh` warns about each one (landspec's generated CI has no such filter). `security-scan.sh
--changed` scans only the stacked branch's own files.

`security-scan.sh` prints one line per scanner, `<tool> ok|findings|missing|skipped|failed <detail>`,
and keeps them with `--changed` as the diff's record. A finding the tool rates high or critical
prints `<tool> findings high <report>`: gitleaks for every finding, osv-scanner for a group
`max_severity` of 7.0 or more or an advisory `severity` of `HIGH` or `CRITICAL`, semgrep for a result
`severity` of `ERROR`, `HIGH` or `CRITICAL`, zizmor for a `High` severity, trivy for `HIGH` or
`CRITICAL`. `pr.sh feature --ready` refuses on a `findings high` line and lists the others.

`/landspec:implement [feature]` runs a feature's tasks in parallel instead of one per `/landspec:next`.
Each pass it runs `implement.sh restack`, then `implement.sh status --running <in flight>`, and takes
one step per listed task: `START` launches an implementer (`landspec:implementer`, in the background,
in its own copy), `REVIEW` the independent review against `base_ref <branch>`, `FIX` a fix round with
the review's report, and `OPEN` `pr.sh task` in the task's copy, parents first. The implementer works
to the reviewer's checklist (`pr.md` step 2's test rules and `review.md`'s Method step 2), and runs
`security-scan.sh --changed` and `mutants.sh` on its branch before it returns; `OPEN` runs them only
for a diff that has no record of them (after a restack, say). A fix round's review is a delta
(`review.sh record --delta --branch <branch>`), of any size, and a full review when the delta
refuses (a restack rebased the branch). `review.sh check` passes a task review with no High or
Medium finding on its `Findings:` line, and a plan review with no High. An implementer that returns nothing is marked
`red` and started again once, then `failed`. A task
that depends on an unmerged one starts stacked on its branch (`branch.sh --from`), and its PR is a draft
into the parent's. It asks nothing while it runs, never merges, and ends with the PRs to merge in
`ORDER`; run it again after merging, and it moves the stacked branches onto the base. Each pass reads
every task in `pr` with `pr.sh state`: Copilot's unanswered comments (`COPILOT=comments <n>`) mark it
`changes` with Copilot's report (`implement.sh status` lists a `changes` mark on the current head as
`fix` even over a `ready` record), so they get a fix round that counts against the task's rounds, a
full review (never a delta), and, once pushed, a reply to each thread with the implementer's answer
(`fixed in <sha>` or `not a defect: <reason>`) before it is resolved. The **hand-over rule**: a PR is
listed among the PRs to merge only on `CONFLICT=no` and `COPILOT=` `none`, `clean` or `unavailable`
(Copilot could not review, quota say: its reason is shown and nothing waits for it); any other is
listed apart with its reason (conflict with the base, GitHub still computing it, waiting for Copilot's
review, Copilot comments being answered). CI never holds a PR back: "CI passed", "CI still running"
or "CI failed: <jobs>" is shown beside each, and every PR is written `[#N](<url>)`. landspec never
requests a Copilot review: a repository's ruleset, or a person, does.

On the feature's own branch (`<branch_prefix>/<NNN>-<name>`, made by `branch.sh <feature>`),
`implement.sh status` builds one task at a time instead: it refuses without a current `ready` plan
review, a legacy feature (`LEGACY=`) or, on `full`, the analyzed marker; prints one `TASK=<id>
STATE=pending|waiting|building|built|review|changes|done|failed [ROUND=n]` line per task, then at most
one of `START=<id> REF=landspec/<NNN>-<tnnn>-task FROM=<feature head> [RESUME=yes]`, `REVIEW=`, `FIX=`
or `LAND=`, then `CHECK=yes|no`, `PR=<url|->`, `ORDER=` and `DONE=x/y`. A task is `done` when the
branch's history holds its landing commit (a message line `Landspec-Task: <NNN>/<id>`, such as
`Landspec-Task: 008/T001`). The feature's number is in it because task ids restart at `T001` in every
feature: however the branch was joined (a PR merge, a pull merge, a squash), its own landings are found
and never another feature's. `implement.sh land <task>`
lands a `ready` task whose review matches its ref: it commits the tick in `tasks.md` on the ref, merges
it `--no-ff` as `<id>: <summary>` with the trailers `Landspec-Task: <NNN>/<id>` and `Landspec-Review: ready
<patch id>`, pushes the branch and deletes the ref (`LANDED=<id> COMMIT=<sha>`); it refuses uncommitted
changes in the feature folder, and a conflict aborts the merge naming the files. `retry` also deletes
the task ref. The plan review ignores task ticks and the `**Issue**: #N` line. On upgrade, a plan
review recorded on a `tasks.md` that already had `- [X]` ticks or that line goes stale once: review the plan again.

When every task has its PR, `/landspec:implement` checks them **together**: `implement.sh check-copy`
merges every unmerged task branch in `ORDER` into `<repo>-<feature>-check` (detached at `origin/<base>`,
never pushed, kept at `refs/landspec/check/<feature>`), runs the test command there, and records the
outcome (`check-result red|green`). A conflict (`CONFLICT=<task> WITH=<earlier> FILES=…`) stacks the
later task on the earlier one for its fix round; a red run gets a fix round on the branch the failing
test covers. After a green run, a reviewer in **feature review** mode reads the spec against the
combined diff and reports each FR, scenario and SC as `met`, `not met` or `not verifiable`
(`review.sh record --feature`). `check-copy` counts attempts (`feature_rounds:`), refuses a combination
it already saw fail (`UNCHANGED=`), and waits while the feature has an open spec PR. Each `not met` item
becomes a new task, appended to `tasks.md` through a new spec PR (plan review, issues, `pr.sh spec`) in
the run's worktree, before anything is merged; gap tasks are ordinary tasks, started from the base by
the next run once that spec PR is merged.

When every task is merged, however its tasks were done, the check runs on `origin/<base>` itself, once
per base commit, before the release's bump (`RELEASE=bump` or `RELEASE=none`): `check-copy` prints
`CHECK=<path> ROUND=<n> FROM=<sha>` (`FROM`, the commit before the feature's first merged task PR, is
the feature review's base), or `CHECKED=<sha>` when that commit was already checked green and `ready`.
With no task branch to fix, a red run or a `not met` item becomes a gap task, and nothing is released.

When every task of the feature is merged, `/landspec:implement` makes the **release**, one step per
run, read each time from git and GitHub (`implement.sh release-plan`): a release PR `chore(release):
X.Y.Z` with the bump (`release-bump`) and the notes, through `pr.sh fix` and its review; once you merge
it, the tag `vX.Y.Z` on its merge commit; then the published release with those notes. It never merges.
Before the bump it runs the `full` security audit unattended on `origin/<base>`, once per commit
(`implement.sh audit-plan`, `audit-record`; the report is kept in `.git/landspec-security/`). A
confirmed critical or high finding holds the release: no bump, nothing filed or posted, and the last
line is `run /landspec:security <report>`, which tracks and fixes it. The main session runs
`/code-review high` and `/security-review` for it and hands their output to the audit. With nothing
held, the release notes get a "Known issues" section: on a public repository only a count per severity
and a neutral category, on a private one each remaining finding's title and category; never an
exploit detail. The run's last report names the scanners that were missing.

`/landspec:implement` is the default after `/speckit-tasks`: the spec PR's last line names it, and
`/landspec:next` offers it after the progress.

Merge stacked PRs **parents first**. Once a parent's PR is merged, `implement.sh [feature] restack` moves
each stacked branch, in `ORDER`, onto the base (or onto its next unmerged ancestor), and a child whose
parent got new commits onto the parent's new head. It works in its own worktree `<repo>-<feature>-run`,
pushes with a lease, retargets the PR, and marks it ready only when it now targets the base and its
review still holds (`REVIEW=kept`: the diff is unchanged); a move that changes the diff needs a new
review (`REVIEW=needed`) and the PR stays a draft until then. It leaves alone a branch checked out in
any worktree, a running task, one moved on GitHub, and one with unpushed commits
(`RESTACK_SKIPPED=<task> (<why>)`); a conflict is aborted and reported (`RESTACK_CONFLICT=<task>`).
`implement.sh [feature] stack <task> <onto-task>` stacks a started task onto another's branch the same
way.

A task is **claimed** the moment it starts: its branch is pushed to origin, empty. From then on
`next` in every clone and worktree shows it as in progress and never picks it; the clone that
started it sees it as `resume` and picks it first. When origin refuses that push (no network, no
write access, a server hook), the task still starts and `branch.sh` warns `could not claim <branch>
on origin: <git's error>`: other clones may start the same task until the branch is pushed. The
claim is exclusive: it is pushed only if the branch is still absent on origin, so when two clones
start the same task at once, the second one exits 3 with `<task> was claimed elsewhere (<branch> is
on origin)`, back where it started and without the branch. A branch that already exists, locally or
on origin, is simply switched to: that is how you continue your own task in another clone. Teammates need nothing but `/landspec:init`
once in their clone: the shared state is `tasks.md` on the base branch, the issues, and the
branches on origin.

## What happens automatically

| After / before | landspec |
|---|---|
| after `/speckit-specify` | `branch.sh [feature]`, with no task, makes the feature's one branch, `<branch_prefix>/<NNN>-<short-name>` (the spec folder's name, e.g. `feat/008-one-pr-per-feature`): it switches to it when it exists locally, tracks origin's when only origin has it, and otherwise creates it from `origin/<base>` (else the local base) carrying the spec folder's current content, uncommitted files included, commits it as `docs(specs): add <feature> spec` when it changed and pushes it with `-u`; the base is left as it was. It refuses, before any switch, uncommitted changes outside the spec folder, and a feature started under the per-task flow (a `tasks.md` line ending in ` — #N`) with `LEGACY=<feature>` and what to do. It prints `BRANCH=<name> FEATURE=<NNN> BASE=<base>`. With no argument it takes the feature `.specify/feature.json` names (what `/speckit-specify` just wrote), never the branch it runs on. On a feature branch the clone's own `.specify/feature.json` decides the active feature; only a copy without one (a fresh worktree) follows the branch name |
| after `/speckit-tasks` | `/speckit-landspec-plan-review`: the plan is **grounded in the real code** (every symbol a task removes or changes the behaviour of is searched for, with its callers, every quickstart command is read, every data write names its target), then reviewed once by a fresh agent (`review.sh record --plan`): only a high finding sends the plan back for a fix and one more pass, read cold; medium and low findings are shown to you; then the spec folder is committed on the feature branch (`docs(specs): <feature> plan and tasks`) and pushed. No GitHub issue is created: progress is `/landspec:next` and the PR's task table |
| after `/speckit-analyze` | records the analysis from its report: `analyzed.sh <report-file>` refuses a file without the report's "Specification Analysis Report" and "Coverage Summary Table", and keeps the report next to the record (level `full` needs it, for the current `tasks.md`, before tasks start) |
| after `/speckit-converge` | the same plan review for the tasks it added, then the spec folder committed on the feature branch |
| before `/speckit-implement` | refuses without exactly one task, an issue, the merged spec and a clean tree; otherwise switches to `feat/<feature>-t00x-<slug>` and pushes it to origin at once (the claim). spec-kit's implement command is told to build only that task and not tick it (the issue closing is "done"). Before writing code, the implementer (this path or a `/landspec:implement` implementer) weighs each installed skill and MCP server that could bear on the task, `<name> - YES/NO - <reason>`, and invokes every YES (never `landspec:*` or `speckit-*`); its `Skills:` line, `Skills: <name> (<what it was used for>), …` or `Skills: none matched` (`not reported` when an implementer gave none), goes in the PR's *Evidence*. No setting chooses the skills: what is installed is what is weighed, and a very large set can push descriptions out of Claude Code's skill listing budget, hiding the right one |
| after `/speckit-implement` | checks, commit, the security scan on the change, the independent review (it tries to break each thing the change claims with a concrete counterexample and to disprove each finding before reporting it, ends with a `Findings: <n> high, <n> medium, <n> low` count, is recorded for the exact diff, and is fixed until `ready`; `review.sh record` refuses an empty report file, one the reviewer named but never wrote) with `/security-review` and then mutation testing (see "Mutation testing") while it runs, both run again after any later commit, push, PR with `Closes #N` and `## Review`. The PR is refused without a recorded `ready` review for the diff, at every level, and when the constitution's test command fails (it runs before the push; with no test command, a warning says the tests were not run). A green run on a clean, committed tree is recorded in `.git/landspec-test/` for that copy of the repository, that tree and that command, and is not run again for the same three: any edit, commit or change of the command runs it again, another worktree at the same commit runs it again, and a red run records nothing. Ignored files (dependencies, `.env`, generated code) and the environment are not part of the record: changing only those does not run it again. `/landspec:implement` runs it this way when an implementer returns, so OPEN and `pr.sh` reuse that run. With a `mutate` command in the constitution, it is also refused without a `mutants.sh` result for the diff, on surviving mutants that `## Evidence` does not explain, or when the command could not run (exit 126 or 127, recorded as `unavailable`; a wrapper such as `uv run` exits otherwise, so a tool missing behind one shows as survivors); without one, the body says mutation testing was not run. It is refused without a `security-scan.sh --changed` result for the diff (missing or failed scanners and findings do not refuse; the body names each scanner that did not run, as "Scanners not run: semgrep (failed)"). Each `mutants.sh` and `security-scan.sh` run gets its own report folder (a timestamp and a random suffix), so copies running them in the same second never share one. A task review (full or delta) weighs the installed skills the same way before reading the diff and adds its own `Skills:` line after `Model:`; a skill never widens what the reviewer does or changes the report's shape; a plan review and a feature review do not weigh skills. It ends with the PR URL and the hand-over rule (`pr.sh state`: ready to merge only on `CONFLICT=no` and `COPILOT=` `none`, `clean` or `unavailable`, else the reason; the CI state shown, never waited for); on Copilot's review pending or its comments, run `/speckit-implement <task>` again: a run again on a task with an open PR verifies and fixes or answers each Copilot comment, runs the PR step from its checks (a full review), then replies to and resolves each thread |
| a PR that is not a task | a small fix, a dependency bump, landspec's own setup or level change: the same gate as a task PR at every level (recorded `ready` review, `## Review`, tests, mutants and scan for the diff), opened with `pr.sh fix "<title>" <body-file>` from its own branch, with no issue and no `Closes`. The guard blocks a raw `gh pr create`, except a promotion whose head is a long-lived branch (`develop` into `main`) |
| the feature PR | `pr.sh feature "<title>" <body-file>`, on the feature's branch only (elsewhere it refuses, naming `branch.sh <feature>`): the gates of `pr.sh fix` on the whole diff from `origin/<base>` (clean tree, `## Evidence` on `full`, `## Test changes`, mutants, the scan, the Terraform plan, the test command), but no recorded branch review and no `## Review`, since every landing commit carries its task's `ready` review. It refuses a task ticked `[X]` with no landing commit (`untick it or run /landspec:implement`), and adds to the body a `## Tasks` table (task, summary, `done`, `failed` or `pending`, landing commit, review assessment), `## End check` from the feature's end-check record (`.git/landspec-review/feature-<feature>`) when it has a `head:` (head, round, tests, assessment, its `met` / `not met` / `not verifiable` lines, and `checked at <reviewed>; the branch is now at <sha>` once the branch moved), and `Closes #N` from the `**Issue**: #N` line of `tasks.md`. It opens a draft PR, or replaces the open one's body; where drafts are not available it warns `do not merge this PR before pr.sh feature --ready` and opens a normal PR. Prints `PR=<url> READY=no` |
| an open PR, before it is handed over | `pr.sh state <pr>` (a number or the PR's URL) reads it in one GraphQL query and prints `CONFLICT=no\|yes\|unknown` (`unknown` while GitHub has not computed it), `CI=pending` (a check not completed), `fail <name> (<conclusion>),…` (failed, cancelled, timed out, action required or startup failure; a failed or errored status), `pass`, or `none` (no check: CI is shown, never waited for), and `COPILOT=`, in this order: `pending` (a Copilot review request is open), `comments <n> REPORT=<file> [RESOLVE=<id>,…]` (`n` unresolved threads Copilot opened with no comment after Copilot's own, written to `.git/landspec-review/copilot-<pr>` as `## Findings` with `- <path>:<line> thread=<id> [(outdated)] <first line>` and the comment below; `RESOLVE=` the unresolved ones already replied to), `unavailable <first sentence>` (Copilot's newest review or comment says it was unable to review), `clean` (Copilot reviewed, nothing left) or `none`. Copilot is any login matching `copilot`. It only reads: it never requests a review, and reads no clock, so in the seconds after a push, before a ruleset's request appears, a PR can read ready. `pr.sh state <pr> --reply <thread id> [<file>]` posts the file as the reply to that thread's first comment and resolves it (`REPLIED=<id>`), or only resolves a thread already replied to (`RESOLVED=<id>`); it refuses, posting nothing, a thread not on that PR, not Copilot's, already resolved, or unreplied with no or an empty file; a failed post resolves nothing, and a failed resolve exits 1 after `REPLIED=`. Limits: 100 checks, threads and reviews, 30 comments per query |
| every PR | assigned to you (a failure only warns; no milestone or project, no issue); no AI attribution lines; long output folded into `<details>` |
| a task PR that changes existing tests | refused unless the body has a `## Test changes` section saying why: adding tests to an existing file needs no explanation; a deletion, an edit or an added skip does. An added line can still weaken a test in ways this rule cannot see: the review reads it, and `review.sh risk` still flags gate lines. Tests are files under `tests/`, `test/`, `Tests/`, `__tests__/`, `spec/`, `e2e/`, `cypress/` or a `*.Tests/` folder, and files named `*.test.*`, `*.spec.*` (or with `_`, `-`), `*.cy.*`, `tests.py`, `test_*.py` or `FooTests.swift` (case-sensitive). For any other layout, add a line `tests: <regex>` (`grep -E`) to the constitution; an invalid one makes `pr.sh`, `mutants.sh` and `review.sh record` refuse. The same files are what a review's `- proven:` line may name |

These are spec-kit hooks, so you never type them. If you skip one, run it yourself:
`/speckit-landspec-plan-review`, `/speckit-landspec-pr`.

## Mutation testing

`mutants.sh` runs the constitution's `mutate` command on the branch's diff while the review runs
(after the scan and `/security-review`), and keeps the result for that exact diff; the review is
recorded and its findings fixed only after it ends, since a mutant may be in the tree until then.
Each run writes its log to its own folder, so implementers running at once never share one; `pr.sh task` and
`pr.sh fix` refuse a PR without it. A later commit means one more run; one that only adds the tests
killing survivors after a `ready` review is checked with a delta. The command is told what changed:

| Variable | Holds | For |
|---|---|---|
| `LANDSPEC_DIFF_FILE` | a unified diff of the branch against its base | tools that read a diff (`cargo mutants --in-diff`) |
| `LANDSPEC_CHANGED_FILES` | the changed source files, space-separated, tests excluded | tools that take files (`stryker --mutate`), and a project's own harness |

**A project's own harness** (a script with a fixed list of mutants, each a file and a change, that
runs the tests for each) is a `mutate` command like any tool, and it is what keeps a run short:
the whole suite runs once per mutant, so a harness that runs every case on every PR costs the
number of cases times the suite's time (116 cases of 8 s each is about 15 minutes, for a change to
one file). The contract:

- read `LANDSPEC_CHANGED_FILES`; when it is set, run only the cases whose file is in it, plus any
  case marked to run always; when it is unset (run by hand, in CI, on a schedule), run them all;
- print which cases ran and which were left out, so the log shows the run was scoped, not skipped;
- exit non-zero when a case that the tests must catch survives, or when a case's change no longer
  matches the file (a stale case proves nothing), and 0 when every case that ran came out as expected;
- run the full set somewhere it does not hold up a PR: in CI or on a schedule.

A harness that rewrites files in place also needs a lock: two runs at once would leave a mutant in
the source. landspec's reviewer runs in its own copy of the reviewed commit (`isolation:
"worktree"`), so a run it makes there never touches the author's checkout.

## Terraform plan

Only with `aws: on`, at `standard` and `full`, and only for a diff that touches a `*.tf` file,
`pr.sh task` and `pr.sh fix` need the plan recorded for this exact diff. In the root you changed:

```bash
terraform plan -out=tfplan   # git-ignore tfplan
bash .specify/extensions/landspec/scripts/tfplan.sh record tfplan   # [--chdir <root>]
```

`tfplan.sh` reads `terraform show -json` with `python3`, or the text of `terraform show -no-color`
without it (`tofu` when `terraform` is missing), and writes one section per root to
`.git/landspec-tfplan/<diff id>`: the create, change and destroy counts as Terraform's `Plan:` line
gives them (a replace is one create and one destroy), and the address of each stateful resource
(databases, buckets, tables, KMS keys, volumes, secrets, user pools) it replaces or destroys.
Addresses only: no attribute value is ever copied. Recording a root again replaces its section.
It refuses a plan file Terraform cannot read, one older than the last commit, checkout or rebase,
and one made while a `*.tf` file is uncommitted. Any later commit makes a new diff, which needs a
new plan.

A diff with no `*.tf` file but infrastructure code that is not Terraform (a `cdk.json`, a
`Pulumi.yaml` or `Pulumi.<stack>.yaml`, a `*.template.json` or `*.template.yaml`) needs no plan:
the PR body gets `## Terraform plan` with one line, `Skipped: this diff changes infrastructure code
that is not Terraform (<up to 3 paths, then "and <n> more">); the plan gate covers Terraform only.`

The PR is refused without a record, or without a section for each root in `aws_prod_paths` whose
`*.tf` files, or the local modules (`source = "./…"` or `"../…"`, followed recursively) they use,
the diff touches; the refusal names `infra_dir` as the folder to plan in. With the record, the
body gets a `## Terraform plan` section, one block per root, the stateful resources first. The
check binds the plan to the diff, not to the tree it came from: a plan made in another checkout
of the same commit is not caught.

## Measurements

The scripts append one line per step to `.git/landspec-events`, shared by every worktree of the
clone: `<epoch> <UTC time> <branch> <event> key=value...`. The events are `start` (`branch.sh`
made the branch), `review` (`review.sh record`, `round=full|delta|plan|feature` and the verdict;
a plan round also names its `feature=` and its `h=`, `m=` and `l=` counts), `issues` (older logs only: `issues.sh`, now removed, a run
that created or linked issues, `created=<n>`), `outside` (`review.sh outside --plan <n>`, the real
findings of the spec PR's outside reviewers),
`mark` and `fail` (`implement.sh`, with `branch=` named, since the run's copy is detached),
`tests` (`pr.sh`, the seconds the test command took, `ok=1` or `ok=0`; a reused green run logs
`secs=0`) and `pr` (the PR it opened or found). A write that fails is silent and never stops a
script. The file stays in `.git`: it is never pushed, and nothing from it reaches an issue or a PR.
Nothing rotates it (about 10 lines per PR).

`bash .specify/extensions/landspec/scripts/stats.sh` prints one row per feature PR and per fix PR
(and per task PR of the per-task flow); a feature PR's row also counts its tasks' refs
(`landspec/<NNN>-t<nnn>-task`), so the review rounds of every task add up on it (minutes from start to its first `pr` event, `?` with no `start` event, so a later `pr.sh` run that finds the open
PR, or marks the draft ready, does not move it; full and delta review rounds, the first verdict, the test time and runs, and `H+M`, the high and medium findings its reviews counted, `?` when no report carried the `Findings:` count line),
then one `PLAN <feature> rounds <n> (<r> ready) | findings <h>/<m>/<l> … | outside <n>`
line per feature with plan events (the counts of each plan round, `?` when its report had none; plan events
written by 2.7.0 name no feature and are grouped under `?`),
then `PRS=`, the median start-to-PR minutes, the mean rounds and how many were `ready` on
the first review. Spec PRs are left out of the rows and the totals. It reads only this clone's log, and groups by branch name, so a branch name used
twice adds both PRs into one row.

## Using Claude Code well

| Tool | Where it fits |
|---|---|
| **Plan mode** (`Shift+Tab`) | thinking out loud before `/speckit-specify` or during `/speckit-clarify`. Not for `/speckit-plan`, which writes files that plan mode blocks. |
| **`/code-review ultra`** | yourself, before merging a large or risky change (cloud, billed). The review before each PR is landspec's own `/speckit-landspec-review`: a fresh agent grounded in the whole repository, so it is not anchored on the session that wrote the code. |
| **`/security-review`** | before each PR, automatically, and inside `/landspec:security` |
| **Worktrees** | `branch.sh <feature> <task>` run in a worktree beside the repo (`<repo>-<feature>-<task>`) claims the task's branch on origin. Open a Claude Code session in it and run `/speckit-implement <feature> <task>`. Each task keeps its own branch and PR. Blocked tasks and tasks without `[P]` right after their ID are never offered. A claim that cannot be pushed only warns, so another clone may still start the same task. When you're done, remove each worktree with `git worktree remove <path>`. The active feature, the `/speckit-analyze` record and the security reports are shared by every worktree, so `full` works there too. |

## Configuration

`.specify/extensions/landspec/landspec-config.yml`:

| Key | Default | Meaning |
|---|---|---|
| `level` | `standard` | `lite`, `standard` or `full`; set it with `/landspec:level` |
| `base_branch` | `auto` | the branch task PRs target: `main` on lite, `develop` otherwise |
| `branch_prefix` | `feat` | task branches are named `<prefix>/<feature>-<task>-<slug>` |
| `review_model` | *(no longer read)* | every review (task, plan, feature) runs on `opus` in the plugin's `landspec:reviewer` agent, whatever this key says; when Opus is not available the review stops, with no fallback. `opus` is passed on every launch, so on a cheap session the review costs more than the session. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` overrides it (the launch may then leave `model` empty only when it names an Opus model; the record warns). The plugin's hook that blocks a review launch on any model but `opus`, in a fork, or without `isolation: "worktree"`, exists only where the plugin is installed. A project whose landspec copy predates that rule is refused until `/landspec:init` updates it |
| `worktree_setup` | *(empty)* | one command each `/landspec:implement` implementer runs first in its own copy (a new worktree has no git-ignored files: `pnpm install`, say); when it fails, that task is `failed` with its output. Empty: each implementer prepares its own copy as the README says, and a task it cannot prepare is `failed` (`setup: <what is missing>`) |
| `implement_model` | *(empty: the session's)* | the model of `/landspec:implement`'s implementers: `sonnet`, `opus` or `fable`; any other value is refused |
| `task_rounds` | `3` | how many `changes needed` reviews a task gets before `implement.sh mark … changes` marks it `failed` (`FAILED=<id>`; `retry` lifts it): a number from `1` to `9` |
| `feature_rounds` | `3` | how many whole-feature check attempts `/landspec:implement` makes (a conflict, a red run or a `changes needed` feature review each count once per new combination of task heads) before it stops and asks: a number from `1` to `9` |
| `version_files` | *(empty)* | the files that carry the version (`version: "X.Y.Z"` or `"version": "X.Y.Z"`), comma separated, the first one read as the current version; `/landspec:implement` bumps them for the release (minor; patch when every task is a `Fix`). Empty: no release step, only notes |
| `release_notes` | *(empty)* | the folder for each release's notes, `<folder>/X.Y.Z.md`; they are also the published release's body; without it, the notes are the release PR's body, up to its `## Evidence` or `## Review` |
| `parallel_tasks` | `4` | how many implementers `/landspec:implement` runs at once (`implement.sh status` puts at most this many, minus the running ones, in `START=`); reviewers take no slot: a number from `1` to `16`, any other value is refused |
| `aws` | `off` | `on` turns on the AWS access layer. `/landspec:level` then writes `.mcp.json` when it does not exist (the `aws-mcp` server: `uvx mcp-proxy-for-aws==<MCP_PROXY_VERSION>`, run as the `landspec-agent-dev` profile; an existing one is kept as it is, and `remove.sh` deletes it only while unchanged) and adds a "Cloud access" section per level to the constitution. `MCP_PROXY_VERSION` in `extension/scripts/pins.sh` is a PyPI release: `bin/check-tools.sh` reads GitHub releases only, so it is bumped by hand, to a release a few weeks old. `off`: nothing of this is written |
| `aws_prod_profiles` | *(empty)* | comma-separated AWS CLI profiles that reach a prod account, matched exactly; set by `/landspec:aws` (empty: one account only) |
| `aws_prod_paths` | *(empty)* | comma-separated folders whose Terraform targets prod (e.g. `infra/envs/prod`); set by `/landspec:aws` |
| `aws_agent_role` | `landspec-agent` | the agent role's name; `/landspec:aws` sets it when unset |
| `infra_dir` | `infra` | the folder holding the Terraform code, named in the plan gate's refusal; `/landspec:aws` sets it when unset, to the folder with the most `*.tf` files |

### `/landspec:aws`

`aws.sh setup [--prod-profiles a,b] [--prod-paths p,q]` sets `aws: on` and the keys above (a flag
left out keeps its value, `''` empties it), then reruns `level.sh` at the current level, which
writes `.mcp.json` and the "Cloud access" text. It never rewrites an existing `.mcp.json` or
`.claude/settings.json`: it prints the `aws-mcp` entry, or a `pin:` line when the file pins another
`mcp-proxy-for-aws` release, and each missing client entry (allow the AWS documentation tools, ask
for `run_script` and `get_presigned_url`, deny `Read(./.env*)` and `Read(**/*.tfstate*)`) as
`add to <file>: <entry>`. Then one `deploy:` line per account kind, the `aws cloudformation deploy`
of `aws/agent-role.yaml` with `Access=build` for dev (`read` on lite) and `Access=read` for prod
(printed only with prod profiles), and the `~/.aws/config` profile lines. The role trusts only an
IAM Identity Center sign-in (`TrustMode=sso`, the one mode): the users of the permission set
`PermissionSetName` names, matched exactly (`Dev` does not match `Dev_ReadOnly`), so Identity Center
is required. You run the deploy; landspec makes no AWS call.

`aws.sh setup --scp` (alone) only prints the path of the optional organization policy,
`aws/scp-agent.json`, and to attach it in AWS Organizations to the accounts the agent uses; it
changes no config key. You attach it; landspec never does.

`aws.sh check [--simulate]` (the command's later runs) says which identity Claude's AWS calls run
as, from `aws sts get-caller-identity` and, for the agent role, its `landspec:access` tag (`aws iam
get-role`). It prints `IDENTITY=`, `ACCOUNT=`, `ROLE=`, `ACCESS=` (`read`, `build` or `unknown`),
`PROD=` (the `aws_prod_profiles` list as is, or `PROD=none: no prod configured (one account only;
/landspec:aws --prod-profiles <names> adds one)` with one account only; information, never the
verdict or the exit code) and a `missing: <file>: <entry>` line per absent `aws-mcp` server or
client entry. The verdicts:

| `IDENTITY=` | When | Exit |
|---|---|---|
| `agent` | the caller is `assumed-role/<aws_agent_role>/…` | 0 |
| `user` | the caller is an IAM user (an access key or `aws login`); a refusal names the `landspec-agent-dev` profile, and a second line says `it is a long-lived access key` when `AWS_ACCESS_KEY_ID` is set without `AWS_SESSION_TOKEN` (the key itself is never printed) | 1 |
| `other-role` | any other role, e.g. an Identity Center admin permission set | 1 |
| `no-cli` / `no-credentials` | `aws` is not installed / the call fails | 1 |

`--simulate`, for the agent role only, runs `aws iam simulate-principal-policy` with the concrete
action of each line of `aws/denied-actions.txt` (and `denied-read-actions.txt` when `ACCESS=read`)
and prints `denied <action>` or `ALLOWED <action>` (`unknown <action>` when the answer has no
decision for it); any line but `denied` exits 1. It only evaluates the role's policies, its
boundary and SCPs: nothing is called or changed.

### The reviewer's copy

Every review runs in its own copy of the repository: the author passes `isolation: "worktree"`
with the facts `commit:` and `checkout:`, Claude Code makes the copy under `.claude/worktrees/agent-*`,
and the reviewer moves it to `commit:` and never writes to the checkout. A reviewer that finds
itself elsewhere, or gets no `commit:` (an older project copy: run `/landspec:init`), reports
`Copy: none (…)` and ends `changes needed`. The report's `Copy:` line names the copy, and
`review.sh record` removes it, with its `worktree-agent-*` branch, only when it is an `agent-*`
folder directly under `.claude/worktrees/`, a listed worktree at the reviewed commit, and not the
current checkout; otherwise it prints why it left it. `pr.sh` and `branch.sh` never count
`.claude/worktrees/` as uncommitted work.

### The guard's AWS rules

With `aws: on` in the repository a command runs in (its config is read once per repository top;
outside a repository the rules are off), the guard refuses, in every shell form it already parses:
`terraform`/`tofu destroy` and `apply -destroy`; `apply` whose directory (the current one, a `cd`,
or `-chdir=`) is or sits under an `aws_prod_paths` entry, or under an `AWS_PROFILE=` named in
`aws_prod_profiles`; an `aws` write verb under a prod `--profile`, `--profile=` or `AWS_PROFILE=`;
secret reads (`secretsmanager get-secret-value`/`batch-get-secret-value`, `ssm get-parameter`,
`get-parameters`, `get-parameters-by-path`, `get-parameter-history` with `--with-decryption`);
`cat`, `less`, `more`, `head`, `tail`, `bat`, `grep`, `sed`, `awk`, `strings` and `xxd` on a
`.env*` or `*.tfstate*` file (`.env.example`, `.sample`, `.template` and `.dist` are allowed),
`terraform state pull`, and `terraform show` without a plan file. Reads (`describe-*`, `list-*`,
`get-*`, `plan`, `show <planfile>`, `output`) stay allowed. The plugin hook hands the guard any
command that mentions `git`, `gh`, `aws`, `terraform`, `tofu`, `.env` or `.tfstate`.

## AI attribution

`.claude/settings.json` turns off the "Generated with Claude Code" and
`Co-Authored-By` lines for everyone on the project. landspec writes it only when the
project has no `.claude/settings.json` yet; to get the same in an existing one, add
`"attribution": { "commit": "", "pr": "" }`. If your team or a policy requires AI
disclosure, delete its `attribution` block: landspec then keeps those lines, and never asks
for the block back.

## Uninstall

From one project, `/landspec:remove`: it unregisters the spec-kit extension and preset,
deletes the files landspec created and you never edited (hooks, workflows, Dependabot, PR
template, `SECURITY.md`, `CODEOWNERS`), undoes its git hook setup and strips its block from the
constitution. A managed file that changed since landspec wrote it (against the SHA-256 it
recorded in `.specify/landspec-files.sha256`; for a project set up before 1.8.0, any file not committed
or with uncommitted edits) is kept and named `kept (edited): <file>`, and the record stays
while it names a kept file, so a second run keeps it too (`--with-speckit` deletes the record with
`.specify`, so that protection ends there). With no record, a marked file is kept only while its edit is uncommitted:
an edit you commit between two runs looks like landspec's own file, and the second run deletes it. The constitution is deleted only when it is landspec's
untouched template; any other text stays, without landspec's block. A damaged block refuses before
anything is deleted. Your specs, commits and edits stay; `develop`/`staging` and the GitHub protections
are listed for you to remove by hand. `/landspec:remove --with-speckit` also removes spec-kit's
own files, your constitution included, for a reinstall from zero with `/landspec:init`.

From Claude Code: `/plugin uninstall landspec`.
