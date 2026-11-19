#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
I="$SCRIPTS/implement.sh"
TASKS='- [ ] T001 Add search in `src/search.ts` — #1
- [ ] T002 [P] Add filters in `src/filters.ts` — #2
- [ ] T003 Add ranking in `src/rank.ts` (depends on T001) — #3
- [ ] T004 Add export in `src/export.ts` (depends on T002, T003) — #4'
B1=feat/001-t001-a; B2=feat/001-t002-b; B3=feat/001-t003-c; B4=feat/001-t004-d

# setup: a repo with the four tasks on its base, run from a detached HEAD; $W commits on task
# branches without ever checking one out here.
setup() {
  cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/w" "$TMP/c" "$TMP/l"; : > "$GH_CLOSED"; : > "$GH_OPEN"
  new_repo standard; commit_tasks "$TASKS"
  git switch --quiet --detach origin/develop; HEAD0="$(git rev-parse HEAD)"
  git worktree add --quiet --detach "$TMP/w" origin/develop
}
# mk <branch> [<from>]: the branch with one commit of its own, from origin/develop.
mk() { git -C "$TMP/w" switch --quiet -c "$1" "${2:-origin/develop}"; commit_on "$1"; }
commit_on() {
  git -C "$TMP/w" switch --quiet "$1"; echo "$RANDOM" >> "$TMP/w/${1//\//_}.txt"
  git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet -m "feat: $1"; git -C "$TMP/w" switch --quiet --detach
}
# ready <branch> [<findings>]: a recorded ready review of its head, recorded by name from here.
ready() {
  printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n%s\nAssessment: ready\n' \
    "$(git merge-base "refs/heads/$1" "$(bash -c 'source "$0/lib.sh"; base_ref "$1"' "$SCRIPTS" "$1")")" "$(git rev-parse "refs/heads/$1")" "${2:-}" > "$TMP/r.md"
  "$SCRIPTS/review.sh" record --branch "$1" "$TMP/r.md" >/dev/null
}
# Paths in REASON= are git's, resolved: on macOS $TMP is /var/... and git prints /private/var/....
# st [args]: run status, keep its output in $out, and note when HEAD moved.
st() { out="$("$I" status "$@" 2>&1)" || true; [[ "$(git rev-parse HEAD)" == "$HEAD0" ]] || echo moved >> "$TMP/head.moved"; }
state_of() { sed -n "s/^TASK=$1 STATE=\([^ ]*\).*/\1/p" <<<"$out"; }
line_of() { grep "^TASK=$1 " <<<"$out"; }
cfg_set() { sed -i.bak "/^parallel_tasks:/d" .specify/extensions/landspec/landspec-config.yml; [[ -z "$1" ]] || echo "parallel_tasks: $1" >> .specify/extensions/landspec/landspec-config.yml; }
rm -f "$TMP/head.moved"

# ── Dependencies ──
setup
st
check "before anything starts, then START is T001 T002 and T003, T004 wait" \
  'grep -qx "START=T001 T002" <<<"$out" && [[ "$(state_of T003)" == waiting && "$(state_of T004)" == waiting ]]'
check "then each waiting line says which dependency it waits for" \
  'line_of T003 | grep -q " REASON=waits for T001$" && line_of T004 | grep -q " REASON=waits for T002$"'
mk "$B1"; ready "$B1"; st
check "when T001 is reviewed, then it is reviewed, in OPEN, and T003 becomes startable" \
  '[[ "$(state_of T001)" == reviewed && "$(state_of T003)" == startable ]] && grep -qx "OPEN=T001" <<<"$out" && grep -qx "START=T002 T003" <<<"$out"'
check "then T003 stacks on T001: its startable line names T001's branch as PARENT, and T002 (no dependency) has none" \
  'line_of T003 | grep -qF "STATE=startable" && line_of T003 | grep -qF " PARENT=$B1" && line_of T002 | grep -qF " PARENT=-"'
mk "$B2"; ready "$B2"; st
check "when one dependency is reviewed and the other not started, then it waits for the unstarted one" 'line_of T004 | grep -q " REASON=waits for T003$"'
mk "$B3" "$B1"; git config "branch.$B3.landspec-parent" "$B1"; ready "$B3"; st
check "when T002 and T003 are both reviewed and unmerged, then T004 still waits, for one of their merges" \
  '[[ "$(state_of T004)" == waiting ]] && line_of T004 | grep -q " REASON=merge T002 or T003 first$"'
check "then ORDER lists the parent before its child" 'grep -qx "ORDER=T001 T002 T003" <<<"$out"'
echo 2 >> "$GH_CLOSED"; st
check "when T002 is merged, then T004 becomes startable" '[[ "$(state_of T002)" == merged && "$(state_of T004)" == startable ]]'
check "then T004 stacks on its one unmerged dependency, T003" 'line_of T004 | grep -qF " PARENT=$B3"'
echo 3 >> "$GH_CLOSED"; st
check "when every dependency of T004 is merged, then it starts from the base: PARENT=-" \
  '[[ "$(state_of T004)" == startable ]] && line_of T004 | grep -qF " PARENT=-"'

# ── Limits and refusals ──
setup
cfg_set 1; st
check "when parallel_tasks is 1, then START holds one task" 'grep -qx "START=T001" <<<"$out"'
st --running T001
check "when T001 is running and parallel_tasks is 1, then it takes the slot and START is empty" \
  '[[ "$(state_of T001)" == running ]] && grep -qx "START=" <<<"$out"'
for v in 0 abc 17; do
  cfg_set "$v"
  check "when parallel_tasks is $v, then status dies with the exact message" \
    'fails_with "landspec: parallel_tasks must be a number from 1 to 16" "$I" status'
done
cfg_set ""
mk "$B2"; git worktree add --quiet "$TMP/l" "$B2"; git worktree lock "$TMP/l"; st
check "when a task branch is checked out in a locked worktree, then it is running with the worktree named" \
  'line_of T002 | grep -qF "STATE=running" && line_of T002 | grep -qF "REASON=locked worktree $(cd "$TMP/l" && pwd -P)"'
git worktree unlock "$TMP/l"; git worktree remove --force "$TMP/l"
git push --quiet origin "origin/develop:refs/heads/$B4"; git fetch --quiet origin; st
check "when a task's branch is on origin with no local branch, then it is elsewhere" '[[ "$(state_of T004)" == elsewhere ]]'
mkdir -p specs/002-other; printf -- '- [ ] T001 Other in `x` — #9\n' > specs/002-other/tasks.md
check "when a feature's tasks.md is not on origin's base, then status refuses with merge the spec PR first" \
  'fails_with "merge the spec PR first" "$I" 002 status'
rm -rf specs/002-other
check "when gh cannot list the PRs, then status stops with gh's error and prints no state" \
  'gf=0; o="$(GH_FAIL_PR_LIST=1 "$I" status 2>&1)" || gf=$?; ((gf != 0)) && grep -q "cannot list the open pull requests" <<<"$o" && ! grep -q "^START=" <<<"$o"'

# ── The task record ──
setup
mk "$B1"; "$I" mark T001 implemented >/dev/null; st
check "when T001 is marked implemented, then it is implemented, in REVIEW, not in START" \
  '[[ "$(state_of T001)" == implemented ]] && grep -qx "REVIEW=T001" <<<"$out" && ! grep -q "^START=.*T001" <<<"$out"'
rec1() { sed -n "s/^$1=//p" "$(git rev-parse --git-common-dir)/landspec-run/001-demo/T001"; }
ph0="$(rec1 phase)"; h0="$(rec1 head)"; r0="$(rec1 round)"; "$I" mark T001 red >/dev/null; o2="$("$I" mark T001 red 2>&1)" || true; st
check "when T001's tests are red twice after it said done, then red=2, with phase, head and round unchanged, and it is still implemented" \
  '[[ "$o2" == "MARKED=T001 PHASE=red RED=2" && "$(rec1 red)" == 2 && "$(rec1 phase)" == "$ph0" && "$(rec1 head)" == "$h0" && "$(rec1 round)" == "$r0" && "$(state_of T001)" == implemented ]]'
"$I" mark T001 implemented >/dev/null
check "when T001 is then marked implemented, then red= is gone" '[[ -z "$(rec1 red)" ]]'
"$I" mark T001 red >/dev/null; "$I" retry T001 >/dev/null
check "when T001 is red and then retried, then red= is gone" '[[ -z "$(rec1 red)" ]]'
commit_on "$B1"; st
check "when a new commit lands on it, then it is resume" '[[ "$(state_of T001)" == resume ]]'
echo "findings" > "$TMP/rep1.md"; "$I" mark T001 changes "$TMP/rep1.md" >/dev/null; st
check "when T001 is marked changes with a report, then it is fix, in FIX, and the report is kept" \
  '[[ "$(state_of T001)" == fix ]] && grep -qx "FIX=T001" <<<"$out" && [[ "$(cat "$(git rev-parse --git-common-dir)/landspec-run/001-demo/T001.report")" == findings ]]'
"$I" mark T001 changes "$TMP/rep1.md" >/dev/null; "$I" mark T001 changes "$TMP/rep1.md" >/dev/null; st
check "when the third changes is marked, then T001 is failed (review rounds)" \
  'line_of T001 | grep -qF "STATE=failed" && line_of T001 | grep -qF "REASON=review rounds"'
commit_on "$B1"; "$I" mark T001 changes "$TMP/rep1.md" >/dev/null; st
check "when a new commit lifts a review-rounds failure, then the next changes starts the rounds again (fix, not failed)" '[[ "$(state_of T001)" == fix ]]'
mk "$B2"; "$I" fail T002 "tests red" >/dev/null; st
check "when T002 is failed, then it is failed and T004 never startable" \
  '[[ "$(state_of T002)" == failed && "$(state_of T004)" != startable ]] && line_of T002 | grep -qF "REASON=tests red"'
check "then mark and fail are logged with the task's branch named, whatever is checked out" \
  'ev="$(git rev-parse --git-common-dir)/landspec-events"; grep -qE " mark task=T001 phase=implemented round=[0-9]+ branch=$B1$" "$ev" && grep -qE " fail task=T002 branch=$B2$" "$ev"'
commit_on "$B2"; st
check "when a new commit lands on a failed task, then it is lifted" '[[ "$(state_of T002)" == resume ]]'
"$I" mark T002 implemented >/dev/null; st
check "then marking that new work implemented does not bring the failure back" '[[ "$(state_of T002)" == implemented ]]'
"$I" fail T002 "tests red" >/dev/null; "$I" retry T002 >/dev/null; st
check "when a failed task is retried, then it is lifted (back to implemented)" '[[ "$(state_of T002)" == implemented ]]'
"$I" fail T004 "no idea" >/dev/null; mk "$B4"; commit_on "$B4"; st
check "when a task failed before its branch existed, then it stays failed until retry" '[[ "$(state_of T004)" == failed ]]'
"$I" retry T004 >/dev/null; st
check "then retry lifts it" '[[ "$(state_of T004)" == resume ]]'

# ── Moved on GitHub ──
setup
mk "$B1"; git push --quiet origin "$B1"
git -C "$TMP/w" switch --quiet --detach "$B1"; echo theirs > "$TMP/w/theirs.txt"; git -C "$TMP/w" add -A
git -C "$TMP/w" commit --quiet -m theirs; git -C "$TMP/w" push --quiet origin "HEAD:refs/heads/$B1"; git -C "$TMP/w" switch --quiet --detach origin/develop
st
check "when someone pushed to a task branch checked out nowhere, then status fast-forwards it" \
  '[[ "$(git rev-parse "refs/heads/$B1")" == "$(git rev-parse "refs/remotes/origin/$B1")" && "$(state_of T001)" == resume ]]'
mk "$B2"; git push --quiet origin "$B2"; git worktree add --quiet "$TMP/c" "$B2"; before="$(git rev-parse "refs/heads/$B2")"
git -C "$TMP/w" switch --quiet --detach "$B2"; echo theirs > "$TMP/w/t2.txt"; git -C "$TMP/w" add -A
git -C "$TMP/w" commit --quiet -m theirs; git -C "$TMP/w" push --quiet origin "HEAD:refs/heads/$B2"; git -C "$TMP/w" switch --quiet --detach origin/develop
st
check "when the same happens to a branch checked out in a worktree, then it is not moved and is elsewhere with the path" \
  '[[ "$(git rev-parse "refs/heads/$B2")" == "$before" ]] && line_of T002 | grep -qF "STATE=elsewhere" && line_of T002 | grep -qF "REASON=checked out in $(cd "$TMP/c" && pwd -P)"'
git worktree remove --force "$TMP/c"; commit_on "$B2"; st
check "when the local branch and origin diverged, then it is elsewhere, diverged from origin" \
  'line_of T002 | grep -qF "STATE=elsewhere" && line_of T002 | grep -qF "REASON=diverged from origin"'

# ── Draft PRs on the base ──
setup
mk "$B1"; ready "$B1"
printf '12\t%s\t%s\tdevelop\ttrue\n' "$B1" "$(git rev-parse "refs/heads/$B1")" > "$GH_OPEN"; st
check "when a draft PR on the base has a valid review, then the task is reviewed and in OPEN" \
  '[[ "$(state_of T001)" == reviewed ]] && grep -qx "OPEN=T001" <<<"$out" && line_of T001 | grep -qF "PR=12"'
git config "branch.$B1.landspec-parent" feat/001-t009-gone; st
check "when that PR still has landspec-parent set (retargeted by GitHub), then it is waiting, restack pending, in no list" \
  'line_of T001 | grep -qF "STATE=waiting" && line_of T001 | grep -qF "REASON=restack pending" && grep -qx "OPEN=" <<<"$out" && grep -qx "START=T002" <<<"$out"'
git config --unset "branch.$B1.landspec-parent"; "$I" mark T001 pr >/dev/null
printf '12\t%s\t%s\tdevelop\tfalse\n' "$B1" "$(git rev-parse "refs/heads/$B1")" > "$GH_OPEN"; st
check "when the PR is ready on the base and marked pr, then the task is pr" '[[ "$(state_of T001)" == pr ]]'
echo "- a.ts:3 thread=PRRT_1 nit" > "$TMP/cop.md"; "$I" mark T001 changes "$TMP/cop.md" >/dev/null; st
check "when that task (a ready record, its PR open) is marked changes with a Copilot report on the same head, then it is fix, in FIX" \
  '[[ "$(state_of T001)" == fix ]] && grep -qx "FIX=T001" <<<"$out"'
commit_on "$B1"; st
check "when a later commit lands on it, then it is listed as before (resume)" '[[ "$(state_of T001)" == resume ]]'
ready "$B1"; "$I" mark T001 pr >/dev/null
printf '12\t%s\t%s\tdevelop\tfalse\n' "$B1" "$(git rev-parse "refs/heads/$B1")" > "$GH_OPEN"
mk "$B3" "$B1"; git config "branch.$B3.landspec-parent" "$B1"; ready "$B3"; "$I" mark T003 pr >/dev/null
printf '12\t%s\t%s\tdevelop\tfalse\n13\t%s\t%s\t%s\ttrue\n' "$B1" "$(git rev-parse "refs/heads/$B1")" "$B3" "$(git rev-parse "refs/heads/$B3")" "$B1" > "$GH_OPEN"; st
check "when a stacked draft PR into its parent is marked pr, then the task is pr, not in OPEN" \
  '[[ "$(state_of T003)" == pr ]] && ! grep -q "^OPEN=.*T003" <<<"$out"'

# ── Spec 004 T005: restack moves stacked branches; stack stacks one task on another ──
# rs_setup: a lite repo (base main) with T001, T002 (depends on T001), T003 (depends on T002).
rs_setup() {
  cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/repo-001-run" "$TMP/w" "$TMP/c"; : > "$GH_CLOSED"; : > "$GH_OPEN"; : > "$GH_ALL"; : > "$GH_LOG"
  new_repo lite; commit_tasks '- [ ] T001 Add search in `a` — #1
- [ ] T002 Add filters in `b` (depends on T001) — #2
- [ ] T003 Add ranking in `c` (depends on T002) — #3'
  DEV="$(git rev-parse HEAD)"; HEAD0="$DEV"; git worktree add --quiet --detach "$TMP/w" origin/main
}
# mkb <branch> <from> <file> [<parent branch>]: a pushed task branch with one file of its own.
mkb() {
  git -C "$TMP/w" switch --quiet -c "$1" "$2"; printf 'l1\nl2\nl3\nl4\nl5\n' > "$TMP/w/$3"
  git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet -m "feat: $1"; git -C "$TMP/w" push --quiet origin "$1"; git -C "$TMP/w" switch --quiet --detach
  if [[ -n "${4:-}" ]]; then
    git config "branch.$1.landspec-parent" "$4"; mkdir -p .git/landspec-review
    git rev-parse "refs/heads/$4" > ".git/landspec-review/parent-head-${1//\//__}"
  fi
}
# edit <branch> <file> <sed>: a pushed commit editing that file.
edit() {
  git -C "$TMP/w" switch --quiet "$1"; sed -i.bak "$3" "$TMP/w/$2"; rm -f "$TMP/w/$2.bak"
  git -C "$TMP/w" commit --quiet -am "fix: $1"; git -C "$TMP/w" push --quiet origin "$1"; git -C "$TMP/w" switch --quiet --detach
}
# prs: lines "<n> <branch> <base> <draft> <state>" on stdin become the fake gh's PR lists.
prs() {
  : > "$GH_ALL"; : > "$GH_OPEN"
  while read -r n b bs d s; do
    h="$(git rev-parse "refs/remotes/origin/$b")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$b" "$h" "$bs" "$d" "$s" >> "$GH_ALL"
    if [[ "$s" == OPEN ]]; then printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$b" "$h" "$bs" "$d" >> "$GH_OPEN"; fi
  done
}
squash() { # squash <branch> <issue>: squash-merge it into main on origin, as GitHub does
  git -C "$TMP/w" switch --quiet --detach origin/main; git -C "$TMP/w" merge --quiet --squash "refs/heads/$1" >/dev/null
  git -C "$TMP/w" commit --quiet -m "squash $1"; git -C "$TMP/w" push --quiet origin HEAD:refs/heads/main; git -C "$TMP/w" switch --quiet --detach
  git fetch --quiet origin; echo "$2" >> "$GH_CLOSED"
}
own() { git diff --name-only "$(git merge-base "refs/heads/$1" "$2")" "refs/heads/$1" | tr '\n' ' ' | sed 's/ $//'; } # own <branch> <against>
rs() { out="$("$I" restack 2>&1)" || true; }
run_ok() { # the run's worktree is detached and every task branch can still be checked out elsewhere
  [[ -z "$(git -C "$TMP/repo-001-run" branch --show-current)" ]] && git worktree add --quiet "$TMP/c" "$1" && git worktree remove --force "$TMP/c" \
    && [[ "$(git rev-parse HEAD)" == "$DEV" && "$(git branch --show-current)" == main ]]
}
B1=feat/001-t001-add-search-in-a; B2=feat/001-t002-add-filters-in-b; B3=feat/001-t003-add-ranking-in-c

rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; ready "$B2"
printf '11 %s main false OPEN\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
squash "$B1" 1
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs; : > "$GH_LOG"; rs
check "when T001 is squash-merged, then restack moves T002 onto main, keeps its review and marks its PR ready" \
  'grep -qx "RESTACKED=T002 REVIEW=kept" <<<"$out" && [[ "$(own "$B2" origin/main)" == b ]] && ! git config --get "branch.$B2.landspec-parent" \
   && grep -q "^pr edit 12 --base main" "$GH_LOG" && grep -q "^pr ready 12$" "$GH_LOG"'
check "then the run's worktree is detached, the branch can be checked out, the developer's checkout is unchanged" 'run_ok "$B2"'
printf '11 %s main false MERGED\n12 %s main false OPEN\n' "$B1" "$B2" | prs; rs # as GitHub shows it after the edit
check "when restack runs again, then it prints nothing" '[[ -z "$out" ]]'

rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; ready "$B2"
printf '11 %s main false OPEN\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
edit "$B1" a 's/l1/L1/'; printf '11 %s main false OPEN\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs; : > "$GH_LOG"; rs
check "when the parent moved (a fix round) and is still open, then the child is moved onto its new head with no pr ready" \
  'grep -qx "RESTACKED=T002 REVIEW=kept" <<<"$out" && git merge-base --is-ancestor "refs/heads/$B1" "refs/heads/$B2" && [[ "$(own "$B2" "refs/heads/$B1")" == b ]] \
   && ! grep -q "^pr ready 12$" "$GH_LOG" && [[ "$(cat ".git/landspec-review/parent-head-${B2//\//__}")" == "$(git rev-parse "refs/heads/$B1")" ]] && run_ok "$B2"'
squash "$B1" 1; printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs; rs
check "when that fixed parent is then squash-merged, then the child holds only its own file, with no conflict" \
  'grep -qx "RESTACKED=T002 REVIEW=kept" <<<"$out" && [[ "$(own "$B2" origin/main)" == b ]]'

# Chain T001 -> T002 -> T003, T001 merged: one restack moves both.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; mkb "$B3" "$B2" c "$B2"
squash "$B1" 1; printf '11 %s main false MERGED\n' "$B1" | prs; : > "$GH_LOG"; rs
check "in a chain with T001 merged, then one restack leaves T003 against T002 holding only its own file" \
  'grep -qx "RESTACKED=T002 REVIEW=none" <<<"$out" && grep -qx "RESTACKED=T003 REVIEW=none" <<<"$out" && [[ "$(own "$B3" "refs/heads/$B2")" == c && "$(own "$B2" origin/main)" == b ]]'
check "then a task with no PR is moved with no gh call but the PR list" '! grep -qE "^pr (edit|ready)" "$GH_LOG"'

# The review needs redoing when the move changes the diff (here, its context lines), and the PR stays a draft.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; edit "$B2" a 's/l3/X3/'; ready "$B2"
edit "$B1" a 's/l1/Y1/'; squash "$B1" 1
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs; : > "$GH_LOG"; rs; rsout="$out"; st
check "then restack said REVIEW=needed" 'grep -qx "RESTACKED=T002 REVIEW=needed" <<<"$rsout"'
check "when the move changes the child's diff, then REVIEW=needed, no pr ready, and the task is implemented" \
  '[[ "$(state_of T002)" == implemented ]] && ! grep -q "^pr ready 12$" "$GH_LOG" && grep -q "^pr edit 12 --base main" "$GH_LOG"'

# A child that touches the parent's fixed lines conflicts and keeps its head.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; edit "$B2" a 's/l1/C1/'; edit "$B1" a 's/l1/P1/'
printf '11 %s main false OPEN\n' "$B1" | prs; h="$(git rev-parse "refs/heads/$B2")"; rs
check "when the child touches the parent's fixed lines, then RESTACK_CONFLICT and its head is kept" \
  'grep -qx "RESTACK_CONFLICT=T002" <<<"$out" && [[ "$(git rev-parse "refs/heads/$B2")" == "$h" ]] && run_ok "$B2"'

# Skips: checked out, origin moved, local commits not on origin.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; squash "$B1" 1
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
git worktree add --quiet "$TMP/c" "$B2"; rs
check "when the child is checked out in a worktree, then it is skipped, saying so" 'grep -q "^RESTACK_SKIPPED=T002 (checked out in " <<<"$out"'
git worktree remove --force "$TMP/c"
edit "$B2" b 's/l2/O2/'; git -C "$TMP/w" push --quiet origin ":refs/heads/__x" 2>/dev/null || true
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
git -C "$TMP/w" switch --quiet --detach "$B2"; echo z > "$TMP/w/z"; git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet -m z
git -C "$TMP/w" push --quiet origin "HEAD:refs/heads/$B2"; git -C "$TMP/w" switch --quiet --detach; git fetch --quiet origin
git update-ref "refs/heads/$B2" "refs/remotes/origin/$B2"; rs
check "when origin's head differs from the PR's head, then it is skipped (origin moved)" 'grep -qx "RESTACK_SKIPPED=T002 (origin moved)" <<<"$out"'
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
git -C "$TMP/w" switch --quiet "$B2"; echo y > "$TMP/w/y"; git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet -m y; git -C "$TMP/w" switch --quiet --detach; rs
check "when it has local commits not on origin, then it is skipped, saying so" 'grep -qx "RESTACK_SKIPPED=T002 (local commits not on origin)" <<<"$out"'

# A failed gh pr edit after the push: a second restack finishes it.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; ready "$B2"; squash "$B1" 1
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
out="$(GH_FAIL_EDIT=1 "$I" restack 2>&1)" && ebrc=0 || ebrc=$?
check "when gh pr edit fails after the move, then restack stops naming the PR" '[[ $ebrc != 0 ]] && grep -q "could not move PR #12 onto main" <<<"$out" && run_ok "$B2"'
: > "$GH_LOG"; rs
check "then a second restack moves the PR onto main and marks it ready" \
  'grep -qx "RETARGETED=T002" <<<"$out" && grep -q "^pr edit 12 --base main" "$GH_LOG" && grep -q "^pr ready 12$" "$GH_LOG"'

# A PR stacked in another clone (no setting here) on a still-open parent is left alone.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b
printf '11 %s main false OPEN\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs; : > "$GH_LOG"; rs
check "when a PR is stacked on an open parent in another clone, then restack leaves it" '[[ -z "$out" ]] && ! grep -qE "^pr (edit|ready)" "$GH_LOG"'

# A local branch behind origin is not moved, so origin keeps the commits this clone lacks.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; old2="$(git rev-parse "refs/heads/$B2")"; edit "$B2" b 's/l2/N2/'
git update-ref "refs/heads/$B2" "$old2"; squash "$B1" 1; 
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
out="$("$I" restack --running T002 2>&1)" || true
check "when T002 is running, then restack skips it, saying so" 'grep -qx "RESTACK_SKIPPED=T002 (running)" <<<"$out"'
rs
check "when the local branch is behind origin, then it is fast-forwarded first and the move keeps origin's commit" \
  'grep -qx "RESTACKED=T002 REVIEW=none" <<<"$out" && git merge-base --is-ancestor origin/main "refs/heads/$B2" && grep -q N2 <(git show "refs/heads/$B2:b") \
   && [[ "$(git rev-parse "refs/remotes/origin/$B2")" == "$(git rev-parse "refs/heads/$B2")" ]]'

# stack has the same guards.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" origin/main b; git worktree add --quiet "$TMP/c" "$B2"
check "when stack's branch is checked out in a worktree, then stack refuses and leaves it" \
  'h="$(git rev-parse "refs/heads/$B2")"; fails_with "cannot be stacked now: checked out in" "$I" stack T002 T001 && [[ "$(git rev-parse "refs/heads/$B2")" == "$h" ]]'
git worktree remove --force "$TMP/c"

# A move keeps the record's state: implemented, fix and failed stay so, and none is in START.
for ph in implemented changes failed; do
  rs_setup
  mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; echo r > "$TMP/rep.md"
  case "$ph" in failed) "$I" fail T002 "tests red" >/dev/null ;; *) "$I" mark T002 "$ph" "$TMP/rep.md" >/dev/null ;; esac
  squash "$B1" 1; printf '11 %s main false MERGED\n' "$B1" | prs; rs; rsout="$out"; st
  want="$ph"; [[ "$ph" != changes ]] || want=fix
  check "when a $want stacked task is moved, then it is still $want and not in START" \
    'grep -q "^RESTACKED=T002" <<<"$rsout" && [[ "$(state_of T002)" == "$want" ]] && ! grep -q "^START=.*T002" <<<"$out"'
done

# pr ready refused: the task stays reviewed, a draft on the base, in OPEN.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" "$B1" b "$B1"; ready "$B2"; squash "$B1" 1
printf '11 %s main false MERGED\n12 %s %s true OPEN\n' "$B1" "$B2" "$B1" | prs
out="$(GH_FAIL_READY=1 "$I" restack 2>&1)" || true
check "when gh pr ready fails, then RESTACK_NOT_READY" 'grep -qx "RESTACK_NOT_READY=T002" <<<"$out"'
printf '11 %s main false MERGED\n12 %s main true OPEN\n' "$B1" "$B2" | prs; st
check "then the task is reviewed, in OPEN" '[[ "$(state_of T002)" == reviewed ]] && grep -q "^OPEN=.*T002" <<<"$out"'

# stack: T003 (unstacked, from main) onto T002.
rs_setup
mkb "$B1" origin/main a; mkb "$B2" origin/main b; mkb "$B3" origin/main c
out="$("$I" stack T003 T002 2>&1)" || true
check "when stack T003 T002 runs, then T003's diff against T002 holds only its own file and T002 is its parent" \
  'grep -q "^RESTACKED=T003" <<<"$out" && [[ "$(own "$B3" "refs/heads/$B2")" == c && "$(git config --get "branch.$B3.landspec-parent")" == "$B2" ]] && run_ok "$B3"'
check "then a second stack refuses" 'fails_with "already stacked" "$I" stack T003 T001'
rs_setup; mkb "$B1" origin/main a; mkb "$B2" origin/main b; mkb "$B3" origin/main c
printf '13 %s main false OPEN\n' "$B3" | prs; : > "$GH_LOG"; out="$("$I" stack T003 T002 2>&1)" || true
check "when stack moves a ready PR onto a task branch, then it turns it back into a draft" \
  'grep -q "^RESTACKED=T003" <<<"$out" && grep -q "^pr edit 13 --base $B2" "$GH_LOG" && grep -q "^pr ready 13 --undo" "$GH_LOG"'
rs_setup; mkb "$B1" origin/main a; mkb "$B2" origin/main b; mkb "$B3" origin/main c
printf '13 %s main true OPEN\n' "$B3" | prs; : > "$GH_LOG"; out="$(GH_PR_DRAFT=true "$I" stack T003 T002 2>&1)" || true
check "then a PR that is already a draft is left as it is" 'grep -q "^RESTACKED=T003" <<<"$out" && ! grep -q "^pr ready 13" "$GH_LOG"'

# ── Spec 004 T007: the whole-feature check copy, its rounds, and the feature review ──
cc() { out="$("$I" check-copy "$@" 2>&1)" || true; }
fname() { basename "$(ls -d specs/*/ | head -1)"; }
CW() { echo "$(cd "$TMP" && pwd -P)/repo-001-check"; } # as git prints it (macOS: /private/var)
# frep <lines>: a feature review of the current check ref, with those item lines.
frep() {
  c="$(git rev-parse "refs/landspec/check/$(fname)")"
  printf '%b\nCopy: none (test)\nReviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$1" "$(git merge-base "$c" origin/main)" "$c" > "$TMP/f.md"
  "$SCRIPTS/review.sh" record --feature "$TMP/f.md" 2>&1
}
rnd() { sed -n 's/^round=//p' ".git/landspec-review/feature-$(fname)-round" 2>/dev/null; }

rs_setup
mkb "$B1" origin/main a; mkb "$B2" origin/main b; mkb "$B3" origin/main c; cc
check "when three task branches merge cleanly, then check-copy prints CHECK= and the ref holds all three files" \
  'grep -q "^CHECK=$(CW) ROUND=1$" <<<"$out" && for f in a b c; do git cat-file -e "refs/landspec/check/$(fname):$f" || exit 1; done \
   && [[ "$(git rev-parse HEAD)" == "$DEV" && "$(git branch --show-current)" == main && -z "$(git status --porcelain --untracked-files=no)" ]]'
cc
check "when check-copy runs again on the same heads with no result, then UNCHANGED=1 and round stays 1" '[[ "$out" == UNCHANGED=1 && "$(rnd)" == 1 ]]'
cc --remove
check "when check-copy --remove runs, then the copy and the ref are gone" '[[ -z "$out" && ! -d "$(CW)" ]] && ! git show-ref --quiet "refs/landspec/check/$(fname)"'
cc --remove
check "then a second --remove is silent" '[[ -z "$out" ]]'
"$I" check-result red >/dev/null; cc
check "when the same heads as the last red attempt are checked, then UNCHANGED= and no copy is made" '[[ "$out" == UNCHANGED=1 && ! -d "$(CW)" ]]'
edit "$B3" c 's/l1/F1/'; cc
check "when a fix commit makes new heads, then round goes up" 'grep -q "^CHECK=.* ROUND=2$" <<<"$out" && [[ "$(rnd)" == 2 ]]'
"$I" check-result red >/dev/null; edit "$B3" c 's/l2/F2/'; cc; "$I" check-result green >/dev/null
out="$(frep '- met: FR-001 — a\n- not verifiable: SC-001 — needs a timed run')"
check "when a feature review has only met and not verifiable lines, then it records ready" 'grep -qx "REVIEW=ready" <<<"$out"'
check "then a ready review after a green run resets the round counter" '[[ -z "$(rnd)" ]]'
edit "$B3" c 's/l3/F3/'; cc; "$I" check-result red >/dev/null
out="$(frep '- met: FR-001 — a')"
check "when a ready feature review follows a red run, then the round counter is kept" 'grep -qx "REVIEW=ready" <<<"$out" && [[ "$(rnd)" == 1 ]]'
out="$(frep '- met: FR-001 — a\n- not met: FR-002 — nothing does it')"
check "when a feature review has a not met line, then it records changes needed, whatever its last line says" 'grep -qx "REVIEW=changes needed" <<<"$out"'
check "when record --feature is given with --plan, then it is refused" 'fails_with "a feature review is recorded alone" "$SCRIPTS/review.sh" record --feature --plan "$TMP/f.md"'
echo "feature_rounds: 2" >> .specify/extensions/landspec/landspec-config.yml
edit "$B3" c 's/l4/F4/'; cc; "$I" check-result red >/dev/null; cc --remove; edit "$B3" c 's/l5/F5/'; cc
check "when feature_rounds is 2, then the third attempt on new heads prints ROUNDS_EXHAUSTED=2 and makes no copy" '[[ "$out" == ROUNDS_EXHAUSTED=2 && ! -d "$(CW)" ]]'

rs_setup
mkb "$B1" origin/main a; mkb "$B2" origin/main b; git branch -D --quiet "$B2"; cc
check "when an unmerged task's branch is not in this clone, then check-copy stops naming it and makes no copy" \
  'grep -q "T002 has no branch in this clone" <<<"$out" && ! grep -q "^CHECK=" <<<"$out" && [[ ! -d "$(CW)" ]]'

# A conflict: two unstacked branches edit the same line.
rs_setup
git -C "$TMP/w" switch --quiet --detach origin/main; printf 'l1\nl2\nl3\n' > "$TMP/w/s"; git -C "$TMP/w" add s; git -C "$TMP/w" commit --quiet -m s
git -C "$TMP/w" push --quiet origin HEAD:refs/heads/main; git -C "$TMP/w" switch --quiet --detach; git fetch --quiet origin
mkb "$B1" origin/main a; edit "$B1" s 's/l1/A1/'; mkb "$B2" origin/main b; edit "$B2" s 's/l1/B1/'; cc
check "when two unstacked branches edit the same line, then CONFLICT names the later, the earlier and the file, with no merge left in progress" \
  '[[ "$out" == "CONFLICT=T002 WITH=T001 FILES=s" ]] && ! git -C "$(CW)" rev-parse -q --verify MERGE_HEAD >/dev/null'
check "then the conflict counts as an attempt" '[[ "$(rnd)" == 1 ]] && grep -qx "outcome=conflict" ".git/landspec-review/feature-$(fname)-round"'
edit "$B2" s 's/B1/l1/; s/l3/B3/'; out="$("$I" stack T002 T001 2>&1)" || true; cc
check "after a fix commit on the later one and stack T002 T001, then check-copy prints CHECK=" 'grep -q "^CHECK=.* ROUND=2$" <<<"$out"'
cc --remove

# ── Spec 004 T009: the release, one step at a time, read from git and GitHub ──
rp() { out="$("$I" release-plan 2>&1)" || true; }
# on_main <msg> <file> <content>: a commit on origin's main, printing its sha.
on_main() {
  git -C "$TMP/w" switch --quiet --detach origin/main; printf '%b' "$3" > "$TMP/w/$2"; git -C "$TMP/w" add "$2"
  git -C "$TMP/w" commit --quiet -m "$1"; git -C "$TMP/w" push --quiet origin HEAD:refs/heads/main; git -C "$TMP/w" rev-parse HEAD; git -C "$TMP/w" switch --quiet --detach
  git fetch --quiet origin
}
rl_setup() {
  rs_setup; : > "$GH_REL"; : > "$GH_RELEASES"
  on_main version package.json '{\n  "name": "x",\n  "version": "1.4.2"\n}\n' >/dev/null
  on_main version extension.yml 'extension:\n  id: x\n  version: "1.4.2"\nrequires:\n  speckit_version: ">=1.0"\n' >/dev/null
  git switch --quiet --detach origin/main; git branch --quiet -f main origin/main; git switch --quiet main; DEV="$(git rev-parse HEAD)"; HEAD0="$DEV"
  printf 'version_files: package.json, extension.yml\nrelease_notes: docs/releases\n' >> .specify/extensions/landspec/landspec-config.yml
  n=10
  for b in "$B1" "$B2" "$B3"; do
    n=$((n + 1)); mkb "$b" origin/main "f$n"; squash "$b" $((n - 10))
    printf '%s\tfeat: %s\t%s\tMERGED\t%s\t2026-11-0%sT10:00:00Z\n' "$n" "$b" "$b" "$(git rev-parse origin/main)" $((n - 10)) >> "$GH_REL"
  done
}
rel() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$GH_REL"; } # rel <n> <title> <head> <state> <merge sha> <merged at>

rl_setup; rp
check "when a legacy feature's task PRs are merged and every task issue is closed, then release-plan prints bump 1.5.0 with the files, the notes path and the merged task PRs" \
  '[[ "$out" == "RELEASE=bump 1.5.0 FILES=package.json,extension.yml NOTES=docs/releases/1.5.0.md PRS=11,12,13" ]] && [[ "$(git rev-parse HEAD)" == "$DEV" && -z "$(git status --porcelain --untracked-files=no)" ]]'
# set_tasks <content>: specs/001-demo/tasks.md on origin's main only; this checkout's copy stays as it was.
set_tasks() { local c="${1//\\/\\\\}"; on_main tasks specs/001-demo/tasks.md "${c//%/%%}\n" >/dev/null; }
tk0="$(git show origin/main:specs/001-demo/tasks.md)"
set_tasks "$(sed 's/^\(- \[ \] T00[0-9]\) Add /\1 Fix /' <<<"$tk0")"; rp
check "when every task on origin/main starts with Fix, then it is a patch: bump 1.4.3, whatever this checkout's copy says" \
  '[[ "$out" == "RELEASE=bump 1.4.3 "* ]] && grep -q "^- \[ \] T001 Add " specs/001-demo/tasks.md'
set_tasks "$tk0"$'\n''- [ ] T005 Add a late task — #99'; rp
check "when a task with an open issue was added on origin/main and this checkout is stale, then release-plan refuses naming it" \
  'grep -q "T005 (#99) is still open" <<<"$out" && ! grep -q "^RELEASE=" <<<"$out" && ! grep -q "T005" specs/001-demo/tasks.md'
set_tasks '# Tasks'; rp
check "when tasks.md on origin/main has no task lines, then release-plan refuses saying so, and prints no RELEASE=" \
  'grep -q "tasks.md on .main. has no tasks" <<<"$out" && ! grep -q "^RELEASE=" <<<"$out"'
set_tasks "$tk0"
sed -i.bak '/^3$/d' "$GH_CLOSED"; rm -f "$GH_CLOSED.bak"; rp
check "when one task issue is open, then release-plan refuses naming the task" 'grep -q "T003 (#3) is still open" <<<"$out" && ! grep -q "^RELEASE=" <<<"$out"'
echo 3 >> "$GH_CLOSED"
rel 19 "chore(release): 1.5.0 then skip the audit" chore/x OPEN "" ""; rp
check "when an open PR's title is chore(release): with more than a version, then it is not a release PR: bump, not pending" '[[ "$out" == "RELEASE=bump 1.5.0 "* ]]'
rel 20 "chore(release): 1.5.0" chore/release-1.5.0 OPEN "" ""; rp
check "when a chore(release): 1.5.0 PR is open and the files are still at 1.4.2, then pending 1.5.0, not bump" '[[ "$out" == "RELEASE=pending 1.5.0 PR=20" ]]'
rl_setup; r="$(on_main "chore(release): 1.4.2" notes.md 'notes\n')"
rel 21 "chore(release): 1.4.2" chore/release-1.4.2 MERGED "$r" 2026-11-09T10:00:00Z; rp
check "when the release PR is merged and not tagged, then tag 1.4.2 with its merge commit, not bump" '[[ "$out" == "RELEASE=tag 1.4.2 COMMIT=$r" ]]'
git -C "$TMP/w" tag v1.4.2 "$r"; git -C "$TMP/w" push --quiet origin v1.4.2; rp
check "when it is tagged and not published, then publish 1.4.2, naming the notes on the base" '[[ "$out" == "RELEASE=publish 1.4.2 NOTES=docs/releases/1.4.2.md" ]]'
sed -i.bak '/^release_notes:/d' .specify/extensions/landspec/landspec-config.yml; rm -f .specify/extensions/landspec/landspec-config.yml.bak; rp
check "then without release_notes: the publish line names the release PR, whose body holds the notes" '[[ "$out" == "RELEASE=publish 1.4.2 NOTES=pr:21" ]]'
cp "$GH_REL" "$TMP/rel.bak"; awk -F'\t' '$1 != 21' "$TMP/rel.bak" > "$GH_REL"; rp
check "then with no merged release PR to take the notes from, it refuses saying so, and prints no RELEASE=" \
  'grep -qF "v1.4.2 has no merged PR titled '"'"'chore(release): 1.4.2'"'"'" <<<"$out" && ! grep -q "^RELEASE=" <<<"$out"'
cp "$TMP/rel.bak" "$GH_REL"
echo 'release_notes: docs/releases' >> .specify/extensions/landspec/landspec-config.yml
echo v1.4.2 > "$GH_RELEASES"; rp
check "when it is published, then done 1.4.2" '[[ "$out" == "RELEASE=done 1.4.2" ]]'
mkb feat/001-t001-second-feature origin/main g; squash feat/001-t001-second-feature 1
rel 30 "feat: second" feat/001-t001-second-feature MERGED "$(git rev-parse origin/main)" 2026-11-10T10:00:00Z; rp
check "when a second feature is merged after v1.4.2 was published, then bump 1.5.0, not done" '[[ "$out" == "RELEASE=bump 1.5.0 "* ]]'
sed -i.bak '/^version_files:/d' .specify/extensions/landspec/landspec-config.yml; rm -f .specify/extensions/landspec/landspec-config.yml.bak; rp
check "when version_files: is not set, then RELEASE=none" '[[ "$out" == "RELEASE=none (no version_files:)" ]]'
echo 'version_files: package.json, extension.yml' >> .specify/extensions/landspec/landspec-config.yml
out="$("$I" release-bump 1.5.0 2>&1)" || true
check "when release-bump 1.5.0 runs, then only the version line of each file changes" \
  '[[ "$out" == BUMPED=1.5.0 && "$(git diff --numstat -- package.json extension.yml)" == $'"'"'1\t1\textension.yml\n1\t1\tpackage.json'"'"' ]] \
   && grep -qx "  \"version\": \"1.5.0\"" package.json && grep -qx "  version: \"1.5.0\"" extension.yml && grep -qF "speckit_version: \">=1.0\"" extension.yml'
git checkout --quiet -- package.json extension.yml
printf '  "engines": {\n    "version": "9.9.9"\n  }\n' >> package.json; out="$("$I" release-bump 1.5.0 2>&1)" || true
check "when a version file has a second, nested version line, then release-bump changes only the first" \
  '[[ "$out" == BUMPED=1.5.0 ]] && grep -qx "  \"version\": \"1.5.0\"" package.json && grep -qx "    \"version\": \"9.9.9\"" package.json'
git checkout --quiet -- package.json extension.yml; echo plain > notes.txt
sed -i.bak 's/^version_files:.*/version_files: package.json, notes.txt/' .specify/extensions/landspec/landspec-config.yml; rm -f .specify/extensions/landspec/landspec-config.yml.bak
check "when a listed file has no version line, then release-bump refuses and changes nothing" \
  'fails_with "notes.txt has no version line" "$I" release-bump 1.5.0 && [[ -z "$(git diff -- package.json)" ]]'
rm -f notes.txt

# ── Spec 008 T010: the release is keyed on the feature PR, and no issue is read ──
# fp_setup <title> <state>: a feature with no task issues, its feature PR #40 (feat/001-demo) in that state,
# beside a task PR of the old flow, another feature's PR and a fix PR, all merged.
fp_setup() {
  rs_setup; : > "$GH_REL"; : > "$GH_RELEASES"
  on_main version package.json '{\n  "name": "x",\n  "version": "1.4.2"\n}\n' >/dev/null
  on_main tasks specs/001-demo/tasks.md '- [ ] T001 Add search in `a`\n- [ ] T002 Add filters in `b` (depends on T001)\n' >/dev/null
  git switch --quiet --detach origin/main; git branch --quiet -f main origin/main; git switch --quiet main
  echo 'version_files: package.json' >> .specify/extensions/landspec/landspec-config.yml
  mkb feat/001-demo origin/main a; squash feat/001-demo 0
  mc="$(git rev-parse origin/main)"; [[ "$2" == MERGED ]] || mc=""
  rel 40 "$1" feat/001-demo "$2" "$mc" "${mc:+2026-11-12T10:00:00Z}"
  rel 41 "feat: a task of the old flow" feat/001-t001-add-search MERGED "$(git rev-parse origin/main^)" 2026-11-11T10:00:00Z
  rel 42 "feat: another feature" feat/002-other MERGED "$(git rev-parse origin/main^)" 2026-11-11T11:00:00Z
  rel 43 "fix: a typo" fix/typo MERGED "$(git rev-parse origin/main^)" 2026-11-11T12:00:00Z
  : > "$GH_LOG"
}
fp_setup "feat: one PR per feature" MERGED; rp
check "when the feature PR is merged, then release-plan prints bump 1.5.0 with PRS= that PR alone, and gh reads no issue" \
  '[[ "$out" == "RELEASE=bump 1.5.0 FILES=package.json NOTES=- PRS=40" ]] && ! grep -qE "^(issue|api graphql)" "$GH_LOG"'
fp_setup "fix(search): one PR per feature" MERGED; rp
check "when the feature PR's title starts with fix, then it is a patch: bump 1.4.3" '[[ "$out" == "RELEASE=bump 1.4.3 FILES=package.json NOTES=- PRS=40" ]]'
fp_setup "feat: one PR per feature" OPEN; rp
check "when the feature PR is still open, then no bump: release-plan says the feature PR #40 is not merged yet" \
  'grep -qF "the feature PR #40 of 001-demo is not merged yet" <<<"$out" && ! grep -q "^RELEASE=" <<<"$out" && ! grep -qE "^(issue|api graphql)" "$GH_LOG"'

# ── Spec 004 T012: with every task merged, the whole-feature check runs on the base, once per base commit ──
# fbase <from> [<item line>]: a feature review of the check ref, Reviewed: <from>..<check ref> (ready unless a not met line).
fbase() {
  printf -- '%s\nCopy: none (test)\nReviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "${2:-- met: FR-001 — a}" "$1" "$(git rev-parse "refs/landspec/check/$(fname)")" > "$TMP/f.md"
  "$SCRIPTS/review.sh" record --feature "$TMP/f.md" 2>&1
}
rl_setup; m11="$(awk -F'\t' '$1 == 11 { print $5 }' "$GH_REL")"; from="$(git rev-parse "$m11^1")"; cc
check "when every task issue is closed, then check-copy makes the copy at origin/main with nothing merged, ROUND=1, FROM= the parent of the first task PR's merge commit" \
  '[[ "$out" == "CHECK=$(CW) ROUND=1 FROM=$from" && "$(git rev-parse "refs/landspec/check/$(fname)")" == "$(git rev-parse origin/main)" && "$(git -C "$(CW)" rev-parse HEAD)" == "$(git rev-parse origin/main)" ]]'
"$I" check-result green >/dev/null; out="$(fbase "$from")"
check "then record --feature accepts Reviewed: <FROM>..<check ref>, and a ready review after green removes the round file" 'grep -qx "REVIEW=ready" <<<"$out" && [[ -z "$(rnd)" ]]'
cc --remove; cc
check "when that base commit was checked green and ready, then CHECKED=<its sha> and no copy is made" '[[ "$out" == "CHECKED=$(git rev-parse origin/main)" && ! -d "$(CW)" ]]'
on_main more more.txt 'x\n' >/dev/null; cc
check "when origin/main moves, then the base is checked again: CHECK= at the new commit, ROUND=1" \
  '[[ "$out" == "CHECK=$(CW) ROUND=1 FROM=$from" && "$(git rev-parse "refs/landspec/check/$(fname)")" == "$(git rev-parse origin/main)" ]]'
"$I" check-result red >/dev/null; out="$(fbase "$from")"; cc --remove; cc
check "when the run on that commit was red, then a ready review does not make it CHECKED: the same commit is UNCHANGED" '[[ "$out" == UNCHANGED=1 && ! -d "$(CW)" ]]'
on_main more2 more2.txt 'y\n' >/dev/null; cc; "$I" check-result green >/dev/null; out="$(fbase "$from" '- not met: FR-002 — nothing does it')"; cc --remove; cc
check "when the base commit's run was green but its feature review was changes needed, then it is not CHECKED: the copy is made again" \
  'grep -q "^CHECK=$(CW) ROUND=2 FROM=$from$" <<<"$out"' # round 2: the red run above still counts
cc --remove
set_tasks "$(git show origin/main:specs/001-demo/tasks.md)"$'\n''- [ ] T004 Add a late task — #4'; cc
check "when one task is not started and the others are merged, then there is no check of the base: check-copy refuses, as before" \
  'grep -q "no unmerged task branch in this clone to check" <<<"$out" && ! grep -q "^CHECK" <<<"$out"'

# ── Spec 004 T010: the audit before the bump, once per base commit ──
ap() { out="$("$I" audit-plan 2>&1)" || true; }
c0="$(git rev-parse origin/main)"; ap
check "when no audit is recorded, then audit-plan says needed for origin/main's commit" '[[ "$out" == "AUDIT=needed COMMIT=$c0" ]]'
printf '# report\n' > "$TMP/audit.md"; out="$("$I" audit-record "$c0" "$TMP/audit.md" 0 2>&1)" || true; rm -f "$TMP/audit.md"; ap
check "when an audit with no confirmed critical or high is recorded, then done, with a kept copy of the report" \
  '[[ "$out" == "AUDIT=done COMMIT=$c0 REPORT="*"/landspec-security/audit-$c0.md HOLD=0" ]] && grep -qx "# report" "$(sed "s/.*REPORT=//; s/ HOLD=.*//" <<<"$out")"'
printf '# report\n' > "$TMP/audit.md"; "$I" audit-record "$c0" "$TMP/audit.md" 2 >/dev/null; ap
check "when the audit confirmed two, then hold, HOLD=2" '[[ "$out" == "AUDIT=hold COMMIT=$c0 "*" HOLD=2" ]]'
r0="$(sed "s/.*REPORT=//; s/ HOLD=.*//" <<<"$out")"; "$I" audit-record "$c0" "$r0" 0 >/dev/null 2>&1 || true; ap
check "when the held report itself is recorded again with 0 (a disproved finding), then done" '[[ "$out" == "AUDIT=done COMMIT=$c0 REPORT=$r0 HOLD=0" ]] && grep -qx "# report" "$r0"'
c1="$(on_main fix fix.txt 'fixed\n')"; ap
check "when origin/main moved since the audit, then needed again for the new commit" '[[ "$out" == "AUDIT=needed COMMIT=$c1" ]]'
check "when audit-record gets a short sha, a missing report or a hold that is not a number, then it refuses" \
  'fails_with "usage: implement.sh audit-record" "$I" audit-record "${c1:0:7}" "$TMP/audit.md" 0 \
   && fails_with "usage: implement.sh audit-record" "$I" audit-record "$c1" "$TMP/none.md" 0 \
   && fails_with "usage: implement.sh audit-record" "$I" audit-record "$c1" "$TMP/audit.md" x'
check "when the commit is not in the repository, then it refuses" 'fails_with "is not a commit in this repository" "$I" audit-record "$(printf "%040d" 1)" "$TMP/audit.md" 0'
side="$(git commit-tree -p "$c1" -m side "$(git rev-parse "$c1^{tree}")")"; a0="$(cat "$(git rev-parse --git-common-dir)/landspec-security/audit")"
printf '# report\n' > "$TMP/audit.md"
check "when the commit is on a side branch, not on origin/main, then it refuses and the audit record is unchanged" \
  'fails_with "$side is not on origin/main" "$I" audit-record "$side" "$TMP/audit.md" 0 && [[ "$(cat "$(git rev-parse --git-common-dir)/landspec-security/audit")" == "$a0" ]]'
rm -f "$TMP/audit.md"

check "then the current HEAD is the same after every call" '[[ ! -e "$TMP/head.moved" ]]'

# ── Spec 008 T002: on the feature branch, tasks land one at a time on local task refs ──
FB=feat/001-demo; R1=landspec/001-t001-task; R2=landspec/001-t002-task; R3=landspec/001-t003-task
TASKS3='# Tasks

- [ ] T001 Add search in `src/search.ts`
- [ ] T002 Add ranking in `src/rank.ts` (depends on T001)
- [ ] T003 Add export in `src/export.ts`'
# fsetup: feat/001-demo made by branch.sh with the three tasks and a ready plan review; $TMP/w a detached copy.
fsetup() {
  cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/w" "$TMP/l"; : > "$GH_CLOSED"; : > "$GH_OPEN"; rm -f "$GH_PR" "$GH_PR.head"
  new_repo standard
  printf '%s\n' "$TASKS3" > specs/001-demo/tasks.md; printf '# Plan\n' > specs/001-demo/plan.md
  "$SCRIPTS/branch.sh" >/dev/null 2>&1
  git worktree add --quiet --detach "$TMP/w" "$FB"
}
# build <ref> [<file> <text>]: one commit on the task ref, made in $TMP/w (the ref starts from the feature head), then detached there.
build() {
  if git show-ref --verify --quiet "refs/heads/$1"; then git -C "$TMP/w" switch --quiet "$1"
  else git -C "$TMP/w" switch --quiet -c "$1" "$FB"; git config "branch.$1.landspec-parent" "$FB"; fi
  printf '%s\n' "${3:-$RANDOM}" >> "$TMP/w/${2:-${1//\//_}.txt}"
  git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet -m "feat: $1"; git -C "$TMP/w" switch --quiet --detach
}
fs() { out="$("$I" status "$@" 2>&1)" || true; }
head_fb() { git rev-parse "refs/heads/$FB"; }

fsetup
check "when the plan has no ready review, then status on the feature branch refuses naming the plan review" \
  'one_refusal "no independent review recorded for the plan" "$I" status'
plan_review >/dev/null 2>&1; fs
check "when nothing is built, then T001 and T003 start from the feature head on their task refs, and T002 waits for T001" \
  'grep -qx "START=T001 REF=$R1 FROM=$(head_fb)" <<<"$out" && grep -qx "START=T003 REF=$R3 FROM=$(head_fb)" <<<"$out" && [[ "$(grep -c "^START=" <<<"$out")" == 2 && "$(state_of T001)" == pending && "$(state_of T003)" == pending ]] \
   && line_of T002 | grep -qx "TASK=T002 STATE=waiting REASON=waits for T001"'
check "then it ends with CHECK=no PR=- ORDER=T001 T002 T003 DONE=0/3" \
  '[[ "$(tail -4 <<<"$out")" == "CHECK=no"$'"'"'\n'"'"'"PR=-"$'"'"'\n'"'"'"ORDER=T001 T002 T003"$'"'"'\n'"'"'"DONE=0/3" ]]'
build "$R1"; echo findings > "$TMP/r.md"; o1="$("$I" mark T001 changes "$TMP/r.md")"; o2="$("$I" mark T001 changes "$TMP/r.md")"; fs
check "when T001 gets its second changes (task_rounds 2 by default), then mark prints FAILED=T001, and not on the first" \
  'grep -qx "FAILED=T001" <<<"$o2" && ! grep -q "^FAILED=" <<<"$o1"'
check "then T001 is failed, T002 stays waiting, and the independent T003 starts" \
  'line_of T001 | grep -q "STATE=failed ROUND=2 REASON=review rounds" && [[ "$(state_of T002)" == waiting ]] && grep -qx "START=T003 REF=$R3 FROM=$(head_fb)" <<<"$out"'
git worktree add --quiet "$TMP/l" "$R1"; rf="$(git rev-parse --git-common-dir)/landspec-run/001-demo/T001"; cp "$rf" "$TMP/rec.before"
check "when T001's ref is checked out in a worktree, then retry refuses it and leaves its record unchanged" \
  'one_refusal "is checked out in" "$I" retry T001 && cmp -s "$rf" "$TMP/rec.before" && git show-ref --verify --quiet "refs/heads/$R1"'
git worktree remove --force "$TMP/l"
"$I" retry T001 >/dev/null; fs
check "when T001 is retried, then its task ref is gone and it starts again from the feature head, with no RESUME" \
  '! git show-ref --verify --quiet "refs/heads/$R1" && [[ -z "$(git config --get-regexp "^branch\.$R1\." || true)" ]] && grep -qx "START=T001 REF=$R1 FROM=$(head_fb)" <<<"$out"'
build "$R1"; rm -f "$(git rev-parse --git-common-dir)/landspec-run/001-demo/T001"; fs
check "when T001's ref is there with no run record, then it starts again on that ref: RESUME=yes" \
  'grep -qx "START=T001 REF=$R1 FROM=$(head_fb) RESUME=yes" <<<"$out" && [[ "$(state_of T001)" == pending ]]'
echo "task_rounds: 10" >> .specify/extensions/landspec/landspec-config.yml
check "when task_rounds is 10, then mark changes refuses it and exits non-zero" 'one_refusal "task_rounds must be a number from 1 to 9" "$I" mark T001 changes "$TMP/r.md"'
sed -i.bak '/^task_rounds:/d' .specify/extensions/landspec/landspec-config.yml
fs --running T001
check "when T001 is running, then it is building and only the independent T003 starts" \
  '[[ "$(state_of T001)" == building && "$(grep -E "^(START|REVIEW|FIX|LAND)=" <<<"$out")" == "START=T003 REF=$R3 FROM=$(head_fb)" ]]'
git worktree add --quiet "$TMP/l" "$R1"; git worktree lock "$TMP/l"; fs
check "when T001's ref is checked out in a locked worktree, then it waits with the worktree named" \
  'line_of T001 | grep -qxF "TASK=T001 STATE=waiting REASON=locked worktree $(cd "$TMP/l" && pwd -P)"'
git worktree unlock "$TMP/l"; git worktree remove --force "$TMP/l"
"$I" mark T001 changes "$TMP/r.md" >/dev/null; fs
check "when T001 is marked changes once, then it is changes with ROUND=1 and FIX=T001 is the next step" \
  'line_of T001 | grep -qx "TASK=T001 STATE=changes ROUND=1" && grep -qx "FIX=T001" <<<"$out"'
"$I" mark T001 implemented >/dev/null; fs
check "when T001 is marked implemented, then it is built and REVIEW=T001 is the next step" '[[ "$(state_of T001)" == built ]] && grep -qx "REVIEW=T001" <<<"$out"'
check "when T001 is not ready, then land refuses it" 'one_refusal "T001 is not ready" "$I" land T001'
ready "$R1"; "$I" mark T001 ready >/dev/null; fs
check "when T001's review is ready and marked, then it is review and LAND=T001 is the next step" '[[ "$(state_of T001)" == review ]] && grep -qx "LAND=T001" <<<"$out"'
echo '- [ ] T004 Draft' >> specs/001-demo/tasks.md
check "when tasks.md has uncommitted changes, then land refuses them" 'one_refusal "uncommitted changes in specs/001-demo" "$I" land T001'
git checkout -- specs/001-demo/tasks.md
build "$R1"; "$I" mark T001 ready >/dev/null
check "when T001's ref moved after its review, then land refuses it" 'one_refusal "changed since its ready review" "$I" land T001'
ready "$R1"; "$I" mark T001 ready >/dev/null
echo dev > dev.txt; git add dev.txt; git commit --quiet -m "chore: a developer commit"; dev="$(git rev-parse HEAD)"
pid="$(sed -n 's/^state: //p' "$(git rev-parse --git-common-dir)/landspec-review/task-${R1//\//__}")"
lo="$("$I" land T001 2>&1)" || true
check "when T001 is ready, then land prints LANDED=T001 with the merge commit" '[[ "$lo" == "LANDED=T001 COMMIT=$(git rev-parse HEAD)" ]]'
check "then the merge is --no-ff, titled T001: Add search, with both trailers" \
  '[[ "$(git log -1 --format=%B)" == "T001: Add search"$'"'"'\n\n'"'"'"Landspec-Task: 001/T001"$'"'"'\n'"'"'"Landspec-Review: ready $pid" && -n "$pid" && "$(git rev-parse HEAD^1)" == "$dev" ]] && git rev-parse --verify --quiet HEAD^2 >/dev/null'
check "then its tree has the tick, the task's change and the developer's commit, and origin has it" \
  'git show HEAD:specs/001-demo/tasks.md | grep -q "^- \[X\] T001 " && git cat-file -e "HEAD:${R1//\//_}.txt" && git cat-file -e HEAD:dev.txt \
   && [[ "$(git ls-remote origin "refs/heads/$FB" | cut -f1)" == "$(git rev-parse HEAD)" && -z "$(git status --porcelain)" ]]'
check "then the task ref and its settings are gone" '! git show-ref --verify --quiet "refs/heads/$R1" && [[ -z "$(git config --get-regexp "^branch\.$R1\." || true)" ]]'
fs
check "then T001 is done, T002 starts from the new head, and the plan review still holds after the tick" \
  '[[ "$(state_of T001)" == done ]] && grep -qx "START=T002 REF=$R2 FROM=$(head_fb)" <<<"$out" && grep -qx "DONE=1/3" <<<"$out"'
check "when T001 is landed already, then land refuses it" 'one_refusal "T001 is landed already" "$I" land T001'
echo "https://github.com/acme/app/pull/99" > "$GH_PR"; echo "$FB" > "$GH_PR.head"; fs
check "when the feature branch has an open PR, then status prints PR=<its url>" 'grep -qx "PR=https://github.com/acme/app/pull/99" <<<"$out"'
rm -f "$GH_PR" "$GH_PR.head"
build "$R3"; "$I" mark T003 implemented >/dev/null; ready "$R3"; "$I" mark T003 ready >/dev/null
git merge --quiet --no-ff --no-edit "refs/heads/$R3"; hm="$(git rev-parse HEAD)"
check "when a ready task's ref was merged into the feature branch by hand, then land refuses naming that merge and changes nothing" \
  'one_refusal "already in $FB'"'"'s history (merged by hand?)" "$I" land T003 && [[ "$(git rev-parse HEAD)" == "$hm" ]] && git show-ref --verify --quiet "refs/heads/$R3" \
   && ! git log --format=%B | grep -qx "Landspec-Task: 001/T003"'
git reset --quiet --hard HEAD^1; git branch --quiet -D "$R3"
# The analyzed marker hashes tasks.md as /speckit-analyze saw it: no tick, with or without the issue line.
sh256() { bash -c 'source "$0/lib.sh"; sha256' "$SCRIPTS"; }
mk_marker() { mkdir -p "$(git rev-parse --git-common-dir)/landspec-analyzed"; cat > "$(git rev-parse --git-common-dir)/landspec-analyzed/001-demo"; }
set_cfg level full; echo stale | mk_marker
check "when the level is full and the analyzed marker is for another tasks.md, then status refuses" \
  'one_refusal "level '"'"'full'"'"' requires /speckit-analyze" "$I" status'
printf '## Specification Analysis Report\n\nCoverage Summary Table\n' > "$TMP/an.md"
check "when /speckit-analyze runs again after a landing (tasks.md ticked), then analyzed.sh's marker lets status run" \
  'git show HEAD:specs/001-demo/tasks.md | grep -q "^- \[X\] T001 " && "$SCRIPTS/analyzed.sh" "$TMP/an.md" >/dev/null && "$I" status | grep -q "^DONE=1/3$"'
sed 's/^- \[X\] T001 /- [ ] T001 /' specs/001-demo/tasks.md | sh256 | mk_marker
check "when the marker hashes tasks.md before the tick and before the issue line, then status runs" '"$I" status | grep -q "^DONE=1/3$"'
awk 'NR == 1 { print; print ""; print "**Issue**: #7"; next } { print }' specs/001-demo/tasks.md > "$TMP/t.md"; cat "$TMP/t.md" > specs/001-demo/tasks.md
check "when the issue line is added after the analysis, then status still runs" '"$I" status | grep -q "^DONE=1/3$"'
sed 's/^- \[X\] T001 /- [ ] T001 /' specs/001-demo/tasks.md | sh256 | mk_marker
check "when the marker hashes tasks.md with its issue line, before the tick, then status runs" '"$I" status | grep -q "^DONE=1/3$"'
git checkout -- specs/001-demo/tasks.md; set_cfg level standard
build "$R2" clash.txt task; "$I" mark T002 implemented >/dev/null; ready "$R2"; "$I" mark T002 ready >/dev/null
echo dev > clash.txt; git add clash.txt; git commit --quiet -m "chore: a conflicting commit"; h="$(git rev-parse HEAD)"; r2="$(git rev-parse "refs/heads/$R2")"
check "when the feature branch has a conflicting developer commit, then land prints CONFLICT= naming the file and leaves the branches as they were" \
  'rc=0; o="$("$I" land T002 2>/dev/null)" || rc=$?; ((rc == 1)) && [[ "$o" == "CONFLICT=T002 FILES=clash.txt" ]] && [[ "$(git rev-parse HEAD)" == "$h" && "$(git rev-parse "refs/heads/$R2")" == "$r2" && -z "$(git status --porcelain)" ]] \
   && ! git rev-parse --verify --quiet MERGE_HEAD >/dev/null'
# A pull merge in another clone: its local work (from before T001 landed) first, the landed branch second.
L="$(git log -1 --format=%H --grep='^Landspec-Task: 001/T001$')"; X="$(git commit-tree "$L^1^{tree}" -p "$L^1" -m "chore: local work")"
git reset --quiet --hard "$(git commit-tree "$h^{tree}" -p "$X" -p "$h" -m "Merge branch '$FB' of origin into $FB")"; fs
check "when a pull merge joins T001's landing as its second parent, then T001 is still done" \
  '! git rev-list --first-parent HEAD | grep -qx "$L" && [[ "$(state_of T001)" == done ]] && grep -qx "DONE=1/3" <<<"$out"'
git push --quiet origin "$(git commit-tree "$FB^{tree}" -p origin/develop -p "$FB" -m "Merge pull request #99 from $FB"):refs/heads/develop"; git fetch --quiet origin; fs
check "when this feature's PR is merged into the base with a merge commit and fetched, then its landed task is still done" \
  'git merge-base --is-ancestor "$FB" origin/develop && [[ "$(state_of T001)" == done ]] && grep -qx "DONE=1/3" <<<"$out" && one_refusal "T001 is landed already" "$I" land T001'
printf '%s\n' '- [ ] T009 Old way in `a` — #5' >> specs/001-demo/tasks.md
check "when the feature was started under the per-task flow, then status prints LEGACY= and refuses" \
  'rc=0; o="$("$I" status 2>/dev/null)" || rc=$?; ((rc != 0)) && [[ "$o" == LEGACY=001-demo ]]'
git checkout -- specs/001-demo/tasks.md

# Another feature's landings on the base never count: task ids restart at T001 in every feature, so the
# trailer names the feature (000/T001 here, this feature being 001); nor does the old bare trailer.
# on_base <how> <trailer>: a fresh repo whose develop holds a T001 landing with that trailer, squashed or merged by its
# PR's merge commit; then this feature's branch is cut from it, with a ready plan review, and status runs.
on_base() {
  cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/w"; new_repo standard
  local b t s l m="T001: an earlier task"$'\n\n'"Landspec-Task: $2"; b="$(git rev-parse HEAD)"; t="$(git rev-parse 'HEAD^{tree}')"
  if [[ "$1" == squash ]]; then s="$(git commit-tree "$t" -p "$b" -m "$m")"
  else l="$(git commit-tree "$t" -p "$b" -p "$(git commit-tree "$t" -p "$b" -m "feat: old work")" -m "$m")" # its landing
    s="$(git commit-tree "$t" -p "$b" -p "$l" -m "Merge pull request #1 from feat/000-old")"; fi
  git push --quiet origin "$s:refs/heads/develop"; git fetch --quiet origin
  printf '%s\n' "$TASKS3" > specs/001-demo/tasks.md; printf '# Plan\n' > specs/001-demo/plan.md
  "$SCRIPTS/branch.sh" >/dev/null 2>&1; plan_review >/dev/null 2>&1; fs
}
for c in "squash 000/T001" "merge 000/T001" "squash T001"; do
  how="${c% *}"; tr="${c#* }"; on_base "$how" "$tr"
  check "when the base holds a T001 landing with Landspec-Task: $tr ($how), then this feature's T001 is pending and starts" \
    'git log --format=%B | grep -qx "Landspec-Task: $tr" && [[ "$(state_of T001)" == pending ]] && grep -q "^START=T001 " <<<"$out" && grep -qx "DONE=0/3" <<<"$out"'
  check "then land T001 is not refused as landed already ($how, $tr)" 'one_refusal "has no task ref" "$I" land T001'
done

# ── Spec 008 T017: every startable task starts at once, and a conflicting landing gets one round ──
starts() { grep "^START=" <<<"$out" | tr '\n' ' '; }
fsetup; plan_review >/dev/null 2>&1; fs
check "when T001 and T003 are startable and T002 depends on T001, then status starts T001 and T003, not T002" \
  '[[ "$(starts)" == "START=T001 REF=$R1 FROM=$(head_fb) START=T003 REF=$R3 FROM=$(head_fb) " ]]'
cfg_set 1; fs
check "when parallel_tasks is 1, then only START=T001" '[[ "$(starts)" == "START=T001 REF=$R1 FROM=$(head_fb) " ]]'
fs --running T001
check "when parallel_tasks is 1 and T001 is running, then nothing starts" '[[ -z "$(starts)" && "$(state_of T001)" == building ]]'
cfg_set ""; fs --running T001
check "when T001 is running, then only START=T003" '[[ "$(starts)" == "START=T003 REF=$R3 FROM=$(head_fb) " ]]'
fs --running T001 --running T003
check "when --running is given twice, then both tasks are building and nothing starts" \
  '[[ -z "$(starts)" && "$(state_of T001)" == building && "$(state_of T003)" == building ]]'
# The lows in the shapes recorded reviews write them, beside list items that are not lows.
lows='
- deep: src/search.ts — gate
- Lower bound is checked
| 1 | Low | src/x.ts:1 | resolved |

Findings: 0 high, 0 medium, 5 low

1. **Low** — `src/search.ts:3` — a test gap on the empty query
- **Low** src/rank.ts:7 wording of the error
1. Low — docs/r.md:342: the refusal names no fix
- Low: a.sh:84-91: the range is not checked
- Low, `docs/reference.md` (the table) is stale
'
wantlows='Low: src/search.ts:3 a test gap on the empty query
Low: src/rank.ts:7 wording of the error
Low: docs/r.md:342 the refusal names no fix
Low: a.sh:84-91 the range is not checked
Low: docs/reference.md (the table) is stale'
build "$R1" clash.txt one; "$I" mark T001 implemented >/dev/null; ready "$R1" "$lows"; "$I" mark T001 ready >/dev/null
build "$R3" clash.txt three; "$I" mark T003 implemented >/dev/null; ready "$R3"; "$I" mark T003 ready >/dev/null; fs
check "when T001 and T003 are both ready, then status prints LAND=T001 and LAND=T003" 'grep -qx "LAND=T001" <<<"$out" && grep -qx "LAND=T003" <<<"$out"'
pid="$(sed -n 's/^state: //p' "$(git rev-parse --git-common-dir)/landspec-review/task-${R1//\//__}")"
"$I" land T001 >/dev/null 2>&1; l1="$(head_fb)"
msg1="T001: Add search"$'\n\n'"$wantlows"$'\n\n'"Landspec-Task: 001/T001"$'\n'"Landspec-Review: ready $pid"
check "when the review wrote five lows in five shapes (bold, numbered, dash, range, backticks, no line), then the landing commit has one Low: line each above the trailers" \
  '[[ "$(git log -1 --format=%B "$l1")" == "$msg1" ]]'
lrc=0; o="$("$I" land T003 2>/dev/null)" || lrc=$?; fs
check "when T003 edits the line T001 landed, then land prints CONFLICT=T003 with the file, exits 1 and leaves the branch at T001's landing" \
  '((lrc == 1)) && [[ "$o" == "CONFLICT=T003 FILES=clash.txt" && "$(head_fb)" == "$l1" && -z "$(git status --porcelain)" ]] && ! git rev-parse --verify --quiet MERGE_HEAD >/dev/null'
check "then status prints FIX=T003 REASON=conflict, and the conflict takes no fix round" \
  'grep -qx "FIX=T003 REASON=conflict" <<<"$out" && line_of T003 | grep -qx "TASK=T003 STATE=changes"'
# resolve <ref>: the task's copy merges the feature branch into its ref and keeps both sides.
resolve() {
  git -C "$TMP/w" switch --quiet "$1"; git -C "$TMP/w" merge --quiet "$FB" >/dev/null 2>&1 || true
  printf 'one\nthree\n' > "$TMP/w/clash.txt"; git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet --no-edit; git -C "$TMP/w" switch --quiet --detach
}
resolve "$R3"; "$I" mark T003 implemented >/dev/null; ready "$R3"; "$I" mark T003 ready >/dev/null; fs
check "when T003 has merged the feature branch and is ready again, then it is LAND=T003, not FIX" 'grep -qx "LAND=T003" <<<"$out" && ! grep -q "^FIX=" <<<"$out"'
o="$("$I" land T003 2>&1)" || true
check "then it lands" '[[ "$o" == "LANDED=T003 COMMIT=$(head_fb)" ]]'
# T002 (now startable) conflicts twice: a developer commit on the same line before each landing.
dev() { git switch --quiet "$FB"; printf '%s\n' "$1" >> clash.txt; git add clash.txt; git commit --quiet -m "chore: $1"; }
build "$R2" clash.txt two; "$I" mark T002 ready >/dev/null 2>&1; ready "$R2"; "$I" mark T002 ready >/dev/null; dev dev1
o="$("$I" land T002 2>/dev/null)" || true
check "when T002 conflicts once, then CONFLICT=T002" '[[ "$o" == "CONFLICT=T002 FILES=clash.txt" ]]'
git -C "$TMP/w" switch --quiet "$R2"; git -C "$TMP/w" merge --quiet "$FB" >/dev/null 2>&1 || true
printf 'one\nthree\ndev1\ntwo\n' > "$TMP/w/clash.txt"; git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet --no-edit; git -C "$TMP/w" switch --quiet --detach
ready "$R2"; "$I" mark T002 ready >/dev/null; dev dev2; h="$(head_fb)"
lrc=0; o="$("$I" land T002 2>/dev/null)" || lrc=$?; fs
check "when T002 conflicts a second time, then land prints FAILED=T002, exits 1, and T002 is failed" \
  '((lrc == 1)) && [[ "$o" == "FAILED=T002" && "$(head_fb)" == "$h" && "$(state_of T002)" == failed ]]'
"$I" retry T002 >/dev/null; build "$R2" clash.txt two; ready "$R2"; "$I" mark T002 ready >/dev/null; dev dev3
o="$("$I" land T002 2>/dev/null)" || true
check "when T002 is retried, then its next conflict is a conflict round again, not FAILED" '[[ "$o" == "CONFLICT=T002 FILES=clash.txt" ]]'
# The tick is made on the feature branch's side: a plan edit there after the ref was cut never conflicts.
fsetup; build "$R1"; ready "$R1"; "$I" mark T001 ready >/dev/null
sed 's/^- \[ \] T001 Add search in `src\/search.ts`$/& (edited)/' specs/001-demo/tasks.md > "$TMP/t.md"; cat "$TMP/t.md" > specs/001-demo/tasks.md
git commit --quiet -am "docs(specs): edit T001"
o="$("$I" land T001 2>&1)" || true
check "when the feature branch edited T001's line after its ref was cut, then land succeeds and the edited line is ticked" \
  '[[ "$o" == "LANDED=T001 COMMIT=$(head_fb)" ]] && git show "$FB:specs/001-demo/tasks.md" | grep -qxF -- "- [X] T001 Add search in \`src/search.ts\` (edited)" && [[ -z "$(git status --porcelain)" ]]'
# After a delta, the record holds only the delta's report: the first round's lows come from the report mark changes kept.
fsetup; build "$R3"; h1="$(git rev-parse "refs/heads/$R3")"
ready "$R3" $'\n- Low: src/export.ts:0 only in round one\n- Low: src/export.ts:1 kept from round one\n- High: src/export.ts:2 broken\n'; cp "$TMP/r.md" "$TMP/r1.md"
"$I" mark T003 changes "$TMP/r1.md" >/dev/null; build "$R3"; h2="$(git rev-parse "refs/heads/$R3")"
printf 'Reviewed: %s..%s\nDelta from: %s\nModel: claude-opus-5-5\n\n- Low: src/export.ts:1 kept from round one\n- Low: src/export.ts:9 new in the delta\n\nAssessment: ready\n' "$h1" "$h2" "$h1" > "$TMP/d.md"
"$SCRIPTS/review.sh" record --delta --branch "$R3" "$TMP/d.md" >/dev/null 2>&1; "$I" mark T003 ready >/dev/null
o="$("$I" land T003 2>&1)" || true
check "when T003 lands after a delta review, then its message has the first round's lows and the delta's, a low in both once" \
  '[[ "$o" == LANDED=T003* ]] && git log -1 --format=%B "$FB" | grep -x "Low: .*" | tr "\n" "|" | grep -qxF "Low: src/export.ts:0 only in round one|Low: src/export.ts:1 kept from round one|Low: src/export.ts:9 new in the delta|"'
exit "$FAIL"
