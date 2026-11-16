#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
b="$SCRIPTS/branch.sh"

new_repo standard
commit_tasks '- [ ] T001 Split CI credentials into a deploy role in `infra/main.tf` — #57
- [ ] T002 [P] [US1] Sandbox schedule in `infra/stack.tf` — #64
- [ ] T003 Task without an issue in `x`'

out="$("$b" T001)"
check "when the branch does not exist, then it is created from origin/develop (standard)" \
  '[[ "$(git branch --show-current)" == feat/001-t001-split-ci-credentials-into && "$(git merge-base HEAD origin/develop)" == "$(git rev-parse origin/develop)" ]]'
check "then it prints the branch, issue, task and base" \
  '[[ "$out" == "BRANCH=feat/001-t001-split-ci-credentials-into ISSUE=57 TASK=T001 BASE=develop" ]]'
check "when run again on the same branch, then it succeeds" '"$b" T001'
check "then the new branch was pushed to origin at once (the claim)" 'git ls-remote --exit-code origin feat/001-t001-split-ci-credentials-into'
check "then the start is logged on the new branch" \
  'grep -qE "^[0-9]+ [0-9T:-]+Z feat/001-t001-split-ci-credentials-into start task=T001$" "$(git rev-parse --git-common-dir)/landspec-events"'

# F1.1: an origin that refuses the claim push (a pre-receive hook), removed afterwards.
git switch --quiet main
printf '#!/bin/sh\necho "claims refused here" >&2\nexit 1\n' > "$TMP/origin.git/hooks/pre-receive"; chmod +x "$TMP/origin.git/hooks/pre-receive"
check "when origin refuses the claim push, then branch.sh exits 0 and prints could not claim" \
  'out="$("$b" T002 2>&1)"; grep -qx "landspec: warning: could not claim feat/001-t002-sandbox-schedule on origin: .*claims refused here.*; other clones may start this task" <<<"$out"'
rm "$TMP/origin.git/hooks/pre-receive"
git switch --quiet main; git branch --quiet -D feat/001-t002-sandbox-schedule 2>/dev/null || true

git switch --quiet main
mkdir -p specs/002-reports; printf '%s\n' '- [ ] T001 Monthly report in `r.py` — #30' > specs/002-reports/tasks.md
git add specs/002-reports; git commit --quiet -m "docs: 002"; git push --quiet origin main; git push --quiet origin main:develop
check "when a feature is named before the task, then that feature's task is used, not the active one" \
  '"$b" 002 T001 | grep -q "BRANCH=feat/002-t001-monthly-report ISSUE=30" && grep -q specs/002-reports .specify/feature.json'
check "when the feature name matches nothing, then it refuses" '! "$b" 009 T001'

# #185: a short task without " in <path>" keeps its branch name when it gains a dependency.
git switch --quiet main
mkdir -p specs/003-ship; printf '%s\n' '- [ ] T001 Ship it — #40' > specs/003-ship/tasks.md
git add specs/003-ship; git commit --quiet -m "docs: 003"; git push --quiet origin main; git push --quiet origin main:develop
"$b" 003 T001 >/dev/null; git switch --quiet main
printf '%s\n' '- [ ] T001 Ship it (depends on T002) — #40' > specs/003-ship/tasks.md
git add specs/003-ship; git commit --quiet -m "docs: 003 dependency"; git push --quiet origin main; git push --quiet origin main:develop
check "when a task without a path gains a dependency, then branch.sh gives the same branch name as before" \
  '"$b" 003 T001 | grep -qx "BRANCH=feat/003-t001-ship-it ISSUE=40 TASK=T001 BASE=develop" && [[ "$(git branch --show-current)" == feat/003-t001-ship-it ]]'
git switch --quiet main; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

git switch --quiet main
"$b" T002 >/dev/null
check "when the task has [P] and [US1] markers, then they are left out of the name" \
  '[[ "$(git branch --show-current)" == feat/001-t002-sandbox-schedule ]]'

"$b" T001 >/dev/null
check "when the branch exists locally, then it switches to it" \
  '[[ "$(git branch --show-current)" == feat/001-t001-split-ci-credentials-into ]]'

echo dirty > dirty.txt
check "when the tree is dirty and the target differs, then it refuses and stays put" \
  '! "$b" T002 && [[ "$(git branch --show-current)" == feat/001-t001-split-ci-credentials-into ]]'
rm dirty.txt

check "when the task has no issue, then it refuses" '! "$b" T003'
check "when the task does not exist, then it refuses" '! "$b" T999'
check "when the argument is not one task ID, then it refuses" '! "$b" 57 && ! "$b" "T001 T002"'

git switch --quiet main
sed -i.bak 's/^level: .*/level: lite/' .specify/extensions/landspec/landspec-config.yml
"$b" T002 >/dev/null || true
check "when the level is lite, then the base is the default branch" \
  'out="$("$b" T001)"; grep -q "BASE=main" <<<"$out"'

git switch --quiet main
mkdir -p specs/002-new
printf '%s\n' '- [ ] T001 New thing in `a` — #1' > specs/002-new/tasks.md
echo '{ "feature_directory": "specs/002-new" }' > .specify/feature.json
git add specs/002-new; git commit --quiet -m wip
check "when tasks.md is not on the base yet, then it refuses and says to merge the spec PR" \
  'fails_with "merge the spec PR" "$b" T001'
git reset --quiet --hard HEAD~1
echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

printf '%s\n' '- [ ] T008 Converge thing in `v` — #88' >> specs/001-demo/tasks.md
git add specs; git commit --quiet -m wip
check "when tasks.md is on the base without the task's line, then it refuses before the claim push" \
  'fails_with "merge the spec PR first" "$b" T008 && ! git ls-remote --exit-code --heads origin "feat/001-t008-*" && [[ "$(git branch --show-current)" == main ]]'
git switch --quiet main; git reset --quiet --hard HEAD~1

sed -i.bak 's/^level: .*/level: full/' .specify/extensions/landspec/landspec-config.yml
check "when the level is full and analysis did not run, then it refuses" \
  'fails_with "speckit-analyze" "$b" T001'
check "when analyzed.sh is run with no report, then it refuses and branch.sh on full still refuses" \
  'fails_with "usage: analyzed.sh <report-file>" "$SCRIPTS/analyzed.sh"; fails_with "speckit-analyze" "$b" T001'
printf '%s\n' '# Notes' 'nothing analyzed here' > "$TMP/not-a-report.md"
check "when analyzed.sh is given a file without the analysis headings, then it refuses and branch.sh on full still refuses" \
  'fails_with "is not a /speckit-analyze report" "$SCRIPTS/analyzed.sh" "$TMP/not-a-report.md"; fails_with "speckit-analyze" "$b" T001'
printf '%s\n' '## Specification Analysis Report' '' '**Coverage Summary Table:**' '' '| Requirement | Has Task |' > "$TMP/report.md"
check "when analyzed.sh is given a real report, then it is accepted and kept next to the marker" \
  '"$SCRIPTS/analyzed.sh" "$TMP/report.md" && cmp -s "$TMP/report.md" "$(git rev-parse --git-common-dir)/landspec-analyzed/001-demo.report.md"'
check "when the level is full and analysis ran on the current tasks, then it proceeds" '"$b" T001'
git switch --quiet main
printf '%s\n' '- [ ] T009 Added after the analysis in `z` — #90' >> specs/001-demo/tasks.md
git commit --quiet --no-verify -am "tasks changed"; git push --quiet --no-verify origin main:develop
check "when tasks.md changed after the analysis, then it refuses until analysis runs again" 'fails_with "speckit-analyze" "$b" T001'
"$SCRIPTS/analyzed.sh" "$TMP/report.md" >/dev/null

# Parallel work: a second worktree, as `claude --worktree` makes for a [P] task. It shares the
# repo but has its own git dir, and none of the untracked files (feature.json is one of them).
git switch --quiet main
git worktree add --quiet "$TMP/wt" origin/develop 2>/dev/null
mkdir -p "$TMP/wt/.specify/extensions/landspec"
cp .specify/extensions/landspec/landspec-config.yml "$TMP/wt/.specify/extensions/landspec/" # committed in a real project
ln -s "$ROOT/extension/scripts" "$TMP/wt/.specify/extensions/landspec/scripts"
check "when a task starts in a fresh worktree on level full, then the analysis done in the main checkout counts" \
  '(cd "$TMP/wt" && [[ ! -f .specify/feature.json ]] && "$b" T002 | grep -q "TASK=T002")'
check "then the worktree's own feature.json points spec-kit at the same feature" \
  'grep -q "\"feature_directory\": \"specs/001-demo\"" "$TMP/wt/.specify/feature.json"'
check "then the worktree is on the task's own branch, and the main checkout is untouched" \
  '[[ "$(git -C "$TMP/wt" branch --show-current)" == feat/001-t002-* && "$(git branch --show-current)" == main ]]'
mkdir -p specs/002-other; printf '%s\n' '- [ ] T002 Other thing in `o` — #99' > specs/002-other/tasks.md
echo '{ "feature_directory": "specs/002-other" }' > .specify/feature.json # the main checkout moved on
check "when the main checkout moves to another feature, then the worktree's task branch keeps its own" \
  '(cd "$TMP/wt" && bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir") | grep -qx "specs/001-demo"'
echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json; rm -rf specs/002-other
git worktree remove --force "$TMP/wt"

# A repo whose default branch is master and whose origin/HEAD was never set.
git switch --quiet main
git push --quiet --no-verify origin main:master
git remote set-head origin --delete >/dev/null 2>&1 || git symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null || true
git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/master # a remote whose default is master
git push --quiet --no-verify origin --delete main
git fetch --quiet --prune origin
git branch --quiet -m main master
sed -i.bak 's/^level: .*/level: lite/' .specify/extensions/landspec/landspec-config.yml
check "when origin/HEAD is unset and the repo uses master, then master is the base (not a missing main)" \
  'out="$("$b" T001)"; grep -q "BASE=master" <<<"$out"'

# The base really is the base: develop and main differ, and a task branch must start from develop.
cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo"
new_repo standard
commit_tasks '- [ ] T001 Thing in `a` — #5'
git switch --quiet -c tmp origin/develop; echo d > dev-only; git add dev-only; git commit --quiet --no-verify -m dev-only
git push --quiet --no-verify origin tmp:develop; git switch --quiet main; git branch --quiet -D tmp
echo m > main-only; git add main-only; git commit --quiet --no-verify -m main-only; git push --quiet --no-verify origin main
"$b" T001 >/dev/null
check "when develop and main differ, then the task branch starts from develop, not main" '[[ -f dev-only && ! -f main-only ]]'

# spec-kit's --timestamp numbering: specs/YYYYMMDD-HHMMSS-name.
git switch --quiet -c ts origin/develop
mkdir -p specs/20261104-153000-ts; printf '%s\n' '- [ ] T1000 Big list in `b` — #77' > specs/20261104-153000-ts/tasks.md
git add specs; git commit --quiet --no-verify -m ts; git push --quiet --no-verify origin ts:develop
echo '{ "feature_directory": "specs/20261104-153000-ts" }' > .specify/feature.json
out="$("$b" T1000)"
check "when features use timestamp numbering and the task ID has 4 digits, then the branch carries both" \
  '[[ "$out" == "BRANCH=feat/20261104-153000-t1000-big-list ISSUE=77 TASK=T1000 BASE=develop" ]]'
echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json
check "then that branch still resolves to its own timestamp feature" \
  'bash -c "source \"$SCRIPTS/lib.sh\"; feature_dir" | grep -qx "specs/20261104-153000-ts"'

# Spec 003: a reviewer's copy under .claude/worktrees is not the author's uncommitted work.
git switch --quiet main; echo kept > tracked.txt; git add tracked.txt; git commit --quiet -m "test: tracked"
mkdir -p .claude/worktrees/agent-x; echo x > .claude/worktrees/agent-x/f
check "when only an untracked .claude/worktrees/agent-x/ folder is there, then switching to a task branch does not refuse" \
  '"$b" 001 T001 >/dev/null && [[ "$(git branch --show-current)" == feat/001-t001-* ]]'
git switch --quiet main; echo changed >> tracked.txt
check "when a tracked file has an uncommitted edit, then switching to a task branch refuses" \
  'fails_with "uncommitted changes" "$b" 001 T001'
git checkout --quiet -- tracked.txt; rm -rf .claude

# ── Spec 004 T001: the claim is exclusive across clones ──
cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/b"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5
- [ ] T002 [P] Add filters in `src/filters.ts` — #6'
git clone --quiet -b main "$TMP/origin.git" "$TMP/b"; cp -a .specify "$TMP/b/"
cd "$TMP/b"; git config user.email t@t; git config user.name t; git config commit.gpgsign false
# The race: clone A claims T001 after B's fetch and before B's push (B's branch checkout runs it, once).
printf '#!/bin/sh\n[ -e "%s/raced" ] && exit 0; touch "%s/raced"\nunset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE\ncd "%s/repo" && "%s" T001 >/dev/null 2>&1\nexit 0\n' "$TMP" "$TMP" "$TMP" "$b" > .git/hooks/post-checkout
chmod +x .git/hooks/post-checkout
brc=0; out="$("$b" T001 2>&1)" || brc=$?
rm .git/hooks/post-checkout
check "when clone A claims the task between clone B's fetch and B's claim push, then B exits 3 with the claimed-elsewhere message" \
  '[[ $brc == 3 ]] && grep -qxF "landspec: T001 was claimed elsewhere (feat/001-t001-add-search is on origin)" <<<"$out"'
check "then B is back on its starting branch with no local task branch" \
  '[[ "$(git branch --show-current)" == main ]] && ! git show-ref --verify --quiet refs/heads/feat/001-t001-add-search'
git fetch --quiet
brc=0; "$b" T001 >/dev/null 2>&1 || brc=$?
check "when the branch exists only on origin, then branch.sh switches to it with --track and exits 0" \
  '[[ $brc == 0 && "$(git branch --show-current)" == feat/001-t001-add-search && "$(git rev-parse --abbrev-ref @{u})" == origin/feat/001-t001-add-search ]]'
git switch --quiet main
git remote set-url origin "$TMP/nowhere.git"
brc=0; out="$("$b" T002 2>&1)" || brc=$?
check "when origin is unreachable, then the warning is printed and the branch kept" \
  '[[ $brc == 0 && "$(git branch --show-current)" == feat/001-t002-add-filters ]] && grep -q "landspec: warning: could not claim feat/001-t002-add-filters on origin" <<<"$out"'
cd "$TMP/repo"

# ── Spec 004 T002: branch.sh --from stacks a task on another task's reviewed branch ──
cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/b" "$TMP/wt"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5
- [ ] T002 Add filters in `src/filters.ts` — #6'
r="$SCRIPTS/review.sh"; P=feat/001-t001-add-search; C=feat/001-t002-add-filters
review_ready() { printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(git merge-base HEAD origin/develop)" "$(git rev-parse HEAD)" > "$TMP/rep.md"; "$r" record "$TMP/rep.md" >/dev/null 2>&1; }
"$b" T001 >/dev/null 2>&1; echo a > a.txt; git add a.txt; git commit --quiet -m "feat: a"
check "when --from names a branch with no recorded review, then it refuses naming the branch and starts nothing" \
  'fails_with "--from $P" "$b" T002 --from "$P" && [[ "$(git branch --show-current)" == "$P" ]] && ! git show-ref --verify --quiet "refs/heads/$C"'
check "when --from names a branch that does not exist, then it refuses naming it" \
  'fails_with "--from feat/nope: no branch" "$b" T002 --from feat/nope && ! git show-ref --verify --quiet "refs/heads/$C"'
review_ready
echo b >> a.txt; git commit --quiet -am "feat: more a"
check "when --from names a branch whose review is of an older head, then it refuses" \
  'fails_with "--from $P" "$b" T002 --from "$P" && ! git show-ref --verify --quiet "refs/heads/$C"'
review_ready
# The parent stays checked out here; the child is started from another worktree, so it is read by name.
git worktree add --quiet --detach "$TMP/wt" origin/develop; cp -a .specify "$TMP/wt/"; cd "$TMP/wt"
check "when --from names a branch with a ready review, checked out in another worktree, then the new branch starts from its head" \
  '"$b" T002 --from "$P" >/dev/null 2>&1 && [[ "$(git branch --show-current)" == "$C" && "$(git rev-parse HEAD)" == "$(git rev-parse "$P")" ]]'
check "then it records the parent setting and the parent's head" \
  '[[ "$(git config --get "branch.$C.landspec-parent")" == "$P" && "$(cat "$(git rev-parse --git-common-dir)/landspec-review/parent-head-${C//\//__}")" == "$(git rev-parse "$P")" ]]'
cd "$TMP/repo"

exit "$FAIL"
