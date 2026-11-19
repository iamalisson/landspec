#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh # branch.sh looks up the feature PR before it makes or pushes the branch
b="$SCRIPTS/branch.sh"

new_repo standard
commit_tasks '- [ ] T001 Split CI credentials into a deploy role in `infra/main.tf`
- [ ] T002 [P] [US1] Sandbox schedule in `infra/stack.tf`'

# ── Spec 008 T012: no task mode; a task id or --from is refused and changes nothing ──
state() { git branch --show-current; git for-each-ref --format='%(refname) %(objectname)'; git ls-remote origin; cat .specify/feature.json; }
s0="$(state)"
check "when branch.sh is given a feature and a task id, then it exits non-zero with the takes-a-feature message and changes nothing" \
  'one_refusal "branch.sh takes a feature, not a task: tasks are built on the feature branch" "$b" 001 T001 && [[ "$(state)" == "$s0" ]]'
check "when branch.sh is given a task id alone, then it refuses the same way" \
  'one_refusal "branch.sh takes a feature, not a task" "$b" T001 && [[ "$(state)" == "$s0" ]]'
check "when branch.sh is given --from, then it is refused with the usage and changes nothing" \
  'one_refusal "usage: branch.sh [feature]" "$b" 001 --from x && [[ "$(state)" == "$s0" ]]'
check "when branch.sh is given two features, then it refuses" 'fails_with "one feature at most" "$b" 001 002'
check "when the feature name matches nothing, then it refuses" '! "$b" 009'

out="$("$b" 001)"
check "when the branch does not exist, then it is created from origin/develop (standard) and printed" \
  '[[ "$out" == "BRANCH=feat/001-demo FEATURE=001 BASE=develop" && "$(git branch --show-current)" == feat/001-demo && "$(git rev-parse HEAD)" == "$(git rev-parse origin/develop)" ]]'
check "then the start is logged on the new branch" \
  'grep -qE "^[0-9]+ [0-9T:-]+Z feat/001-demo start feature=001-demo$" "$(git rev-parse --git-common-dir)/landspec-events"'
check "when run again on the branch, then it logs no second start" \
  '"$b" 001 >/dev/null && [[ "$(grep -c " feat/001-demo start " "$(git rev-parse --git-common-dir)/landspec-events")" == 1 ]]'

# An origin that refuses the push (a pre-receive hook), removed afterwards: the next run pushes it.
git switch --quiet main
mkdir -p specs/002-reports; echo '# R' > specs/002-reports/spec.md
printf '#!/bin/sh\necho "pushes refused here" >&2\nexit 1\n' > "$TMP/origin.git/hooks/pre-receive"; chmod +x "$TMP/origin.git/hooks/pre-receive"
check "when origin refuses the push of a new branch, then branch.sh fails saying to run it again" \
  'fails_with "could not push feat/002-reports to origin; run branch.sh again" "$b" 002 && [[ "$(git branch --show-current)" == feat/002-reports ]]'
rm "$TMP/origin.git/hooks/pre-receive"
check "when run again once origin accepts it, then the branch is pushed" \
  '"$b" 002 >/dev/null && [[ "$(git ls-remote origin refs/heads/feat/002-reports | cut -f1)" == "$(git rev-parse HEAD)" ]]'
git switch --quiet main

set_cfg level lite
check "when the level is lite, then the base is the default branch" \
  'out="$("$b" 001)"; [[ "$out" == "BRANCH=feat/001-demo FEATURE=001 BASE=main" ]]'
set_cfg level standard

# The analysis marker is checked by implement.sh status on level full; analyzed.sh refuses a non-report.
git switch --quiet main
check "when analyzed.sh is run with no report, then it refuses" 'fails_with "usage: analyzed.sh <report-file>" "$SCRIPTS/analyzed.sh"'
printf '%s\n' '# Notes' 'nothing analyzed here' > "$TMP/not-a-report.md"
check "when analyzed.sh is given a file without the analysis headings, then it refuses" \
  'fails_with "is not a /speckit-analyze report" "$SCRIPTS/analyzed.sh" "$TMP/not-a-report.md"'
printf '%s\n' '## Specification Analysis Report' '' '**Coverage Summary Table:**' '' '| Requirement | Has Task |' > "$TMP/report.md"
check "when analyzed.sh is given a real report, then it is accepted and kept next to the marker" \
  '"$SCRIPTS/analyzed.sh" "$TMP/report.md" && cmp -s "$TMP/report.md" "$(git rev-parse --git-common-dir)/landspec-analyzed/001-demo.report.md"'

# A second worktree, as `claude --worktree` makes: it shares the repo but has its own git dir,
# and none of the untracked files (feature.json is one of them).
git switch --quiet main; git branch --quiet -D feat/001-demo
git worktree add --quiet "$TMP/wt" origin/develop 2>/dev/null
mkdir -p "$TMP/wt/.specify/extensions/landspec"
cp .specify/extensions/landspec/landspec-config.yml "$TMP/wt/.specify/extensions/landspec/" # committed in a real project
ln -s "$ROOT/extension/scripts" "$TMP/wt/.specify/extensions/landspec/scripts"
check "when the feature's branch is switched to in a fresh worktree, then it is on the feature branch there" \
  '(cd "$TMP/wt" && [[ ! -f .specify/feature.json ]] && "$b" 001 | grep -qx "BRANCH=feat/001-demo FEATURE=001 BASE=develop")'
check "then the worktree's own feature.json points spec-kit at the feature" \
  'grep -q "\"feature_directory\": \"specs/001-demo\"" "$TMP/wt/.specify/feature.json"'
check "then the main checkout is untouched" \
  '[[ "$(git -C "$TMP/wt" branch --show-current)" == feat/001-demo && "$(git branch --show-current)" == main ]]'
mkdir -p specs/002-other; printf '%s\n' '- [ ] T002 Other thing in `o`' > specs/002-other/tasks.md
echo '{ "feature_directory": "specs/002-other" }' > .specify/feature.json # the main checkout moved on
check "when the main checkout moves to another feature, then the worktree keeps its own" \
  '(cd "$TMP/wt" && bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir") | grep -qx "specs/001-demo"'
echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json; rm -rf specs/002-other
git worktree remove --force "$TMP/wt"

# A repo whose default branch is master and whose origin/HEAD was never set.
git switch --quiet main; git branch --quiet -D feat/001-demo
git push --quiet --no-verify origin --delete feat/001-demo
git push --quiet --no-verify origin main:master
git remote set-head origin --delete >/dev/null 2>&1 || git symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null || true
git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/master # a remote whose default is master
git push --quiet --no-verify origin --delete main
git fetch --quiet --prune origin
git branch --quiet -m main master
set_cfg level lite
check "when origin/HEAD is unset and the repo uses master, then master is the base (not a missing main)" \
  'out="$("$b" 001)"; grep -q "BASE=master" <<<"$out"'

# The base really is the base: develop and main differ, and the feature branch starts from develop.
cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo"
new_repo standard
commit_tasks '- [ ] T001 Thing in `a`'
git switch --quiet -c tmp origin/develop; echo d > dev-only; git add dev-only; git commit --quiet --no-verify -m dev-only
git push --quiet --no-verify origin tmp:develop; git switch --quiet main; git branch --quiet -D tmp
echo m > main-only; git add main-only; git commit --quiet --no-verify -m main-only; git push --quiet --no-verify origin main
"$b" 001 >/dev/null
check "when develop and main differ, then the feature branch starts from develop, not main" '[[ -f dev-only && ! -f main-only ]]'

# spec-kit's --timestamp numbering: specs/YYYYMMDD-HHMMSS-name.
git switch --quiet main
mkdir -p specs/20261104-153000-ts; printf '%s\n' '- [ ] T1000 Big list in `b`' > specs/20261104-153000-ts/tasks.md
echo '{ "feature_directory": "specs/20261104-153000-ts" }' > .specify/feature.json
out="$("$b")"
check "when features use timestamp numbering, then the branch carries the whole folder name" \
  '[[ "$out" == "BRANCH=feat/20261104-153000-ts FEATURE=20261104-153000 BASE=develop" ]]'
rm .specify/feature.json # a fresh worktree has none
check "then that branch still resolves to its own timestamp feature" \
  'bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir" | grep -qx "specs/20261104-153000-ts"'
echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

# Spec 003: a reviewer's copy under .claude/worktrees is not the author's uncommitted work.
git switch --quiet main; echo kept > tracked.txt; git add tracked.txt; git commit --quiet -m "test: tracked"
mkdir -p .claude/worktrees/agent-x; echo x > .claude/worktrees/agent-x/f
check "when only an untracked .claude/worktrees/agent-x/ folder is there, then switching to the feature branch does not refuse" \
  '"$b" 001 >/dev/null && [[ "$(git branch --show-current)" == feat/001-demo ]]'
git switch --quiet main; echo changed >> tracked.txt
check "when a tracked file has an uncommitted edit, then switching to the feature branch refuses" \
  'fails_with "uncommitted changes" "$b" 001'
git checkout --quiet -- tracked.txt; rm -rf .claude

# ── Spec 008 T001: the feature mode, one branch per feature made when the spec is written ──
cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/b" "$TMP/wt"
new_repo standard
mkdir -p specs/002-x; echo '# X' > specs/002-x/spec.md # what /speckit-specify leaves: an uncommitted folder
echo '{ "feature_directory": "specs/002-x" }' > .specify/feature.json
main0="$(git rev-parse main)"; dev0="$(git rev-parse origin/develop)"
out="$("$b")"
check "when a new feature's spec folder is uncommitted, then branch.sh makes feat/002-x from origin/develop and prints it" \
  '[[ "$out" == "BRANCH=feat/002-x FEATURE=002 BASE=develop" && "$(git branch --show-current)" == feat/002-x && "$(git rev-parse HEAD~1)" == "$dev0" ]]'
check "then the folder is committed as docs(specs): add 002-x spec and the branch is on origin" \
  '[[ "$(git log -1 --format=%s)" == "docs(specs): add 002-x spec" && -z "$(git status --porcelain specs)" && "$(git cat-file -p HEAD:specs/002-x/spec.md)" == "# X" ]] \
   && [[ "$(git ls-remote origin refs/heads/feat/002-x | cut -f1)" == "$(git rev-parse HEAD)" && "$(git rev-parse --abbrev-ref @{u})" == origin/feat/002-x ]]'
check "then the base is unchanged, locally and on origin" \
  '[[ "$(git rev-parse main)" == "$main0" && "$(git ls-remote origin refs/heads/develop | cut -f1)" == "$dev0" ]]'
head1="$(git rev-parse HEAD)"
check "when run again, then it stays on the branch without a new commit" \
  '[[ "$("$b" 002)" == "BRANCH=feat/002-x FEATURE=002 BASE=develop" && "$(git rev-parse HEAD)" == "$head1" ]]'
rm .specify/feature.json # a fresh worktree has none
check "when on a feature branch with no feature.json, then feature_dir resolves its folder" \
  'bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir" | grep -qx "specs/002-x"'
echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json
check "when on a task ref of that feature, then feature_dir resolves the same folder, whatever the active feature" \
  'git switch --quiet -c landspec/002-t001-task && bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir" | grep -qx "specs/002-x"'
git switch --quiet --detach feat/002-x; git branch --quiet -D feat/002-x landspec/002-t001-task
check "when the branch is only on origin, then branch.sh switches to it tracking origin's" \
  '"$b" 002 >/dev/null && [[ "$(git branch --show-current)" == feat/002-x && "$(git rev-parse HEAD)" == "$head1" && "$(git rev-parse --abbrev-ref @{u})" == origin/feat/002-x ]]'
git switch --quiet main
mkdir -p specs/003-y; echo '# Y' > specs/003-y/spec.md; echo dirty > dirty.txt
check "when a file outside the spec folder is uncommitted, then it refuses before any switch" \
  'one_refusal "uncommitted changes on '"'"'main'"'"'" "$b" 003 && [[ "$(git branch --show-current)" == main ]] \
   && ! git show-ref --verify --quiet refs/heads/feat/003-y && ! git ls-remote --exit-code origin refs/heads/feat/003-y'
rm dirty.txt
mkdir -p specs/004-z; printf '%s\n' '- [ ] T001 Old way in `a` — #5' > specs/004-z/tasks.md
check "when the feature was started under the per-task flow, then it prints LEGACY= and exits non-zero on the same branch" \
  'rc=0; out="$("$b" 004 2>"$TMP/err")" || rc=$?; ((rc != 0)) && [[ "$out" == LEGACY=004-z ]] && grep -q "per-task flow" "$TMP/err" && [[ "$(git branch --show-current)" == main ]]'
# A folder committed on the current branch only (not on the base) and then edited: git alone would refuse the switch.
rm -r specs/003-y specs/004-z
mkdir -p specs/005-w; echo '# W' > specs/005-w/spec.md; git add specs/005-w; git commit --quiet -m "docs: 005 here only"
echo '# W edited' > specs/005-w/spec.md; echo new > specs/005-w/plan.md
check "when the spec folder is committed here only and edited, then its current content is carried and committed on the new branch" \
  '"$b" 005 >/dev/null && [[ "$(git branch --show-current)" == feat/005-w && "$(git cat-file -p HEAD:specs/005-w/spec.md)" == "# W edited" && "$(git cat-file -p HEAD:specs/005-w/plan.md)" == new && -z "$(git status --porcelain)" ]]'
# /speckit-specify run on another feature's branch: feature.json names the new feature, the branch the old one.
mkdir -p specs/006-b; echo '# B' > specs/006-b/spec.md; echo '{ "feature_directory": "specs/006-b" }' > .specify/feature.json
check "when on feature A's branch feature.json names a new uncommitted feature B, then branch.sh with no argument makes B's branch with B's folder" \
  '"$b" | grep -qx "BRANCH=feat/006-b FEATURE=006 BASE=develop" && [[ "$(git branch --show-current)" == feat/006-b && "$(git rev-parse HEAD~1)" == "$(git rev-parse origin/develop)" && "$(git cat-file -p HEAD:specs/006-b/spec.md)" == "# B" ]] \
   && ! git cat-file -e HEAD:specs/005-w 2>/dev/null && grep -q "specs/006-b" .specify/feature.json'
git switch --quiet feat/005-w; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json
check "when on a feature branch with a local feature.json naming another feature, then feature_dir follows feature.json" \
  'bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir" | grep -qx "specs/001-demo"'

exit "$FAIL"
