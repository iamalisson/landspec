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
PR `init` offers), because that is where feature branches start.

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
("never runs on the feature PR into <base>"), so you can add that branch. Your files are never overwritten: the ones landspec generates carry a
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

Every feature is its own folder (`specs/001-login/`, `specs/002-reports/`) and its own branch,
`<branch_prefix>/<NNN>-<short-name>` (`feat/001-login`), with one PR. They never collide. The
**active feature** is per clone (`.specify/feature.json`, git-ignored): `/speckit-specify` sets it
to the new feature, and `/landspec:next 002` or `/landspec:implement 002` set it explicitly. With no
argument, `next` serves the active feature; when more than one feature has tasks to build, it lists
them and asks, and when only one does, it serves that one without changing the active feature. On a
task ref or the feature branch the branch name decides, for `next` too, so a worktree never follows
the main checkout.

`next.sh [feature]` reads `tasks.md` and the landing commits from the feature branch (the local
one, else origin's after a fetch; before the branch exists, the checkout's `tasks.md`) and reads no
GitHub issue. It prints one `done|failed|pending|waiting Tnnn <summary>` line per task, then
`FEATURE=<NNN> BRANCH=<branch> PR=<url|->` and `DONE=x/y NEXT=<Tnnn|>`. A task is
`done` when the branch's history holds its landing commit (`Landspec-Task: <NNN>/<id>`), `failed` while its run
record says so, `waiting` while a task its line depends on has not landed, else `pending`; `NEXT` is
the first pending one, and `/landspec:next` offers `/landspec:implement <FEATURE>`. `NEXT` empty with
`DONE=y/y` means the end check or the PR is what is left.

A task whose line says `(depends on T003)` **waits** until T003 has landed, so no task starts on
work whose prerequisite is not done. The clause is not part of the task's summary: a trailing
`(depends on …)` (any case) is left out of the text `next` shows and the landing commit's title,
before the ` in <path>` part is cut; one in the middle of a line stays. So a task line may gain or
lose a dependency: run the plan review again and record it.

Teammates need nothing but `/landspec:init` once in their clone: the shared state is the feature
branch on origin, its `tasks.md` and its landing commits. Task refs, run records and test records
are local to a clone; a task with no landing commit is simply built again from the feature head.

**Per-task features (legacy).** A feature started under the old per-task flow (a `tasks.md` line
ending in ` — #N`) is not migrated. `next.sh`, `implement.sh` and `branch.sh` named on it print
`LEGACY=<feature>` and stop (exit 1) with what to do: finish its open PRs as ordinary PRs, then
delete the ` — #N` suffix (and close the issue) of each remaining task to continue it under this
flow. With no argument such features (and their branches) are left out of `next`'s scan and never
asked about, and `LEGACY=` stops it only when no other feature is left. `release-plan` keeps the old
path for them, so a feature finished that way still releases. GitHub closes a PR's `Closes #N`
issues only on a merge into the default branch; on standard and full, the managed
`close-linked-issues.yml` closes them on a merge into `develop` or `staging`, and its job fails,
naming `could not close: #N`, when one of them cannot be closed.

## Building a feature: `/landspec:implement`

`/landspec:implement [feature]` builds every task of a feature on its one branch, in parallel, and
keeps one draft PR up to date. It asks nothing while it runs and never merges. Each pass it runs
`implement.sh status [--running <task>]…`, which refuses without a current plan review with no high
finding (`review.sh check --plan`), a legacy feature (`LEGACY=`) or, on `full`, the analyzed marker.
It prints one `TASK=<id> STATE=pending|waiting|building|built|review|changes|done|failed [ROUND=n]`
line per task, then one `START=<id> REF=landspec/<NNN>-<tnnn>-task FROM=<feature head> [RESUME=yes]`
line per task whose dependencies are done and which is not done, failed or running, in `ORDER`, while
fewer than `parallel_tasks` implementers are in flight (the `--running` ones count; reviewers take no
slot), one `REVIEW=<id>`, `FIX=<id> [REASON=conflict]` or `LAND=<id>` line per task in that state,
then `CHECK=yes|no`, `PR=<url|->`, `ORDER=` and `DONE=x/y`. The main session takes one step per line:

- `START` launches an implementer (`landspec:implementer`, in the background, in its own copy) on
  the task ref, a local branch that starts at the feature head and is never pushed
  (`branch.<ref>.landspec-parent` names the feature branch, so its diff and its review are against
  the feature head). `RESUME=yes`: the ref exists from an interrupted run, and the implementer goes
  on from it. A ref checked out in a locked worktree makes the task `waiting` with `REASON=locked
  worktree <path>`. The implementer works to the reviewer's checklist (`pr.md` step 2's test rules
  and `review.md`'s Method step 2) and runs the tests through `run_tests` after its last commit:
  `implement.sh mark <task> implemented` refuses a task ref whose head tree has no recorded green
  run (`no green test run for <ref> at <sha>`; with no test command it is accepted), and the tests
  are not run again for that tree. When that run is missing, the main session runs the tests in the
  task's copy: red marks the task `red` and sends the output back to its implementer once; red again
  (`RED=2`) fails it, and so does an implementer that returns nothing twice. The implementer returns
  its `Copy:`, its `REF=`, its `Skills:` line and one `Test changes: <file> <why>` line per existing
  test file it changed (or `Test changes: none`); the main session keeps them for the PR body.
- `REVIEW` launches one Opus review of the task ref's diff, in the background, and the task stays
  in flight until it returns (so it never gets a second reviewer; only implementers are passed as
  `--running`). Its report is recorded with `review.sh record --branch <ref>` (a fix or conflict
  round with `--delta`); when `record` refuses, the task is failed with its message. Then
  `implement.sh mark <task> ready <report>`, or `mark <task> changes <report>` on a high or medium
  finding; low findings never hold a task. `review.sh check --branch <ref>` passes with no high or
  medium finding on its `Findings:` line, and a review that could not run in its own copy (`Copy:
  none`) never passes.
- `FIX` sends the report back to the implementer for its one fix round, then a **delta** review
  (`review.sh record --delta --branch <ref>`) of the commits since the reviewed head, whatever the
  fix's size. At `task_rounds` (default 2: the first review and one delta) a `changes` mark fails
  the task (`FAILED=<id>`); it is named at the end, and the run goes on with the others.
- `LAND` runs `implement.sh land <task>`: it refuses unless the task is `ready` and its review
  passes for the ref's head, and refuses uncommitted changes in the feature folder. It merges the
  ref `--no-ff` into the feature branch, with the tick in `tasks.md`, titled `<id>: <summary>`, one
  `Low: <file>:<line> <title>` line per low finding of the task's review (a delta's and its first
  round's) and the trailers `Landspec-Task: <NNN>/<id>` and `Landspec-Review: ready <patch id>`,
  pushes the branch and deletes the ref (`LANDED=<id> COMMIT=<sha>`). The feature's number is in the
  trailer because task ids restart at `T001` in every feature: however the branch was joined (a PR
  merge, a pull merge, a squash), its own landings are found and never another feature's. A
  conflict aborts the merge, prints `CONFLICT=<id> FILES=<files>` and exits 1: the task gets one
  conflict round (`FIX=<id> REASON=conflict`, outside `task_rounds`: merge the feature branch into
  the ref, test, review); a second conflict marks it failed (`FAILED=<id>`).

`implement.sh fail <task> "<reason>"` marks a task failed; `implement.sh retry <task>` lifts it and
deletes the task ref, so the task starts fresh from the feature head (and gets its conflict round
back). The plan review ignores task ticks and the `**Issue**: #N` line, so landing a task never makes
it stale. On upgrade, a plan review recorded on a `tasks.md` that already had `- [X]` ticks or that
line goes stale once: review the plan again.

**The end check.** Each task review reads one diff. When every task is done (`CHECK=yes`),
`implement.sh check` checks the whole feature once, on the feature branch itself: it merges
`origin/<base>` into the branch and pushes it (a conflict stops it, naming the files), points
`refs/landspec/check/<feature>` at the head and prints `CHECK=<head> ROUND=<n>`; or `UNCHANGED=<n>`
when this head's own tests or its own feature review already failed, or `ROUNDS_EXHAUSTED=<n>` once
`feature_rounds` heads were checked. On either of those it stops: the PR stays a draft, its body keeps
what is not met, and the developer is asked at the end. The test command runs on that head through
`run_tests`, in a detached worktree (a tree already green is not run again), and `implement.sh
check-result green|red` records it. Then an Opus review in **feature mode** reads the spec against
the whole diff from `origin/<base>` and reports each FR, scenario and SC as `met`, `not met` or `not
verifiable`; `review.sh record --feature` adds its `verdict:`, `reviewed:` (the head it reviewed) and
lines. One record per feature, `.git/landspec-review/feature-<feature>`, never deleted, holds `head:`,
`heads:` (every head checked so far; the round is their count), `tests:`, `verdict:`, `reviewed:` and
the lines; a new head has no verdict until it is reviewed, so a stale `ready` never passes. Each `not
met` line, and red tests as one task, becomes a new task appended to `tasks.md` on the branch
(`Comes from:` the line), given one plan review pass, committed (`docs(specs): file the end check's
gaps`) and pushed; the same run builds, reviews and lands it like the others, then checks again. A
pass (green tests, no `not met` line) runs `security-scan.sh --changed` and `mutants.sh` once on the
whole feature diff, then `pr.sh feature --ready`.

**The PR.** After the first landing, `pr.sh feature "<title>" <body-file>` opens the feature's one PR
as a draft, with no scan and no mutation testing, and at the end of each run in which a task landed
it replaces the body (see "What happens automatically"). The body holds a short summary, `## Evidence`
(the test result and each task's `Skills:` line) and, when the feature diff changes an existing
test, `## Test changes` from the implementers' `Test changes:` lines under each task id. When every task is done and the end check
passed, `pr.sh feature --ready` checks that the scan and mutation testing were recorded for the whole
feature diff (their results go in `## Evidence`) and marks the PR ready (`PR=<url> READY=yes`). You review, approve and merge that one PR.

`security-scan.sh` prints one line per scanner, `<tool> ok|findings|missing|skipped|failed <detail>`,
and keeps them with `--changed` as the diff's record (on the feature branch, the diff from
`origin/<base>`). A finding the tool rates high or critical prints `<tool> findings high <report>`:
gitleaks for every finding, osv-scanner for a group `max_severity` of 7.0 or more or an advisory
`severity` of `HIGH` or `CRITICAL`, semgrep for a result `severity` of `ERROR`, `HIGH` or `CRITICAL`,
zizmor for a `High` severity, trivy for `HIGH` or `CRITICAL`. `pr.sh feature --ready` refuses on a
`findings high` line and lists the others.

**The release.** Once the feature PR is merged, `/landspec:implement` makes the release, one step per
run, read each time from git and GitHub (`implement.sh release-plan`, which finds the feature's PR by
its branch): a release PR `chore(release): X.Y.Z` with the bump (`release-bump`) and the notes,
through `pr.sh fix` and its review; once you merge it, the tag `vX.Y.Z` on its merge commit; then
the published release with those notes. It never merges. Before the bump it runs the `full` security
audit unattended on `origin/<base>`, once per commit (`implement.sh audit-plan`, `audit-record`; the
report is kept in `.git/landspec-security/`). A confirmed critical or high finding holds the release:
no bump, nothing filed or posted, and the last line is `run /landspec:security <report>`, which
tracks and fixes it. The main session runs `/code-review high` and `/security-review` for it and
hands their output to the audit. With nothing held, the release notes get a "Known issues" section:
on a public repository only a count per severity and a neutral category, on a private one each
remaining finding's title and category; never an exploit detail. The run's last report names the
scanners that were missing.

`/landspec:implement` is the default after the plan review: its last line names it, and
`/landspec:next` offers it after the progress.

## What happens automatically

| After / before | landspec |
|---|---|
| after `/speckit-specify` | `branch.sh [feature]`, with no task, makes the feature's one branch, `<branch_prefix>/<NNN>-<short-name>` (the spec folder's name, e.g. `feat/008-one-pr-per-feature`): it switches to it when it exists locally, tracks origin's when only origin has it, and otherwise creates it from `origin/<base>` (else the local base) carrying the spec folder's current content, uncommitted files included, commits it as `docs(specs): add <feature> spec` when it changed and pushes it with `-u`; the base is left as it was. It refuses, before any switch, uncommitted changes outside the spec folder, and a feature started under the per-task flow (a `tasks.md` line ending in ` — #N`) with `LEGACY=<feature>` and what to do. It prints `BRANCH=<name> FEATURE=<NNN> BASE=<base>`. With no argument it takes the feature `.specify/feature.json` names (what `/speckit-specify` just wrote), never the branch it runs on. On a feature branch the clone's own `.specify/feature.json` decides the active feature; only a copy without one (a fresh worktree) follows the branch name |
| after `/speckit-tasks` | `/speckit-landspec-plan-review`: the plan is **grounded in the real code** (every symbol a task removes or changes the behaviour of is searched for, with its callers, every quickstart command is read, every data write names its target), then reviewed once by a fresh agent (`review.sh record --plan`): only a high finding sends the plan back for a fix and one more pass, read cold; medium and low findings are shown to you. To apply the findings of a `ready` round, a plan delta reads only `review.sh diff --plan` and is recorded with `review.sh record --plan --delta` (refused after a `changes needed` round), so no new full round is needed; then the spec folder is committed on the feature branch (`docs(specs): <feature> plan and tasks`) and pushed. No GitHub issue is created: progress is `/landspec:next` and the PR's task table |
| after `/speckit-analyze` | records the analysis from its report: `analyzed.sh <report-file>` refuses a file without the report's "Specification Analysis Report" and "Coverage Summary Table", and keeps the report next to the record (level `full` needs it, for the current `tasks.md`, before tasks start) |
| after `/speckit-converge` | the same plan review for the tasks it added, then the spec folder committed on the feature branch |
| before `/speckit-implement` | `branch.sh <feature>` switches to the feature's branch; it refuses a task id (`branch.sh takes a feature, not a task: tasks are built on the feature branch`). Tasks are built by `/landspec:implement` (see "Building a feature"). Before writing code, each implementer weighs each installed skill and MCP server that could bear on the task, `<name> - YES/NO - <reason>`, and invokes every YES (never `landspec:*` or `speckit-*`); its `Skills:` line, `Skills: <name> (<what it was used for>), …` or `Skills: none matched` (`not reported` when an implementer gave none), is kept with the task. No setting chooses the skills: what is installed is what is weighed, and a very large set can push descriptions out of Claude Code's skill listing budget, hiding the right one. A task review (full or delta) weighs the installed skills the same way before reading the diff and adds its own `Skills:` line after `Model:`; a skill never widens what the reviewer does or changes the report's shape; a plan review and a feature review do not weigh skills |
| tests, once per tree | a green run on a clean, committed tree is recorded in `.git/landspec-test/` for that tree and that command (not the copy's path) and is not run again for the same two in any copy of the repository (the builder's worktree, the main checkout, a detached worktree): any edit, commit or change of the command runs it again, and a red run records nothing. Ignored files (dependencies, `.env`, generated code) and the environment are not part of the record: changing only those does not run it again. `implement.sh mark implemented`, `pr.sh feature` and the end check reuse that run; with no test command, a warning says the tests were not run. Each `mutants.sh` and `security-scan.sh` run gets its own report folder (a timestamp and a random suffix), so copies running them in the same second never share one |
| after `/speckit-implement`, the feature PR | `/speckit-landspec-pr` runs `pr.sh feature "<title>" <body-file>`, on the feature's branch only (elsewhere it refuses, naming `branch.sh <feature>`): the gates of `pr.sh fix` on the whole diff from `origin/<base>` (clean tree, `## Evidence` on `full`, `## Test changes`, the Terraform plan, the test command through `run_tests`), but no recorded branch review and no `## Review`, since every landing commit carries its task's `ready` review. It refuses a task ticked `[X]` with no landing commit (`untick it or run /landspec:implement`), and adds to the body a `## Tasks` table (task, summary, `done`, `failed` or `pending`, landing commit, review assessment), `## Low findings` (the `Low:` lines of the landing commits, each under its task id, when there are any) and `## End check` from the feature's end-check record (`.git/landspec-review/feature-<feature>`) when it has a `head:` (head, round, tests, assessment, its `met` / `not met` / `not verifiable` lines, and `checked at <reviewed>; the branch is now at <sha>` once the branch moved). No `Closes #N`. It opens a draft PR once the first task has landed, or replaces the open one's body; where drafts are not available it warns `do not merge this PR before pr.sh feature --ready` and opens a normal PR. The draft needs no scan or mutation record. Prints `PR=<url> READY=no`. **`pr.sh feature … --ready`** also refuses unless every task is done (`T003 is pending: every task is done before pr.sh feature --ready`), `review.sh check --feature` passes (the end-check record's `head:` and `reviewed:` are the feature branch's head, `tests: green`, `verdict: ready`; `review.sh report --feature` prints them) and `security-scan.sh --changed` and, with a `mutate` command, `mutants.sh` are recorded for this diff: it refuses on a `findings high` line, naming the scanner, lists the other findings ("Scanner findings (not high): osv-scanner") and each scanner that did not run ("Scanners not run: semgrep (failed)"), and needs a line in `## Evidence` for each surviving mutant (an unavailable mutation tool, exit 126 or 127, is listed as "Mutation testing: unavailable"; without a `mutate` command, the body says mutation testing was not run). Then it marks the PR ready (`gh pr ready`) and prints `PR=<url> READY=yes` |
| a PR that is not a feature | a small fix, a dependency bump, landspec's own setup or level change, a release: a recorded `ready` review, `## Review`, tests, mutants and scan for the diff, at every level, opened with `pr.sh fix "<title>" <body-file>` from its own branch, with no `Closes`. The guard blocks a raw `gh pr create`, except a promotion whose head is a long-lived branch (`develop` into `main`) |
| an open PR, before it is handed over | `pr.sh state <pr>` (a number or the PR's URL) reads it in one GraphQL query and prints `CONFLICT=no\|yes\|unknown` (`unknown` while GitHub has not computed it), `CI=pending` (a check not completed), `fail <name> (<conclusion>),…` (failed, cancelled, timed out, action required or startup failure; a failed or errored status), `pass`, or `none` (no check: CI is shown, never waited for), and `COPILOT=`, in this order: `pending` (a Copilot review request is open), `comments <n> REPORT=<file> [RESOLVE=<id>,…]` (`n` unresolved threads Copilot opened with no comment after Copilot's own, written to `.git/landspec-review/copilot-<pr>` as `## Findings` with `- <path>:<line> thread=<id> [(outdated)] <first line>` and the comment below; `RESOLVE=` the unresolved ones already replied to), `unavailable <first sentence>` (Copilot's newest review or comment says it was unable to review), `clean` (Copilot reviewed, nothing left) or `none`. Copilot is any login matching `copilot`. It only reads: it never requests a review, and reads no clock, so in the seconds after a push, before a ruleset's request appears, a PR can read ready. `pr.sh state <pr> --reply <thread id> [<file>]` posts the file as the reply to that thread's first comment and resolves it (`REPLIED=<id>`), or only resolves a thread already replied to (`RESOLVED=<id>`); it refuses, posting nothing, a thread not on that PR, not Copilot's, already resolved, or unreplied with no or an empty file; a failed post resolves nothing, and a failed resolve exits 1 after `REPLIED=`. Limits: 100 checks, threads and reviews, 30 comments per query |
| every PR | assigned to you (a failure only warns; no milestone or project, no issue); no AI attribution lines; long output folded into `<details>` |
| a PR that changes existing tests | refused unless the body has a `## Test changes` section saying why: adding tests to an existing file needs no explanation; a deletion, an edit or an added skip does. An added line can still weaken a test in ways this rule cannot see: the review reads it, and `review.sh risk` still flags gate lines. Tests are files under `tests/`, `test/`, `Tests/`, `__tests__/`, `spec/`, `e2e/`, `cypress/` or a `*.Tests/` folder, and files named `*.test.*`, `*.spec.*` (or with `_`, `-`), `*.cy.*`, `tests.py`, `test_*.py` or `FooTests.swift` (case-sensitive). For any other layout, add a line `tests: <regex>` (`grep -E`) to the constitution; an invalid one makes `pr.sh`, `mutants.sh` and `review.sh record` refuse. The same files are what a review's `- proven:` line may name |

These are spec-kit hooks, so you never type them. If you skip one, run it yourself:
`/speckit-landspec-plan-review`, `/speckit-landspec-pr`, `/landspec:implement`.

## Mutation testing

`mutants.sh` runs the constitution's `mutate` command once per feature, on the whole feature diff
from `origin/<base>`, after every task has landed and the end check passed, and keeps the result for
that exact diff: `pr.sh feature --ready` and `pr.sh fix` refuse without it (the draft feature PR
needs none). A mutant may be in the tree until the run ends, so nothing else edits or tests that
tree meanwhile. Each run writes its log to its own folder, so two runs at once never share one. A
later commit makes a new diff, which needs one more run (and, on the feature branch, an end check
of the new head). The command is told what changed:

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
`pr.sh feature` and `pr.sh fix` need the plan recorded for this exact diff. In the root you changed:

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
clone: `<epoch> <UTC time> <branch> <event> key=value...`. The events are `start` (the implementer, on a task's new ref, with `task=`; and `branch.sh`
made the branch), `review` (`review.sh record`, `round=full|delta|plan|feature` and the verdict;
a plan round also names its `feature=` and its `h=`, `m=` and `l=` counts), `issues` (older logs only: a run of the removed issue step
that created or linked issues, `created=<n>`), `outside` (`review.sh outside --plan <n>`, the real
findings of outside reviewers of the plan),
`mark` and `fail` (`implement.sh`, with `branch=` named, since the run's copy is detached),
`tests` (`pr.sh`, the seconds the test command took, `ok=1` or `ok=0`; a reused green run logs
`secs=0`) and `pr` (the PR it opened or found). A write that fails is silent and never stops a
script. The file stays in `.git`: it is never pushed, and nothing from it reaches a PR.
Nothing rotates it (about 10 lines per PR).

`bash .specify/extensions/landspec/scripts/stats.sh` prints one row per feature PR and per fix PR
(and per PR of a per-task feature); a feature PR's row also counts its tasks' refs
(`landspec/<NNN>-t<nnn>-task`), so the review rounds of every task add up on it (minutes from start to its first `pr` event, `?` with no `start` event, so a later `pr.sh` run that finds the open
PR, or marks the draft ready, does not move it; full and delta review rounds, the first verdict, the test time and runs, and `H+M`, the high and medium findings its reviews counted, `?` when no report carried the `Findings:` count line),
then, for each feature whose tasks landed on its one branch, one
`TASK <NNN>/<id> first->land <m>m | reviews <f> full + <d> delta | conflict yes|no` line per landed task
(minutes from the first event on its ref to its `land` event: the `start` its implementer logs, or, in an older
log with none, its first `mark` or `review`, so the build before it is not counted; `conflict`: it had a landing conflict round) and one
`FEATURE <branch> first->land <m>m | tasks <n> | checks <n>` line (from the first event of any of its tasks to its
last landing, the tasks landed, and the end-check rounds),
then one `PLAN <feature> rounds <n> (<r> ready) | findings <h>/<m>/<l> … | outside <n>`
line per feature with plan events (the counts of each plan round, `?` when its report had none; plan events
written by 2.7.0 name no feature and are grouped under `?`),
then `PRS=`, the median start-to-PR minutes, the mean rounds and how many were `ready` on
the first review. A per-task feature's own PR for its spec folder is left out of the rows and the totals. It reads only this clone's log, and groups by branch name, so a branch name used
twice adds both PRs into one row.

## Using Claude Code well

| Tool | Where it fits |
|---|---|
| **Plan mode** (`Shift+Tab`) | thinking out loud before `/speckit-specify` or during `/speckit-clarify`. Not for `/speckit-plan`, which writes files that plan mode blocks. |
| **`/code-review ultra`** | yourself, before merging a large or risky change (cloud, billed). landspec's own reviews (`/speckit-landspec-review`: one Opus review per task, the plan review and the end check's feature review) run in a fresh agent grounded in the whole repository, so they are not anchored on the session that wrote the code. |
| **`/security-review`** | before a fix PR, automatically, for the release audit, and inside `/landspec:security` |
| **Worktrees** | `/landspec:implement` gives each implementer its own copy (Claude Code's `isolation: "worktree"`) on its task ref, and each review its own copy of the reviewed commit; nothing is pushed from them but the landed feature branch. A `worktree_setup` command prepares a fresh copy. The active feature, the `/speckit-analyze` record, the test records and the security reports live in the shared git directory, so `full` works in every copy. A copy left behind is removed with `git worktree remove <path>`; `implement.sh status` runs `git worktree prune` first. |

## Configuration

`.specify/extensions/landspec/landspec-config.yml`:

| Key | Default | Meaning |
|---|---|---|
| `level` | `standard` | `lite`, `standard` or `full`; set it with `/landspec:level` |
| `base_branch` | `auto` | the branch feature PRs target: `main` on lite, `develop` otherwise |
| `branch_prefix` | `feat` | the feature branch is named `<prefix>/<NNN>-<short-name>`, the spec folder's name (`feat/008-one-pr-per-feature`) |
| `worktree_setup` | *(empty)* | one command each `/landspec:implement` implementer runs first in its own copy (a new worktree has no git-ignored files: `pnpm install`, say); when it fails, that task is `failed` with its output. Empty: each implementer prepares its own copy as the README says, and a task it cannot prepare is `failed` (`setup: <what is missing>`) |
| `implement_model` | *(empty: the session's)* | the model of `/landspec:implement`'s implementers: `sonnet`, `opus` or `fable`; any other value is refused |
| `task_rounds` | `2` | how many `changes needed` reviews a task gets (the first review and one delta; a landing conflict's round is not counted) before `implement.sh mark … changes` marks it `failed` (`FAILED=<id>`; `retry` lifts it): a number from `1` to `9` |
| `feature_rounds` | `3` | how many heads of the feature branch the end check checks (a red run or a `changes needed` feature review count once per head; red tests or a `not met` line give new tasks, and the next head is checked again) before it stops and asks: a number from `1` to `9` |
| `version_files` | *(empty)* | the files that carry the version (`version: "X.Y.Z"` or `"version": "X.Y.Z"`), comma separated, the first one read as the current version; `/landspec:implement` bumps them for the release (minor; patch when every task is a `Fix`). Empty: no release step, only notes |
| `release_notes` | *(empty)* | the folder for each release's notes, `<folder>/X.Y.Z.md`; they are also the published release's body; without it, the notes are the release PR's body, up to its `## Evidence` or `## Review` |
| `parallel_tasks` | `4` | how many builders `/landspec:implement` runs at once on the feature branch, each on its own task ref: `implement.sh status` prints at most this many `START=` lines, minus the running ones; reviewers take no slot: a number from `1` to `16`, any other value is refused |
| `aws` | `off` | `on` turns on the AWS access layer. `/landspec:level` then writes `.mcp.json` when it does not exist (the `aws-mcp` server: `uvx mcp-proxy-for-aws==<MCP_PROXY_VERSION>`, run as the `landspec-agent-dev` profile; an existing one is kept as it is, and `remove.sh` deletes it only while unchanged) and adds a "Cloud access" section per level to the constitution. `MCP_PROXY_VERSION` in `extension/scripts/pins.sh` is a PyPI release: `bin/check-tools.sh` reads GitHub releases only, so it is bumped by hand, to a release a few weeks old. `off`: nothing of this is written |
| `aws_prod_profiles` | *(empty)* | comma-separated AWS CLI profiles that reach a prod account, matched exactly; set by `/landspec:aws` (empty: one account only) |
| `aws_prod_paths` | *(empty)* | comma-separated folders whose Terraform targets prod (e.g. `infra/envs/prod`); set by `/landspec:aws` |
| `aws_agent_role` | `landspec-agent` | the agent role's name; `/landspec:aws` sets it when unset |
| `infra_dir` | `infra` | the folder holding the Terraform code, named in the plan gate's refusal; `/landspec:aws` sets it when unset, to the folder with the most `*.tf` files |

### The reviewer's model

There is no setting for the review model: every review (task, plan, feature) runs on `opus` in the
plugin's `landspec:reviewer` agent; when Opus is not available the review stops, with no fallback.
`opus` is passed on every launch, so on a cheap session the review costs more than the session.
`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` overrides it (the launch may then leave `model` empty only when it
names an Opus model; the record warns). The plugin's hook that blocks a review launch on any model but `opus`,
in a fork, or without `isolation: "worktree"`, exists only where the plugin is installed. A project whose landspec copy predates that rule is refused until `/landspec:init`
updates it. A key for the review model left in an older config is ignored.

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
