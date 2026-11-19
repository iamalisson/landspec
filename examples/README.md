# Example: one feature, from idea to merged PR

This walks through **price search**, a small feature with 3 tasks, on a `standard` project
(`feat/*` → `develop` → `main`). Every file named here is in this folder, in the exact shape
landspec produces, so you can open each one and see what you'll get.

**Your job:** plan the feature, review its PR, merge it. **Claude:** writes the spec, plan,
tasks and code. **landspec:** does everything in between (the branch, the checks, the reviews, the
PR), the same way every time.

## 1. Plan the feature (once)

| You run | What appears | What you do |
|---|---|---|
| `/speckit-specify "shoppers filter products by max price"` | [`spec.md`](specs/001-price-search/spec.md): stories, requirements, success criteria, committed on the feature's branch `feat/001-price-search`, made from `develop` and pushed | read it, fix what's wrong |
| `/speckit-plan` | [`plan.md`](specs/001-price-search/plan.md): stack, design, constitution check | read it |
| `/speckit-tasks` | [`tasks.md`](specs/001-price-search/tasks.md), then one Opus review of the plan against the real code; the spec folder is committed on the branch. No GitHub issue is created | read the review's findings; a high one sends the plan back |

## 2. Build it (once per feature)

| You run | What happens | What you do |
|---|---|---|
| `/landspec:implement` | starts T001 and T003 at once, each in its own copy on a local task ref (`landspec/001-t001-task`, never pushed): code, tests, one Opus review of the task's diff. T002 says "depends on T001", so it waits. T001 lands first (one merge commit on `feat/001-price-search`, its tick in `tasks.md`), and the draft [PR #20](github/feature-pr.md) opens (`pr.sh feature`); T002 starts. T003 and T002 land as each is ready | nothing; `/landspec:next` shows `1/3 done`, `2/3 done` meanwhile |
| *(same run)* | every task has landed: the end check runs the tests on the branch head and an Opus review of the whole feature against the spec (each FR and SC `met`), then one scan and one mutation run of the whole diff, and PR #20 is marked ready | review PR #20 and merge it |
| `/landspec:implement` | the feature is on `develop`: the full security audit, then the release | merge the release PR |

Had the end check found a requirement `not met`, it would have become a new task on the same
branch, built, reviewed and landed the same way, before the PR was marked ready.

The PR timeline on GitHub:

```
#20  feat(products): price search   feat/001-price-search → develop   one PR for T001, T002, T003
```

## Why one PR?

- **You merge once.** Each task still gets its own small review before it lands, but no task waits
  for you to merge the one before it, and `tasks.md` is on the branch from the start.
- **The review stays small.** Each task is reviewed alone, on its own diff; the end check is the
  one review of all of them together, against the spec.
- **A task is still one commit.** Each landing is one merge commit with its review in a trailer, so
  `git revert -m 1` takes out one task before the feature merges.
- **You review the design before any code exists.** The plan review runs before the first task
  starts. Changing your mind costs one edit to a doc, not a rewrite.

## Reading the PR

The feature PR keeps what a reviewer needs visible: what changed, a one-line evidence summary, the
task table (each task's landing commit and review), the low findings and the end check's lines.
Long output, such as test logs and scan details, is folded into `<details>` blocks that you click
open. See [`github/feature-pr.md`](github/feature-pr.md).

## Starting from zero

This example adds a feature to an existing project. To start from an empty folder, run
`/landspec:new`. You choose the stack together with Claude; it sets up the tooling (no
application code) by following the [Starter checklist](../docs/GUIDELINES.md#starter-checklist),
then suggests a foundation spec as your first `/speckit-specify`.

Stuck? `/landspec:help`, or `/landspec:help <your question>`.
