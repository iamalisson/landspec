#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
n="$SCRIPTS/next.sh"
# land <Tnnn>: a landing commit of the task on the current branch, as implement.sh land makes it.
land() { git commit --quiet --allow-empty -m "$1: landed" -m "Landspec-Task: $1"$'\n'"Landspec-Review: ready abc123"; }

new_repo standard
commit_tasks '# Tasks

**Issue**: #263

- [ ] T001 First in `a`
- [ ] T002 [P] Second in `b`
- [ ] T003 Third in `c` (depends on T002)'

check "when the feature branch does not exist yet, then every task is pending or waiting and the first is next" \
  'out="$("$n")"; grep -qx "pending T001 First" <<<"$out" && grep -qx "waiting T003 Third" <<<"$out" && [[ "$(tail -1 <<<"$out")" == "DONE=0/3 NEXT=T001" ]]'

git switch --quiet -c feat/001-demo; land T001; git switch --quiet main
: > "$GH_LOG"; out="$("$n")"
check "when one task of three has landed, then it is done, the next pending and the dependent one waiting" \
  'grep -qx "done T001 First" <<<"$out" && grep -qx "pending T002 Second" <<<"$out" && grep -qx "waiting T003 Third" <<<"$out"'
check "then the last two lines name the feature, its branch, issue and PR, then DONE=1/3 NEXT=T002" \
  '[[ "$(tail -2 <<<"$out")" == $'"'"'FEATURE=001 BRANCH=feat/001-demo ISSUE=#263 PR=-\nDONE=1/3 NEXT=T002'"'"' ]]'
check "then no GitHub issue is read, and there is no parallel, RUN= or CHOOSE= line" \
  '! grep -q "^issue " "$GH_LOG" && ! grep -q "^api graphql" "$GH_LOG" && ! grep -qE "^(parallel|RUN=|CHOOSE=)" <<<"$out"'
check "when a commit only mentions a task, then it is not done" \
  'git switch --quiet feat/001-demo; git commit --quiet --allow-empty -m "T002: wip" -m "see Landspec-Task: T002 later"; git switch --quiet main; out="$("$n")"; grep -qx "pending T002 Second" <<<"$out"'

rec="$(git rev-parse --git-common-dir)/landspec-run/001-demo"; mkdir -p "$rec"
printf 'phase=implemented\nfailed=tests red twice\n' > "$rec/T002"
check "when the run record says a task failed, then it is failed and not next" \
  'out="$("$n")"; grep -qx "failed T002 Second" <<<"$out" && [[ "$(tail -1 <<<"$out")" == "DONE=1/3 NEXT=" ]]'
rm -rf "$rec"

echo "https://github.com/acme/app/pull/7" > "$GH_PR"; echo feat/001-demo > "$GH_PR.head"
check "when the feature branch has an open PR, then PR= is its URL" \
  '[[ "$("$n" | tail -2 | head -1)" == *" PR=https://github.com/acme/app/pull/7" ]]'
rm -f "$GH_PR" "$GH_PR.head"
check "when the PR cannot be looked up, then next stops naming it" 'GH_FAIL_PR_LIST=1 fails_with "cannot look up the feature" "$n"'

# The feature branch's tasks.md is read, not the checkout's.
git switch --quiet feat/001-demo; printf '%s\n' '- [ ] T004 Fourth in `d`' >> specs/001-demo/tasks.md
git add -A; git commit --quiet -m "docs: T004"; git switch --quiet main
check "when the feature branch's tasks.md has a task the checkout's has not, then it is shown" \
  'out="$("$n")"; grep -qx "pending T004 Fourth" <<<"$out" && [[ "$(tail -1 <<<"$out")" == "DONE=1/4 NEXT=T002" ]]'

git push --quiet origin feat/001-demo; git branch --quiet -D feat/001-demo
check "when the feature branch is only on origin, then its landing commits and tasks are read" \
  'out="$("$n")"; grep -qx "done T001 First" <<<"$out" && grep -qx "pending T004 Fourth" <<<"$out"'

git fetch --quiet origin; git switch --quiet -c feat/001-demo origin/feat/001-demo
land T002; land T003; land T004
check "when every task has landed, then NEXT is empty and DONE=y/y" '[[ "$("$n" | tail -1)" == "DONE=4/4 NEXT=" ]]'
git switch --quiet main; git branch --quiet -D feat/001-demo; git push --quiet origin --delete feat/001-demo

# Legacy features (research R11): started under the per-task flow, a line ends in " — #N".
mkdir -p specs/002-old specs/003-older
printf '%s\n' '- [X] T001 Old in `o` — #5' > specs/002-old/tasks.md
printf '%s\n' '- [ ] T001 Older in `p` — #6' > specs/003-older/tasks.md
check "when a legacy feature is named, then next prints LEGACY= and the R11 message and exits 1" \
  'rc=0; out="$("$n" 002 2>"$TMP/err")" || rc=$?; ((rc == 1)) && grep -qx "LEGACY=002-old" <<<"$out" && grep -qF "per-task flow" "$TMP/err" && ! grep -q "^DONE=" <<<"$out"'
echo '{ "feature_directory": "specs/002-old" }' > .specify/feature.json
check "when two legacy features and one new feature exist and none is named, then the new one is served, with no CHOOSE= or LEGACY=" \
  'out="$("$n")"; grep -q "^FEATURE=001 " <<<"$out" && ! grep -qE "^(CHOOSE|LEGACY)=" <<<"$out"'

mkdir -p specs/004-new; printf '%s\n' '- [ ] T001 New in `n`' > specs/004-new/tasks.md
check "when two new features have work and none is named, then it lists them and asks, leaving the legacy ones out" \
  'out="$("$n")"; grep -qx "feature 001-demo DONE=0/3" <<<"$out" && grep -qx "feature 004-new DONE=0/1" <<<"$out" && [[ "$(tail -1 <<<"$out")" == "CHOOSE=001-demo 004-new" ]] && ! grep -qE "old|LEGACY" <<<"$out"'
check "when a feature is named, then it becomes the active one and is served" \
  'out="$("$n" 004)"; [[ "$(tail -1 <<<"$out")" == "DONE=0/1 NEXT=T001" ]] && grep -q "ISSUE=- " <<<"$out" && grep -q "specs/004-new" .specify/feature.json'
check "when the name matches no single feature, then it refuses" 'fails_with "no single feature" "$n" 009'

# On a task ref (landspec/NNN-tnnn-task), its feature is served.
git switch --quiet -c landspec/004-t001-task
check "when the current branch is a task ref of one feature, then that feature is served with no CHOOSE=" \
  'echo "{ \"feature_directory\": \"specs/001-demo\" }" > .specify/feature.json; out="$("$n")"; grep -q "^FEATURE=004 " <<<"$out" && ! grep -q CHOOSE <<<"$out"'
git switch --quiet main; git branch --quiet -D landspec/004-t001-task
rm -rf specs/002-old specs/003-older specs/004-new; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

check "then the next skill shows the progress and starts /landspec:implement <FEATURE>, never a single task or a parallel offer" \
  'grep -qF "/landspec:implement <FEATURE>" "$ROOT/skills/next/SKILL.md" && ! grep -qE "speckit-implement <|parallel|RUN=|resume|in-progress" "$ROOT/skills/next/SKILL.md"'

mkdir -p "$TMP/mono/apps/web/.specify" && git -C "$TMP/mono" init --quiet
check "when spec-kit lives in a subfolder of the repo, then scripts refuse instead of writing into the parent" \
  '(cd "$TMP/mono/apps/web" && fails_with "a subfolder of the repository" "$SCRIPTS/next.sh") && [[ ! -e "$TMP/mono/.specify" ]]'

exit "$FAIL"
