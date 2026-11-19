# Why landspec works this way

Design decisions, each with its reason. The what is in the [README](../README.md) and the
[reference](reference.md).

## One branch and one PR per feature

- **The merge loop cost more than small PRs saved.** landspec used to give every task its own GitHub
  issue, branch and PR, plus a PR for the spec, and another each time the end check found a gap. An
  eleven-task feature meant a dozen PRs, each merged by hand before the next run could go on, and a
  review round and a scan repeated on each one. The developer's time went into that loop, not into
  reading code. Now a feature is what spec-kit already says it is: one spec folder, one branch
  (`<branch_prefix>/<NNN>-<short-name>`, made when the spec is written), one PR, reviewed and
  merged once. No GitHub issue is created: progress is `/landspec:next` and the PR's task table.
- **Small reviews still happen, one per task.** Review finds bugs only in small changes: a Cisco
  study of 2,500 reviews put the useful size at 200 to 400 lines
  ([SmartBear](https://smartbear.com/learn/code-review/best-practices-for-peer-code-review/)), and
  Google's guide calls about 100 lines reasonable
  ([small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)). So each
  task is still reviewed alone, by one Opus review of its own diff against the feature head, before
  it lands. What moved is the merge: a task lands on the feature branch, not on the base, so no
  task waits for a person.
- **Tasks are built in parallel.** `/landspec:implement` starts every task whose dependencies have
  landed at once, up to `parallel_tasks` (default 4), each on its own local task ref
  (`landspec/<NNN>-<tnnn>-task`, never pushed) in its own copy. A feature takes the time of its
  longest chain of dependent tasks, not the sum of all of them, and a task that depends on another
  simply starts once that one has landed: nothing is stacked.
- **Landing is one commit.** `implement.sh land` merges a reviewed task ref `--no-ff` into the
  feature branch with its tick in `tasks.md`, the review's low findings as `Low:` lines and the
  trailers `Landspec-Task: <NNN>/<id>` and `Landspec-Review: ready <patch id>`. That merge is what
  "done" means, in any clone, so `/landspec:next` and a resumed run read progress from git alone.
  Failures still localize: there is one landing commit per task, and `git revert -m 1` of it takes
  out one task before the feature merges. Two tasks that change the same lines conflict at landing;
  the later one gets one round to take in the feature branch, is reviewed again and lands, and a
  second conflict marks it failed.
- **Every check runs once.** The tests run once per tree: a green run is recorded for that tree and
  command, and every later step that needs it (`implement.sh mark implemented`, `pr.sh feature`, the
  end check) reuses it. The plan review is one Opus pass; only a high finding sends it back. A task
  review blocks on a high or medium finding and gets one fix round, re-checked as a delta
  (`task_rounds`, default 2, counts both); a task still blocked after it is marked failed and named
  at the end while the run goes on. The scanners and mutation testing run once, on the whole
  feature diff, before the PR is marked ready. Loops that end only at zero findings are gone.
- **The end check is the PR's review.** Each task review reads one diff; only a check of all of
  them together, against the spec, answers "nothing is left and nothing breaks the others". When
  every task has landed, `implement.sh check` runs the tests on the branch head and an Opus review
  in feature mode reports each FR, scenario and SC as `met`, `not met` or `not verifiable`. Each
  `not met` line becomes a new task on the same branch; rounds are capped (`feature_rounds`, default
  3) so a fix that changes nothing never loops. One record, kept per feature, decides the PR:
  `pr.sh feature` opens a draft after the first landing, with no scan yet, and keeps its body current
  (tasks, low findings, test changes, end check), and
  `pr.sh feature --ready` marks it ready only when every task is done, the latest feature review is
  `ready` for the current head and the scan and mutants are recorded for that diff.

The cost is a larger PR to merge, and a revert after the merge takes the feature. That is why the
PR carries the evidence a merge needs (each task's review, the end check's lines, the scan) and why
tasks are still **vertical slices**, one observable behavior with its test: the reviews stay small
even when the PR is not.

Features started under the old per-task flow (a task line ending in ` — #N`) are not migrated:
`next.sh`, `implement.sh` and `branch.sh` print `LEGACY=<feature>` and say how to finish its open
PRs and continue it under this flow.

## The review is independent

A review inside the session that wrote the code shares that session's assumptions and tests the
path it already tested. landspec's review (`/speckit-landspec-review`) of each task, of the plan and of the whole
feature is an Opus review in a fresh agent that gets only facts: the branch or task ref, the task
line, the test command. It starts from the
diff and the code around it (what it calls and what calls it), once, and reports the real bugs in the changed lines, after trying to break each thing the change claims with a concrete counterexample, following personal data and secrets into the helpers they are passed to,
since a leak usually hides one call away from the diff. It runs in its own copy of the
reviewed commit, so whatever it runs (a test, a mutation) never touches the author's checkout. CI runs the tests. `## Evidence` is the author's: no script checks what it says.
It works the way GitHub's Copilot code review does, one fast pass, with no Copilot subscription
needed. The review is a gate, not a prompt: its
report is recorded against the exact diff (`review.sh`), at every level. `implement.sh land`
refuses a task whose review of its ref's head has a high or medium finding; `implement.sh status`
starts no task while the plan review is stale or has a high finding; `pr.sh feature --ready`
refuses without a `ready` feature review of the branch head; `pr.sh fix` refuses a fix PR without a
recorded `ready` for its diff. A review that could not run in its own copy (`Copy: none`) never
passes. What the gate proves is that a report was recorded for this exact diff; that a fresh
reader wrote it rests on the prompt and the launch hook. The feature PR's task table shows each
task's assessment and the end check's lines; a fix PR's body shows the facts of its review and
nothing else, folded under "Independent review": the review was recorded for
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
the head it starts from, and refuses a rebase or a range that is not the delta's; a fix of any
size is a delta, and a task gets one. Each report states the range and model it reviewed,
so a commit made while the review ran is never recorded as reviewed.

## One security review, of the diff, before the PR is ready

The audit used to run after the merge, before the release bump: the whole repository, `/code-review
high`, `/security-review` and an eleven-group sweep, 10 to 30 minutes, on code already reviewed
task by task, and too late: a finding there was already on the base. Now one security review reads
the feature's diff and the code it touches, in the end check, beside the feature review and on the
same commit, while the PR is still a draft. It is staged the way Anthropic's security review action
and the published work on pairing an LLM with static analysis are: map what the change exposes,
hunt only where the map points with the scanners' findings as leads, then try to disprove each
finding, with a fixed list of noise never reported. A diff that exposes nothing costs one line; a
confirmed critical or high costs one more reviewer, who sees the claim and not the reasoning. A
passed review stands in for the audit at the release (`AUDIT=reviewed`); `/landspec:security` stays
the whole-repository audit, on demand.

## The main session starts every agent

Implementers and reviewers are the main session's background agents, and none starts another. Only
the main session can watch them all, keep the review independent (the agent that wrote a task ref
never picks its reviewer), land each task in turn and wait for every one of them before it stops.
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
