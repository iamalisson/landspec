# Why landspec works this way

Design decisions, each with its reason. The what is in the [README](../README.md) and the
[reference](reference.md).

## One task = one issue = one branch = one PR

- **Review finds bugs only in small changes.** A Cisco study of 2,500 reviews put the useful
  size at 200 to 400 lines; past that, defects found per line fall off
  ([SmartBear](https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/)).
  Google's guide calls about 100 lines reasonable and 1,000 too large
  ([small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)). This
  matters more with AI-written code: a 150-line PR gets read, a 2,000-line one gets scrolled.
- **Small batches are faster and safer at once.** DORA's research links batch size to both
  delivery speed and stability
  ([working in small batches](https://dora.dev/capabilities/working-in-small-batches/)), and the
  2025 model lists it among the capabilities that make AI help instead of hurt.
- **Failures localize.** A red CI, a security finding or a production bug points at one task.
  One revert removes one task. In a one-PR feature, the revert takes everything. The promise rests
  on one commit per task PR: `init` offers to turn rebase merges off on every level; lite merges by
  squash only, and on standard and full task PRs are squashed by convention (merge commits stay for
  the `develop` → `main` promotions, which a squash would split from `develop`).
- **"Done" has an external definition.** The issue says which requirement produced the code and
  closes only when the PR merges. That is what makes `/landspec:next` resumable after a month,
  and what the independent review checks the PR against.

The cost is real: a CI run, a review round and a merge per task. It pays off when tasks are
**vertical slices**, one observable behavior with its test, and not layers. The tasks template
says so, and the plan review flags layer-shaped tasks before any issue exists. Since other people
promote the base branch while a feature is half built, each task must also be safe in production
alone: a visible feature ships behind a flag that is off by default, and its last task turns it on.

## The spec is its own PR

Task branches start from the base branch and read `tasks.md` there, so the spec has to be merged
before any task starts. It also means you review the design while changing it costs one edit to a
doc, and each task PR stays small and closes exactly one issue. The worked example in
[examples/](../examples/README.md#why-two-kinds-of-pr) shows both kinds.

## The review is independent

A review inside the session that wrote the code shares that session's assumptions and tests the
path it already tested. landspec's review before every PR (`/speckit-landspec-review`) runs in a fresh agent
that gets only facts: the branch, the task line, the PR body, the test command. It starts from the
diff and the code around it (what it calls and what calls it), once, and reports the real bugs in the changed lines, after trying to break each thing the change claims with a concrete counterexample, following personal data and secrets into the helpers they are passed to,
since a leak usually hides one call away from the diff. It runs in its own copy of the
reviewed commit, so whatever it runs (a test, a mutation) never touches the author's checkout. CI runs the tests. `## Evidence` is the author's: no script checks what it says.
It works the way GitHub's Copilot code review does, one fast pass, with no Copilot subscription
needed. The review is a gate, not a prompt: its
report is recorded against the exact diff (`review.sh`), and `pr.sh` refuses the PR without a
recorded `ready` for that diff, at every level; the same holds for the plan review before issues.
What the gate proves is that a report saying `ready` was recorded for this exact diff; that a fresh
reader wrote it rests on the prompt and the launch hook. The PR body shows those facts and nothing else, folded under "Independent review": the review was recorded for
this diff (its patch id), its `Assessment:` line, the model it ran on with any warning (a session
that forces one subagent model, or a model outside the configured family), and the risk map's
paths. The script copies none of the reviewer's
prose, because no filter on wording can be sure to keep a finding out of it, so a security
finding's detail cannot reach a public PR through the script. The review's summary reaches the PR
only through the author's `## Review`, a security finding as the one line
`Security: reported privately (<id>)`.

Depth follows risk. A script that sees only paths and added lines (`review.sh risk`) names the
risky ones (a migration, a deletion, CI, authorization, secrets, money, styles and page templates, a skipped gate), and
`record` refuses a report that does not deep-check each, or name the test line that proves it. The
reviewer adds the risks a path cannot show. A fix round is a **delta**: it reviews only the commits
since the last recorded head, and `record --delta` holds it to that: it follows a recorded round, names
the head it starts from, and refuses a fix that grew past 20 lines outside the previous findings,
a rebase, or a range that is not the delta's. Each report states the range and model it reviewed,
so a commit made while the review ran is never recorded as reviewed.

## Parallel tasks, stacked PRs

`/landspec:implement` runs every task that can start at once, each in its own copy, so a feature
takes the time of its longest chain of dependent tasks, not the sum of all of them. A task that
depends on one still unmerged starts on that task's branch and its PR is a draft into it: each PR
still shows only its own task's work and is reviewed alone, and GitHub cannot merge the child before
its parent. Once the parent merges, `restack` moves the child onto the base, and the review it
already has still counts unless the move changed its diff.

Each task's review reads one diff. Only a check of all of them merged together, against the spec,
answers "nothing is left and nothing breaks the others": so the run ends with one, in a copy that holds
every task branch at once (made by the main session, since an agent's copy holds one), and its
rounds are capped so a fix that changes nothing never loops.

The main session starts every agent: implementers and reviewers are its background agents, and none
starts another. Only the main session can watch them all, keep the review independent (the agent
that wrote a branch never picks its reviewer), and wait for every one of them before it stops.
Agents that start agents would leave work that nobody watches.

## Levels instead of one setup

A prototype and a payment service do not need the same ceremony, and a checklist that is too
heavy gets skipped. `lite`, `standard` and `full` size the branch flow, the constitution's
defaults, the CI and the review bar to how serious the project is, and `/landspec:level`
moves between them without deleting anything.

## Nothing of yours is overwritten

Files landspec generates carry a `# landspec: managed file` first line and are re-created
on `/landspec:level`; delete that line and the file is yours. Files it cannot mark (the PR
template, `.claude/settings.json`, `SECURITY.md`) are written only when missing. `remove` deletes
only what still matches what it wrote.

When a managed workflow is re-created, an action pin newer than landspec's own (a Dependabot
bump: `uses: <action>@<sha> # <version>`) is kept and named `kept newer pin: <action> <version>`.
A `container.image` digest is not such a line and goes back to landspec's.

Releases before the marker (1.0.0 to 1.3.1) wrote some files byte for byte;
`extension/scripts/old-files.sha256` lists them. Their two git hooks are replaced and marked. Their
`close-linked-issues.yml` and `release.yml` are kept and named (`kept (written by landspec
<versions>, no marker)`), since a 1.4.0+ copy with its marker deleted has the same bytes; and once
an old hook matched, so are the generated workflows, Dependabot and `CODEOWNERS` (`<versions> or
older`). Delete one to get the current version.
