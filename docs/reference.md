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
check, so after an update run `/reload-plugins` first, then `init`.

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

## Several features at once

Every feature is its own folder (`specs/001-login/`, `specs/002-reports/`), and everything landspec
creates carries its number: issues `[001] T003: ...`, branches `feat/001-t003-...`, the spec PR
`spec/001-login`. They never collide. The **active feature** is per clone (`.specify/feature.json`,
git-ignored): `/speckit-specify` sets it to the new feature, and `/landspec:next 002` or
`/speckit-implement 002 T001` set it explicitly. With no argument, `next` serves the active
feature; when more than one feature has tasks to start, it lists them and asks, and when only one
does, it serves that one without changing the active feature. On a task branch the branch name
decides, for `next` too, so a worktree never follows the main checkout. `next` prints `FEATURE=` and
starts `/speckit-implement <FEATURE> <NEXT>`, so `next 002` on a 001 task branch starts 002's task.
It fetches origin first, and stops, naming the reason above git's or gh's error, when it cannot
fetch origin, read its branches or list the open PRs: without them a task another clone claimed
would look free. It prints a `parallel` line only for a task whose
line is on `origin/<base>` with its issue: a task of an unmerged spec PR, converge ones included,
gets no line, and `branch.sh` refuses it with "merge the spec PR first" before any claim. A task is
done when the issue number on its line is closed: `next` reads every task's issue by number in one
query per feature, so a renamed issue still counts, and a number it cannot read stops it with
GitHub's error. GitHub closes a PR's `Closes #N` issues only on a merge into the default branch;
on standard and full, the managed `close-linked-issues.yml` closes them on a merge into `develop`
or `staging`, and its job fails, naming `could not close: #N`, when one of them cannot be closed.

A task whose line says `(depends on T003)` is **blocked** until T003's issue closes, so `next`
never offers work whose prerequisite has not merged.

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

`/landspec:implement [feature]` runs a feature's tasks in parallel instead of one per `/landspec:next`.
Each pass it runs `implement.sh restack`, then `implement.sh status --running <in flight>`, and takes
one step per listed task: `START` launches an implementer (`landspec:implementer`, in the background,
in its own copy), `REVIEW` the independent review against `base_ref <branch>`, `FIX` a fix round with
the review's report, and `OPEN` the scan and `pr.sh task` in the task's copy, parents first. A task
that depends on an unmerged one starts stacked on its branch (`branch.sh --from`), and its PR is a draft
into the parent's. It asks nothing while it runs, never merges, and ends with the PRs to merge in
`ORDER`; run it again after merging, and it moves the stacked branches onto the base.

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
line is `run /landspec:security <report>`, which tracks and fixes it.

`/landspec:implement` is the default after `/speckit-tasks`: the spec PR's last line names it, and
`next.sh` prints `RUN=/landspec:implement <feature>` before `FEATURE=` when two or more tasks can start.

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
| after `/speckit-tasks` | the plan is **grounded in the real code** (every symbol a task removes is searched for, every quickstart command is read, every data write names its target), then reviewed by a fresh agent (plan review, recorded; no issue is created without it), then one issue per task, `— #N` written on each task line, the spec PR opened |
| after `/speckit-analyze` | records the analysis from its report: `analyzed.sh <report-file>` refuses a file without the report's "Specification Analysis Report" and "Coverage Summary Table", and keeps the report next to the record (level `full` needs it, for the current `tasks.md`, before tasks start) |
| after `/speckit-converge` | the new tasks it found get grounded, get issues, and reach the base branch through a spec PR |
| before `/speckit-implement` | refuses without exactly one task, an issue, the merged spec and a clean tree; otherwise switches to `feat/<feature>-t00x-<slug>` and pushes it to origin at once (the claim). spec-kit's implement command is told to build only that task and not tick it (the issue closing is "done") |
| after `/speckit-implement` | checks, commit, `/security-review`, the independent review (recorded for the exact diff, fixed until `ready`), mutation testing (see "Mutation testing") and the security scan on the change after the last commit, push, PR with `Closes #N` and `## Review`. The PR is refused without a recorded `ready` review for the diff, at every level, and when the constitution's test command fails (it runs before the push; with no test command, a warning says the tests were not run). With a `mutate` command in the constitution, it is also refused without a `mutants.sh` result for the diff, on surviving mutants that `## Evidence` does not explain, or when the command could not run (exit 126 or 127, recorded as `unavailable`; a wrapper such as `uv run` exits otherwise, so a tool missing behind one shows as survivors); without one, the body says mutation testing was not run. It is refused without a `security-scan.sh --changed` result for the diff (missing scanners and findings do not refuse) |
| a PR that is not a task | a small fix, a dependency bump, landspec's own setup or level change: the same gate as a task PR at every level (recorded `ready` review, `## Review`, tests, mutants and scan for the diff), opened with `pr.sh fix "<title>" <body-file>` from its own branch, with no issue and no `Closes`. The guard blocks a raw `gh pr create`, except a promotion whose head is a long-lived branch (`develop` into `main`) |
| every issue and PR | assigned to you; given the milestone and project if configured (a failure only warns); no AI attribution lines; long output folded into `<details>` |
| a task PR that changes existing tests | refused unless the body has a `## Test changes` section saying why: adding tests to an existing file needs no explanation; a deletion, an edit or an added skip does. An added line can still weaken a test in ways this rule cannot see: the review reads it, and `review.sh risk` still flags gate lines. Tests are files under `tests/`, `test/`, `Tests/`, `__tests__/`, `spec/`, `e2e/`, `cypress/` or a `*.Tests/` folder, and files named `*.test.*`, `*.spec.*` (or with `_`, `-`), `*.cy.*`, `tests.py`, `test_*.py` or `FooTests.swift` (case-sensitive). For any other layout, add a line `tests: <regex>` (`grep -E`) to the constitution; an invalid one makes `pr.sh`, `mutants.sh` and `review.sh record` refuse. The same files are what a review's `- proven:` line may name, and what a fix round (`review.sh record --delta`) may change beyond its 20-line limit outside the previous findings |

These are spec-kit hooks, so you never type them. If you skip one, run it yourself:
`/speckit-landspec-issues`, `/speckit-landspec-pr`.

## Mutation testing

`mutants.sh` runs the constitution's `mutate` command once per PR, after the last commit, and keeps
the result for that exact diff; `pr.sh task` and `pr.sh fix` refuse a PR without it. A fix commit
means one more run, so fix first and run it last. The command is told what changed:

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

## Using Claude Code well

| Tool | Where it fits |
|---|---|
| **Plan mode** (`Shift+Tab`) | thinking out loud before `/speckit-specify` or during `/speckit-clarify`. Not for `/speckit-plan`, which writes files that plan mode blocks. |
| **`/code-review ultra`** | yourself, before merging a large or risky change (cloud, billed). The review before each PR is landspec's own `/speckit-landspec-review`: a fresh agent grounded in the whole repository, so it is not anchored on the session that wrote the code. |
| **`/security-review`** | before each PR, automatically, and inside `/landspec:security` |
| **Worktrees** | `/landspec:next` lists the other `[P]` tasks that can start now and, on yes, gives each its own worktree beside the repo (`<repo>-<feature>-<task>`) and claims its branch on origin, one after another. Open a Claude Code session in each and run `/speckit-implement <feature> <task>`. Each task keeps its own branch and PR. Blocked tasks and tasks without `[P]` right after their ID are never offered. A claim that cannot be pushed only warns, so another clone may still start the same task. When you're done, remove each worktree with `git worktree remove <path>`. The active feature, the `/speckit-analyze` record and the security reports are shared by every worktree, so `full` works there too. |

## Configuration

`.specify/extensions/landspec/landspec-config.yml`:

| Key | Default | Meaning |
|---|---|---|
| `level` | `standard` | `lite`, `standard` or `full`; set it with `/landspec:level` |
| `base_branch` | `auto` | the branch task PRs target: `main` on lite, `develop` otherwise |
| `branch_prefix` | `feat` | task branches are named `<prefix>/<feature>-<task>-<slug>` |
| `issue_labels` | `type:task` | comma-separated labels for task issues |
| `milestone` | *(empty)* | milestone for task issues and PRs, by name; empty means none |
| `project` | *(empty)* | GitHub project (title) to add task issues and PRs to; needs `gh auth refresh -s project` |
| `review_model` | *(empty: `sonnet`)* | the model of the independent and plan reviews, run in the plugin's `landspec:reviewer` agent: `sonnet`, `opus` or `fable`; never `haiku`, any other value is refused. It is passed on every launch, so on a cheap session the review costs more than the session. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` overrides it (the record then warns). The plugin's hook that blocks a review launch on a model outside `sonnet`, `opus` and `fable`, in a fork, or without `isolation: "worktree"`, exists only where the plugin is installed. A project whose landspec copy predates that rule is refused until `/landspec:init` updates it |
| `worktree_setup` | *(empty)* | one command each `/landspec:implement` implementer runs first in its own copy (a new worktree has no git-ignored files: `pnpm install`, say); when it fails, that task is `failed` with its output. Empty: each implementer prepares its own copy as the README says, and a task it cannot prepare is `failed` (`setup: <what is missing>`) |
| `implement_model` | *(empty: the session's)* | the model of `/landspec:implement`'s implementers: `sonnet`, `opus` or `fable`; any other value is refused |
| `feature_rounds` | `3` | how many whole-feature check attempts `/landspec:implement` makes (a conflict, a red run or a `changes needed` feature review each count once per new combination of task heads) before it stops and asks: a number from `1` to `9` |
| `version_files` | *(empty)* | the files that carry the version (`version: "X.Y.Z"` or `"version": "X.Y.Z"`), comma separated, the first one read as the current version; `/landspec:implement` bumps them for the release (minor; patch when every task is a `Fix`). Empty: no release step, only notes |
| `release_notes` | *(empty)* | the folder for each release's notes, `<folder>/X.Y.Z.md`; they are also the published release's body |
| `parallel_tasks` | `4` | how many implementers `/landspec:implement` runs at once (`implement.sh status` puts at most this many, minus the running ones, in `START=`); reviewers take no slot: a number from `1` to `16`, any other value is refused |

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
