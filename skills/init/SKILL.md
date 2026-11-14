---
name: init
description: "Set up the current project (new or existing) with spec-kit and landspec: one task = one issue = one branch = one PR, security checks on every commit, push and PR, and best-practice defaults sized by complexity level (lite, standard, full)."
argument-hint: "[lite|standard|full]"
disable-model-invocation: true
---

# Set up a project with landspec

1. **Tools.** Check `git`, `gh` and `specify`.
   - If `specify` is missing, offer to install spec-kit (the version landspec is tested with):
     `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.5`.
     If `uv` is missing too, point to https://docs.astral.sh/uv/ and stop.
   - If `gh auth status` fails, ask the user to run `! gh auth login` and stop.
   - If `gh repo view` fails, there is no GitHub repository yet, and issues and PRs need one: ask
     its name and visibility and offer `gh repo create <name> --private --source . --remote origin`
     (`--public` for a public one; `git init -b main` first if there is no git repo). On no, go on
     without steps 4 and 5, and say that `/speckit-tasks` stops at creating the issues until there is one.
2. **Level.** Use the argument if it is `lite`, `standard` or `full`. If the project already has
   `.specify/extensions/landspec/landspec-config.yml`, this is an update: keep its `level:` and skip the
   question. Otherwise ask with these options, recommending one from what the repo shows:
   - **lite**: prototype, solo. `feat/*` → `main`, secret checks on commit and push, core defaults.
   - **standard** (default): a product, maybe a small team. Adds `develop`, CI, a security CI
     gate, Dependabot and the security baseline.
   - **full**: production with several environments. Adds `staging`, SAST in CI, CODEOWNERS,
     SECURITY.md, a release workflow, a threat model per feature, and required analysis.

   Recommend **full** for deploy or infra code, payments, personal data, or more than 2 active
   contributors (`git shortlog -sn --since=6.months | wc -l`); **lite** for an empty repo or
   experiment; otherwise **standard**.
3. **Setup.** From the project root run
   `bash "${CLAUDE_PLUGIN_ROOT}/bin/setup.sh" . --level <level>`. Add `--no-branches` if the user
   doesn't want `develop`/`staging` pushed to `origin`. On failure, show the output and stop.
   When it refuses because `this plugin copy is <plugin>, the project is at <project>`, show that
   line as is and suggest `/reload-plugins` (this session runs an older copy of the plugin); add
   `--downgrade` only when the user asks to take the project back to the older version.
   When it refuses because `origin/<base> is at landspec <version>`, show that line as is and stop.
4. **GitHub settings** (every level). Read the visibility with
   `gh repo view --json visibility -q .visibility`. Offer each one, explain it in one line, and run
   it only on yes:
   - Rebase merges off, so a task PR never lands as several commits and one revert removes it:
     `gh api -X PATCH repos/{owner}/{repo} -F allow_rebase_merge=false`.
   - On lite, merge commits off too (squash only: each task PR is one commit on `main`):
     `gh api -X PATCH repos/{owner}/{repo} -F allow_merge_commit=false -F allow_squash_merge=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY`.
     Standard and full keep merge commits for the promotion PRs (`develop` → `main`); their task
     PRs are squashed by convention.
   - Only when the visibility is `PUBLIC` (both are free there):
     - Secret scanning with push protection:
       `gh api -X PATCH repos/{owner}/{repo} -f 'security_and_analysis[secret_scanning][status]=enabled' -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'`
       (the brackets are quoted, so zsh does not expand them).
     - Private vulnerability reporting, so the `SECURITY.md` contact works:
       `gh api -X PUT repos/{owner}/{repo}/private-vulnerability-reporting`.
   - On a `PRIVATE` or `INTERNAL` repo, say in one line instead: secret scanning with push
     protection needs GitHub Secret Protection, and private vulnerability reporting is for public
     repos.

   If GitHub refuses one, say so plainly and continue.
5. **Branch protection** (standard and full). Offer it only once the checks are green on the base
   branch (`gh run list --branch <base branch>`). The gates read the whole history and every
   lockfile, and `enforce_admins` binds the owner too, so a finding that is already there would
   leave the setup PR red with no way to merge it. Until they are green, skip this step and say
   that running `/landspec:init` again offers it, and that docs/security.md ("When a gate is
   red") says how to get there. Otherwise explain it in one line, and run it only on yes:
   - Branch protection on the base branches, requiring a pull request and the checks to pass:
     `gh api -X PUT repos/{owner}/{repo}/branches/<branch>/protection` with
     `required_status_checks`, `enforce_admins: true`, `required_pull_request_reviews` and
     `restrictions: null`.
     - **Check names are job names, not workflow names.** GitHub matches each required check to
       a job's `name:`, or to the job's key when it has no name. Read them from the generated
       `.github/workflows/ci.yml` and `security.yml` (for example `rust`, `Secrets (gitleaks, full
       history)`). Never use `CI` or `Security`: no job reports under those names, so every PR
       would wait forever. Leave `Dependencies (osv-scanner)` out: it fails on any open advisory
       in the tree, so a new one would refuse every unrelated PR, and each Dependabot fix too. It
       stays a visible check on every PR and runs weekly.
     - **Approvals:** 1 on full, 0 on standard. On full with a single contributor
       (`git shortlog -sn | wc -l` is 1), say that requiring 1 approval would block their own
       PRs, and offer 0 until a second person joins.

   On a private repo it needs a paid GitHub plan. If GitHub refuses, say so plainly and continue:
   the local hooks and the CI gate still apply.
6. **Next.** If the repo already has code, run `/landspec:adopt` now. For a new project, tell
   the user to run `/speckit-constitution`.
7. Summarize in four lines: the level, the files created, updated or kept, the GitHub settings
   and protections enabled, and the next command. If the script said the git hooks are "not active in this clone
   yet", repeat the command it gave; if it said "add these lines to it", repeat those lines and
   where they go: without either, nothing checks commits locally. A machine-wide `core.hooksPath`
   stays in charge: never replace it. If it said a workflow "never runs on a task PR", repeat that
   line: until that branch is added, the project's own CI does not check task PRs. If the script
   created `.claude/settings.json`, say in one line that its `"attribution"` block removes Claude's
   commit and PR attribution lines for everyone who clones the repo, and that deleting the block
   keeps them (docs/reference.md, "AI attribution").
8. **Offer to commit it**, in one question: "Commit this on `chore/landspec-<version>` and open
   the PR into `<base>`?" (the version is `version:` in `.specify/extensions/landspec/extension.yml`;
   `<base>` is `base_branch:` in `landspec-config.yml`, or when that is `auto`, `develop` on standard and
   full and the default branch on lite). Task branches start from `<base>` and scripts read the
   level from the tree, so the setup has to land there, on an update too: anywhere else, the next
   branch loses `.specify` and the git hooks, or keeps the old version. The default branch gets it
   at the next promotion. On yes: `git fetch origin`, then `git switch -c <branch> origin/<base>` as its own command
   (the guard refuses a commit chained after it), taking the setup along (if git refuses because the two branches differ in those files, say so,
   and stop: run `/landspec:init` again from `<base>`). Stage **by name** only what the setup
   wrote (`.specify`, `.claude/skills`, and each file the script listed as created or updated;
   never `git add -A`), commit `chore: landspec <version> (level <level>)`, and open the PR as a
   small fix (`.specify/extensions/landspec/commands/pr.md`, "Not a task"): the review, then
   `pr.sh fix "chore: landspec <version> (level <level>)" <body-file>`, which opens it into `<base>`, with a
   two-line body saying what moved and that nothing else changed, plus its `## Review`. No spec, no
   issue; the hooks and CI still apply. Then
   `/landspec:adopt` (step 6) runs on that branch. If `origin/<base>` does not exist yet (the
   script said a branch is "not created yet"), there is no PR to open: tell the user to commit, push
   the default branch and run `/landspec:level <level>`. On no: leave it uncommitted for the user
   to review, and say so, and that its PR goes into `<base>`.
