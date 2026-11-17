---
name: adopt
description: "Adopt landspec in an existing codebase: read the repo and fill the spec-kit constitution (project, stack, commands, project principles) from what is really there, merging any constitution that already exists. Run after /landspec:init on a repo that already has code."
---

# Adopt landspec in an existing project

1. If `.specify/extensions/landspec/` does not exist, stop and ask the user to run
   `/landspec:init` first (only the user can run it), then `/landspec:adopt` again.
2. **Read the project; don't guess.** Look at:
   - the manifests (`Cargo.toml`, `package.json` and lockfile, `pyproject.toml`, `go.mod`, …);
   - the CI workflows and the task runner (`justfile`, `Makefile`, `package.json` scripts);
   - `README`, `CLAUDE.md`/`AGENTS.md`, `docs/`, and the infra folders;
   - `bash .specify/extensions/landspec/scripts/detect-stack.sh`.

   Prefer what the code and config say over what the docs say, and note any stale docs.
3. **Check the formatter hooks.** Run `bash .specify/extensions/landspec/scripts/formatters.sh`
   (it runs each pre-commit hook in a throwaway worktree, never on the user's files). For each
   `REWRITES=<hook> <changed>/<covered>` line, tell the user that `<hook>` would rewrite `<changed>`
   of the `<covered>` files it covers, so every task's commit would carry those rewrites or be
   refused, and give the two options: format the code once in its own PR, or remove or scope the
   hook. Name each `UNCHECKED=` hook with its reason. Change nothing: the user decides.
4. **Fill `.specify/memory/constitution.md`:**
   - `[PROJECT_NAME]`, `[PROJECT_PURPOSE]` (one paragraph);
   - `[STACK]`, with versions from the manifests;
   - `[BUILD_COMMAND]` / `[TEST_COMMAND]` / `[LINT_COMMAND]`: the commands that really work here;
     when the project has no such step (no build, say), leave its placeholder, so CI does not run it;
   - `[MUTATE_COMMAND]`: the project's mutation-testing tool (cargo-mutants, mutmut, StrykerJS,
     gremlins; see `references.yaml`), scoped to the change where the tool allows it through
     `$LANDSPEC_DIFF_FILE` (a diff against the base) or `$LANDSPEC_CHANGED_FILES` (changed sources, space
     separated), and exiting non-zero when a mutant survives, for example
     `cargo mutants --in-diff "$LANDSPEC_DIFF_FILE"`, or for mutmut, whose own exit is 0 on a survivor,
     `mutmut run && ! mutmut results | grep -q survived`. It runs before every PR. No such tool, but
     the project has **its own mutation harness** (a script that applies a fixed list of mutants and
     runs the tests for each, named in the constitution, the README or the test folder): `mutate` is
     that script, given `$LANDSPEC_CHANGED_FILES` so it runs only the cases for the changed files
     (docs/reference.md, "Mutation testing"); if it cannot filter yet, say so in the summary, since
     every PR then runs all of it. Neither a tool nor a harness: leave the placeholder and say so in
     the summary, since adding one is a small-fix PR;
   - a **Commands** line that already exists but has no `mutate` entry gets one appended;
   - `[PROJECT_PRINCIPLES]`: only rules specific to this codebase that you can point to (layer
     boundaries, where auth lives, how migrations run), each backed by a file path.

   Never edit between `<!-- landspec:start` and `<!-- landspec:end -->`. Once the **Commands** line is
   filled, re-run `bash .specify/extensions/landspec/scripts/level.sh <current level> --no-branches`:
   it rewrites the landspec block and the generated CI (`.github/workflows/ci.yml`, while it still
   carries the `# landspec: managed file` line) with the project's real commands.
5. **If a constitution already existed** (not the landspec template): keep its principles and wording.
   Only add what is missing. List every place where it contradicts a landspec default, and ask the
   user which one wins. Don't decide alone.
6. Fill the version line: `1.0.0`, with today's date as ratified and amended (or bump the
   existing version: MINOR when adding sections).
7. Show a short summary: what was filled and from which file, contradictions found, docs that
   look stale. Leave everything uncommitted for the user to review.
