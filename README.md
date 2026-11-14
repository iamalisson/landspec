<h1 align="center">landspec</h1>

<p align="center">
  <em>Spec Kit, with the boring parts done.<br>
  Every task gets an issue, a branch and a pull request. Every commit gets checked. Every project starts with the right defaults.</em>
</p>

<p align="center">Formerly jit-speckit. Upgrading from it: <a href="docs/releases/2.0.0.md">docs/releases/2.0.0.md</a>.</p>

<p align="center">
  <a href="https://github.com/iamalisson/landspec/actions/workflows/test.yml"><img src="https://github.com/iamalisson/landspec/actions/workflows/test.yml/badge.svg" alt="Tests"></a>
  <img src="https://img.shields.io/badge/Claude%20Code-plugin-111111?style=flat-square" alt="Claude Code plugin">
  <img src="https://img.shields.io/badge/spec--kit-v1.2.5-111111?style=flat-square" alt="spec-kit v1.2.5">
  <img src="https://img.shields.io/badge/runs%20on-Linux%20%C2%B7%20macOS-111111?style=flat-square" alt="Linux and macOS">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/flow-dark.svg">
    <img src="assets/flow-light.svg" width="880" alt="spec and tasks once per feature; then, once per task and automatically: issue, branch, pull request, merged and issue closed">
  </picture>
</p>

---

[GitHub Spec Kit](https://github.com/github/spec-kit) turns a feature idea into a spec, a plan and a
task list, and Claude writes the code. landspec plugs into it and handles everything around
that code:

- every task gets a GitHub issue, its own branch and its own pull request;
- secrets are refused at commit and push, and every pull request passes a security gate;
- the project's constitution starts with security, testing and simplicity defaults, sized to how
  serious the project is.

You plan the feature and review the work. Claude writes the code, and landspec does the rest
the same way every time.

## Install

In Claude Code:

```
/plugin install landspec --marketplace iamalisson/landspec
```

<sub>Needs Claude Code 2.1.295 or newer: from that version the command guard blocks a command when it times out or crashes.</sub>

That one command is the whole install. Don't run `specify init` yourself: `/landspec:init` sets
up [spec-kit](https://github.com/github/spec-kit) in your project, for Claude, at the version
landspec is tested with.

What your machine needs first:

| Tool | Why | Check |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) 2.1.295+ | runs landspec | `claude --version` |
| `git` | branches and commits | `git --version` |
| [GitHub CLI](https://cli.github.com), logged in | issues and pull requests | `gh auth status` |
| [uv](https://docs.astral.sh/uv/) | installs spec-kit's `specify` CLI | `uv --version` |

If `specify` is missing, `/landspec:init` offers to install it with `uv`. A project already set up
with `specify init` for another agent (such as `--integration copilot`) needs Claude added first:
`specify integration add claude`.

## Update

```
claude plugin marketplace update landspec && claude plugin update landspec@landspec
```

Then `/reload-plugins`, and **`/landspec:init` once in every project that already uses it**:
each project keeps its own copy of the extension under `.specify/`, and only `init` refreshes it
(it keeps the level). Details: [docs/reference.md](docs/reference.md#update).

## Start

| Your project | Run | Then |
|---|---|---|
| **New** (empty folder) | `/landspec:new` | the foundation spec it suggests: you pick the stack together with Claude, and it sets up the project (tooling, CI, containers) and landspec. To set up only landspec and describe the project yourself, run `/landspec:init`, then `/speckit-constitution` |
| **Existing** (has code, no spec-kit yet) | `/landspec:init` | nothing: it reads your code and fills the constitution for you |

`init` asks one question: how serious the project is (**lite**, **standard** or **full**, see
[Levels](#levels)). It changes nothing in your code and commits nothing; you review the setup and
commit it to the base branch (`develop` on standard and full; `init` offers that PR), because task
branches start there. What `new` asks and sets up: [docs/reference.md](docs/reference.md#what-new-does).

## The loop

| How often | Run | What you get |
|---|---|---|
| **Once per feature** | `/speckit-specify "what and why"` | the spec |
| | *(optional)* `/speckit-clarify` | fewer open questions, before planning |
| | `/speckit-plan` | the technical plan |
| | `/speckit-tasks` | the task list, grounded in the real code, **one issue per task**, and a spec PR |
| | *(optional)* `/speckit-analyze` | a consistency check (required on `full`) |
| | merge the spec PR | |
| **Then, once per feature** | `/landspec:implement` | every startable task at once, each in its own copy: **its branch → code → checks (tests, mutants) → review → PR**; a task that depends on another is stacked on its PR. Then all of them checked together against the suite and the spec, and any gap filed as a new task |
| | merge the PRs, in the order it prints | the issues close; run it again for what is left |
| *(or, once per task)* | `/landspec:next` | progress, then the next open task, the same way, one at a time; it offers `/landspec:implement` when two or more can start. Several features? `next 002` |
| **When every task is merged** | `/landspec:implement` | the full security audit, unattended, then the release PR, the tag and the release, one step per run; a confirmed critical or high holds the release |

**Small fixes don't need the feature loop.** A typo, a one-line bug fix or a dependency bump
goes on a normal branch with a normal PR, through `pr.sh fix`. The independent review, the hooks
and the CI gate still apply: no PR opens without a review, at any level. The spec, issue
and per-task flow are for features.

The spec PR and the task PRs are separate on purpose: task branches start from the base branch
and need `tasks.md` there, and each task PR stays small and closes one issue. See
**[examples/](examples/)** for one feature walked through from spec to merged PRs, with the
real issue and PR bodies.

When every task is merged, run `/landspec:implement` again, however the tasks were done: it checks the
whole feature on the base against the spec (once per commit; gaps become new tasks), audits the base
(`/landspec:security` `full`, unattended, once per commit) and makes the release. A confirmed critical
or high finding holds it, with nothing filed or posted, and the run ends with `run /landspec:security
<report>`, which tracks and fixes it without disclosing it.

> `/landspec:next` picks the next task for you. `/speckit-implement T007` does the same for a
> specific task. Either way, exactly one task per run.

Why one task = one issue = one branch = one PR, with the evidence: [docs/design.md](docs/design.md).

## Security, built in

| When | Check |
|---|---|
| **every commit** | refuses `.env`, keys and credential files, and tokens or passwords in the code. Under a second. |
| **every command Claude runs** | blocks `--no-verify`, `git add -A`, commits on base branches and pushes to them, and `gh pr create` outside `pr.sh` (a promotion between long-lived branches aside) |
| **every push** | re-checks every outgoing commit, including ones made with `--no-verify` |
| **before each PR** (one per task, `/landspec:implement` too) | an **independent review** by a fresh agent (`landspec:reviewer`, on Sonnet unless `review_model:` says `opus` or `fable`), in its own copy of the reviewed commit, that reads the diff and the code around it in one fast pass (following personal data and secrets into the helpers that log them), like Copilot code review, with no subscription needed, scanners on the changed files (the PR is refused until they ran on its exact diff), `/security-review` |
| **every PR, and weekly** | CI gate (standard and full): Gitleaks, OSV-Scanner and zizmor (Semgrep with the OWASP rules on `full`, from its image pinned by digest, its rules fetched from the Semgrep registry at run time; trivy on Dockerfiles and Terraform when the project has them), all pinned and checksum-verified |
| **before a release** | `/landspec:security`, the full audit, run unattended by `/landspec:implement` before the bump; a confirmed critical or high holds the release |

Why each layer exists, and what it can't do: **[docs/security.md](docs/security.md)**.

## Levels

Pick one at `init`, and change it any time with `/landspec:level`. Going down never deletes
files.

| | **lite** | **standard** (default) | **full** |
|---|---|---|---|
| For | prototypes, solo work | products, small teams | production, money, personal data |
| Branches | `feat/*` → `main` | `feat/*` → `develop` → `main` | `feat/*` → `develop` → `staging` → `main` |
| Constitution defaults | KISS, secrets, tests for logic, task = issue = PR | + security baseline, stack idioms, dependency policy, integration tests | + threat model per feature, data integrity, observability, releases |
| Added to the repo | git hooks, PR template, `.claude/settings.json` without AI attribution (only when the project has none yet) | + CI for your stack, security CI, Dependabot | + Semgrep in CI, CODEOWNERS, SECURITY.md, release workflow |
| Before each PR | asks first, then the independent review, recorded and required | the independent review, recorded and required | the same, and evidence is required |
| `/speckit-analyze` | optional | optional | required before any task: its report is recorded, and a changed `tasks.md` needs a new one |

Your stack is detected and shapes the CI and the constitution; your files are never overwritten.
Details, the configuration keys and what runs automatically: [docs/reference.md](docs/reference.md).

## Help

`/landspec:help` shows every command, level and setting. Ask it anything:
`/landspec:help why is the spec a separate PR?`

landspec got something wrong, or could do better? `/landspec:report` drafts an issue for this
repository from what just happened (versions, the message, where in landspec it comes from,
nothing private from your project), checks for duplicates, and files it once you say yes.

## Uninstall

`/landspec:remove` takes landspec out of one project (`--with-speckit` also removes
spec-kit's files, your constitution included); `/plugin uninstall landspec` removes the plugin from Claude Code. What
`remove` deletes and keeps: [docs/reference.md](docs/reference.md#uninstall).

## More

- [docs/design.md](docs/design.md): why it works this way (one task = one PR, the spec PR, the independent review, levels)
- [docs/reference.md](docs/reference.md): what runs automatically, configuration, Claude Code tools, `new`, update and uninstall details
- [docs/security.md](docs/security.md): every security layer and its limits
- [examples/](examples/): one feature from spec to merged PRs, with the real issue and PR bodies
- [docs/GUIDELINES.md](docs/GUIDELINES.md), [docs/GUARDRAILS.md](docs/GUARDRAILS.md), [docs/references.yaml](docs/references.yaml): how `new` and the reviews decide
