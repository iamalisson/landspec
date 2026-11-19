#!/usr/bin/env bash
# Run the project's mutation-testing command on this branch's changes and keep its output.
#   mutants.sh
# The command is the constitution's **Commands** line: mutate `<command>`. It must exit non-zero
# when a mutant survives, and it gets two variables to scope itself to the change:
#   LANDSPEC_DIFF_FILE      a unified diff of this branch against the base (cargo mutants --in-diff)
#   LANDSPEC_CHANGED_FILES  the changed source files, space-separated, tests excluded (stryker --mutate,
#                           or a project's own harness: docs/reference.md, "Mutation testing")
# Prints one line: "mutants ok|survivors|unavailable|missing|skipped <detail>", then REPORT_DIR=<dir>.
# unavailable: the command exited 126 or 127, so it never ran. A wrapper (uv run) exits otherwise,
# so a tool missing behind one stays survivors.
# Output goes to .git/landspec-mutants/<timestamp>/ so it is never committed; the result line is also
# this diff's record (.git/landspec-mutants/<diff id>), which pr.sh fix and pr.sh feature --ready require.
set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
landspec_cd_root
# No set -e here: a die inside $(…) only ends the subshell, and an empty pattern would drop every file.
re="$(test_path_re)" || exit 1

rec="$(diff_record landspec-mutants)" || exit 1
# Every worktree shares this folder: the suffix keeps two runs in the same second apart.
dir="$(git rev-parse --git-common-dir)/landspec-mutants"; mkdir -p "$dir"
dir="$(mktemp -d "$dir/$(date +%Y%m%d-%H%M%S).XXXXXX")" || die "cannot create a report folder in $dir"
finish() { echo "mutants $1 $2" | tee "$rec"; echo "REPORT_DIR=$dir"; exit 0; }

cmd="$(constitution_cmd mutate)"
[[ -n "$cmd" ]] || finish missing "no 'mutate' command in the constitution's **Commands** line; /landspec:adopt fills it"

from="$(git merge-base HEAD "$(base_ref)" 2>/dev/null || echo HEAD)"
landspec_diff "$from" HEAD > "$dir/changes.diff"
changed="$(git diff --name-only --diff-filter=ACMR "$from" HEAD | grep -vE "$re" | tr '\n' ' ')"
changed="${changed% }"
[[ -n "$changed" ]] || finish skipped "no changed source files"

rc=0; LANDSPEC_DIFF_FILE="$dir/changes.diff" LANDSPEC_CHANGED_FILES="$changed" bash -c "$cmd" > "$dir/mutants.log" 2>&1 || rc=$?
case "$rc" in
  0) finish ok "every mutant in the changed lines was caught ($cmd)" ;;
  126|127) finish unavailable "the command could not run ($cmd); see $dir/mutants.log" ;;
esac
finish survivors "a mutant survived: a behavior no test checks; see $dir/mutants.log"
