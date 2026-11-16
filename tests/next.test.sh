#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
n="$SCRIPTS/next.sh"
closed() { printf '%s\n' "$@" > "$GH_CLOSED"; } # issue numbers the fake gh reports as closed
open_prs() { printf '%s\n' "$@" > "$GH_OPEN"; }  # head branches of the open PRs the fake gh reports

new_repo standard
commit_tasks '- [ ] T001 First in `a` — #1
- [ ] T002 [P] Second in `b` — #2
- [ ] T003 Third in `c` — #3'

closed
out="$("$n")"
check "when no issue is closed, then the next task is the first one" '[[ "$out" == *"DONE=0/3 IN_PROGRESS=0 NEXT=T001"* ]]'
check "when two tasks can start (NEXT and a [P] one), then RUN=/landspec:implement is printed just before FEATURE=, the last two lines unchanged" \
  '[[ "$(tail -3 <<<"$out")" == $'"'"'RUN=/landspec:implement 001\nFEATURE=001\nDONE=0/3 IN_PROGRESS=0 NEXT=T001'"'"' ]]'

closed 1 3
out="$("$n")"
check "when issues are closed out of order, then the next task is the first still open" '[[ "$out" == *"DONE=2/3 IN_PROGRESS=0 NEXT=T002"* ]]'
check "when only one task can start, then there is no RUN= line" '! grep -q "^RUN=" <<<"$out"'
check "then each task shows its state" 'grep -q "^done T001 #1 First" <<<"$out" && grep -q "^open T002 #2 Second" <<<"$out"'

# F1.2: the state comes from the issue numbers, so a renamed issue (one a title search misses) still counts.
check "when a closed task issue is not found by a title search, then next shows it done and makes no --search call" \
  ': > "$GH_LOG"; out="$("$n")"; grep -q "^done T001 #1" <<<"$out" && grep -q "^api graphql" "$GH_LOG" && ! grep -q -- --search "$GH_LOG"'
check "when the issue-state query fails, then next stops with gh's error and names the tasks.md to fix" \
  'GH_FAIL_GRAPHQL=999 fails_with "cannot read the state of feature 001'"'"'s task issues; fix or remove the issue number it names in specs/001-demo/tasks.md" "$n" && GH_FAIL_GRAPHQL=999 fails_with "number of 999" "$n"'

closed 1; open_prs feat/001-t002-second-in-b
out="$("$n")"
check "when a task's branch has an open PR (another worktree), then it is in progress and the next open task is picked" \
  'grep -q "^in-progress T002 #2 Second" <<<"$out" && [[ "$out" == *"DONE=1/3 IN_PROGRESS=1 NEXT=T003"* ]]'
open_prs feat/001-t002-second-in-b feat/001-t003-third-in-c
check "when every remaining task has an open PR, then nothing is left to start" '[[ "$("$n" | tail -1)" == "DONE=1/3 IN_PROGRESS=2 NEXT=" ]]'
open_prs feat/002-t002-other-feature
check "then an open PR of another feature's T002 does not count" '[[ "$("$n" | tail -1)" == *"NEXT=T002"* ]]'
open_prs

closed 1 2 3
check "when every issue is closed, then there is no next task" '[[ "$("$n" | tail -1)" == "DONE=3/3 IN_PROGRESS=0 NEXT=" ]]'

# Claims: a branch on origin (another clone started it), one checked out in another worktree,
# one only local (started here, parked), and the current one.
closed; open_prs
git push --quiet origin main:feat/001-t002-second-in-b
check "when a task's branch is on origin without a PR, then it is in progress (claimed elsewhere)" \
  'out="$("$n")"; grep -q "^in-progress T002" <<<"$out" && [[ "$out" == *"NEXT=T001"* ]]'
git push --quiet origin --delete feat/001-t002-second-in-b
git branch --quiet feat/001-t003-third-in-c origin/develop
check "when a task's branch exists only here, then it is yours to resume and is picked before the open ones" \
  'out="$("$n")"; grep -q "^resume T003" <<<"$out" && [[ "$out" == *"IN_PROGRESS=0 NEXT=T003"* ]]'
git worktree add --quiet "$TMP/wt3" feat/001-t003-third-in-c 2>/dev/null
check "when that branch is checked out in another worktree, then it is in progress, not resume" \
  'out="$("$n")"; grep -q "^in-progress T003" <<<"$out" && [[ "$out" == *"NEXT=T001"* ]]'
check "then from inside that worktree the task is the one to resume" \
  'out="$(cd "$TMP/wt3" && mkdir -p .specify/extensions/landspec && ln -sfn "$ROOT/extension/scripts" .specify/extensions/landspec/scripts && cp "$TMP/repo/.specify/extensions/landspec/landspec-config.yml" .specify/extensions/landspec/ && "$n")"; grep -q "^resume T003" <<<"$out" && [[ "$out" == *"NEXT=T003"* ]]'
git worktree remove --force "$TMP/wt3"; git branch --quiet -D feat/001-t003-third-in-c

# Dependencies: "(depends on T001)" holds a task until T001's issue is closed.
closed; open_prs
printf '%s\n' '- [ ] T005 [US2] Report screen (depends on T001, T002) in `s` — #8' >> specs/001-demo/tasks.md
check "when a task depends on open tasks, then it is blocked and not picked" \
  'out="$("$n")"; grep -q "^blocked T005 #8" <<<"$out" && [[ "$out" == *"NEXT=T001"* ]]'
closed 1 2 3
check "when the tasks it depends on are done, then it is open and picked" \
  'out="$("$n")"; grep -q "^open T005 #8" <<<"$out" && [[ "$out" == *"NEXT=T005"* ]]'
closed 2 3
check "when only one dependency is still open, then it stays blocked" 'out="$("$n")"; grep -q "^blocked T005" <<<"$out"'
# #185: the clause at the end of the line, after its summary was cut: still enforced, not shown.
printf '%s\n' '- [ ] T006 Export screen (depends on T001) — #9' >> specs/001-demo/tasks.md
check "when the dependency ends the line, then the task is still blocked by it and shown without the clause" \
  'out="$("$n")"; grep -qx "blocked T006 #9 Export screen" <<<"$out"'
closed 1 2 3
check "then once that dependency is done, it is open" 'out="$("$n")"; grep -qx "open T006 #9 Export screen" <<<"$out"'
sed -i.bak '/T006/d' specs/001-demo/tasks.md; rm -f specs/001-demo/tasks.md.bak
sed -i.bak '/T005/d' specs/001-demo/tasks.md; rm -f specs/001-demo/tasks.md.bak; closed

# Several features: a second one with tasks to start.
mkdir -p specs/002-reports; printf '%s\n' '- [ ] T001 Report in `r` — #30' > specs/002-reports/tasks.md
check "when two features have tasks to start and none is named, then it lists them and asks" \
  'out="$("$n")"; grep -q "^feature 001-demo DONE=0/3" <<<"$out" && grep -q "^feature 002-reports DONE=0/1" <<<"$out" && [[ "$(tail -1 <<<"$out")" == "CHOOSE=001-demo 002-reports" ]]'
# F1.9: on a task branch, the branch names the feature.
git switch --quiet -c feat/001-t001-first-in-a
check "when the current branch is a task branch of one feature and another feature has tasks to start, then next prints that feature's tasks and no CHOOSE=" \
  'out="$("$n")"; grep -q "^resume T001 #1 First" <<<"$out" && grep -q "^open T003 #3 Third" <<<"$out" && ! grep -q CHOOSE <<<"$out"'
check "then an explicit argument still wins over the branch" \
  'out="$("$n" 002)"; grep -q "^open T001 #30 Report" <<<"$out" && ! grep -q "First" <<<"$out"'
git switch --quiet main; git branch --quiet -D feat/001-t001-first-in-a
check "when a feature is named, then it becomes the active one and its next task is picked" \
  'out="$("$n" 002)"; [[ "$out" == *"NEXT=T001"* ]] && grep -q "specs/002-reports" .specify/feature.json'
check "when the name matches no single feature, then it refuses" 'fails_with "no single feature" "$n" 009'
closed 30
check "when only one feature has tasks to start, then it is served without asking" \
  'out="$("$n")"; [[ "$out" == *"NEXT=T001"* ]] && ! grep -q CHOOSE <<<"$out"'
rm -rf specs/002-reports; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json; closed 1 2 3

# FR-036: every other startable [P] task gets a line that makes its worktree and claims it.
tasks3='- [ ] T001 First in `a` — #1
- [ ] T002 [P] Second in `b` — #2
- [ ] T003 Third in `c` — #3'
commit_tasks "$tasks3"'
- [ ] T006 [P] Sixth in `f` (depends on T001) — #9
- [ ] T007 [P] Seventh in `g` — #10
- [ ] T008 Eighth, not [P] itself, in `h` — #11'
closed; open_prs
top="$(git rev-parse --show-toplevel)"
par() { echo "parallel $1 (git worktree add --quiet --detach $top-001-$2 origin/develop && cd $top-001-$2 && bash .specify/extensions/landspec/scripts/branch.sh 001 $1)"; }
check "when open [P] tasks exist besides NEXT, then each gets a parallel line with its worktree and branch.sh command, and DONE= stays last" \
  'out="$("$n")"; grep -qxF "$(par T002 t002)" <<<"$out" && grep -qxF "$(par T007 t007)" <<<"$out" && [[ "$(tail -1 <<<"$out")" == "DONE=0/6 IN_PROGRESS=0 NEXT=T001" ]]'
check "then NEXT, a blocked [P] task, a task without [P] and one with [P] later in its line get no parallel line" \
  'out="$("$n")"; ! grep -qE "^parallel (T001|T003|T006|T008) " <<<"$out"'
closed 1
check "when NEXT itself is a [P] task, then it gets no parallel line and the other [P] tasks do" \
  'out="$("$n")"; [[ "$out" == *"NEXT=T002"* ]] && ! grep -q "^parallel T002 " <<<"$out" && grep -qxF "$(par T007 t007)" <<<"$out"'
# The test repo git-ignores .specify, so the new worktree runs the scripts from here.
check "when a printed parallel line is run, then the task is claimed on origin and the next run shows it in progress with no line" \
  'line="$("$n" | grep "^parallel T007 ")"; cmd="${line#parallel T007 (}"; cmd="${cmd%)}"; (eval "${cmd//bash .specify\/extensions\/landspec\/scripts/bash $SCRIPTS}") && git ls-remote --exit-code --heads origin feat/001-t007-seventh && out="$("$n")" && grep -q "^in-progress T007" <<<"$out" && ! grep -q "^parallel T007 " <<<"$out"'
git worktree remove --force "$top-001-t007" 2>/dev/null || true
git branch --quiet -D feat/001-t007-seventh 2>/dev/null || true
git push --quiet origin --delete feat/001-t007-seventh 2>/dev/null || true
commit_tasks "$tasks3"; closed 1 2 3

printf '%s\n' '- [ ] T004 Fourth in `d`' >> specs/001-demo/tasks.md
check "when a task has no issue, then it is listed as no-issue and not picked" \
  'out="$("$n")"; grep -q "^no-issue T004" <<<"$out" && [[ "$out" == *"NEXT="* && "$out" != *"NEXT=T004"* ]]'
mkdir -p specs/003-bare; printf '%s\n' '- [ ] T001 Nothing linked yet in `n`' > specs/003-bare/tasks.md
check "when no task of the feature has an issue, then no issue-state query is made" \
  ': > "$GH_LOG"; out="$("$n" 003)"; grep -q "^no-issue T001" <<<"$out" && ! grep -q "^api graphql" "$GH_LOG"'
rm -rf specs/003-bare; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

# T015: origin is fetched first, and a parallel line needs its task on the base, with its issue.
git checkout --quiet -- specs; closed; open_prs
behind="$(git rev-parse origin/develop)"
commit_tasks "$tasks3"'
- [ ] T007 [P] Seventh in `g` — #10'
git update-ref refs/remotes/origin/develop "$behind"
check "when origin/develop here is behind origin, then a printed parallel line starts the task" \
  'line="$("$n" | grep "^parallel T007 ")"; cmd="${line#parallel T007 (}"; cmd="${cmd%)}"; (eval "${cmd//bash .specify\/extensions\/landspec\/scripts/bash $SCRIPTS}") && git ls-remote --exit-code --heads origin feat/001-t007-seventh'
git worktree remove --force "$top-001-t007" 2>/dev/null || true
git branch --quiet -D feat/001-t007-seventh 2>/dev/null || true
git push --quiet origin --delete feat/001-t007-seventh 2>/dev/null || true

# #105: next stops, naming why, when it cannot see other clones' claims.
url="$(git remote get-url origin)"; git remote set-url origin "$TMP/gone.git"
check "when the fetch fails, then next stops naming the reason and git's error" \
  '! "$n" >/dev/null 2>"$TMP/err" && grep -q "^landspec: cannot fetch origin, so tasks claimed in other clones cannot be seen" "$TMP/err" && grep -q "gone.git" "$TMP/err"'
git remote set-url origin "$url"; git push --quiet origin main:refs/heads/feat/001-t001-claimed
check "when another clone claimed a task, then next shows it in progress" 'out="$("$n")"; grep -q "^in-progress T001" <<<"$out" && [[ "$out" == *"NEXT=T002" ]]'
git remote set-url origin "$TMP/gone.git"
check "when origin is then unreachable, then the claimed task is never offered as NEXT" \
  'if out="$("$n" 2>/dev/null)"; then false; fi; [[ "$out" != *"NEXT=T001"* ]]'
git remote set-url origin "$url"; git push --quiet origin --delete feat/001-t001-claimed
check "when the open pull requests cannot be listed, then next stops naming the reason and gh's error" \
  '! GH_FAIL_PR_LIST=1 "$n" >"$TMP/out" 2>"$TMP/err" && [[ ! -s "$TMP/out" ]] && grep -q "^landspec: cannot list the open pull requests" "$TMP/err" && grep -q "HTTP 502" "$TMP/err"'

# A first spec PR: the feature exists only on its spec branch.
git switch --quiet -c spec/002-new
mkdir -p specs/002-new; printf '%s\n' '- [ ] T001 [P] New in `n` — #40' '- [ ] T002 [P] Newer in `o` — #41' > specs/002-new/tasks.md
git add specs; git commit --quiet -m "docs: 002"
check "when a first spec PR is open, then its unmerged tasks get no parallel line" \
  'out="$("$n" 002)"; [[ "$out" == *"NEXT=T001"* ]] && ! grep -q "^parallel " <<<"$out"'
check "then starting NEXT refuses and pushes no branch" \
  'fails_with "merge the spec PR first" "$SCRIPTS/branch.sh" 002 T001 && ! git ls-remote --exit-code --heads origin "feat/002-*"'
git switch --quiet main; git branch --quiet -D spec/002-new; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

# A converge spec PR on a base that has tasks.md: its new tasks, and an issue added to a task the base has without one.
commit_tasks "$tasks3"'
- [ ] T007 [P] Seventh in `g` — #10
- [ ] T011 [P] Eleventh in `k`'
closed 1 3
git switch --quiet -c spec/001-converge
sed -i.bak 's/^\(- \[ \] T011 .*\)$/\1 — #21/' specs/001-demo/tasks.md
printf '%s\n' '- [ ] T009 [P] Ninth in `i` — #20' '- [ ] T010 [P] Tenth in `j` — #22' >> specs/001-demo/tasks.md
git add specs; git commit --quiet -m "docs: converge"
check "when a converge spec PR is open, then a merged task keeps its parallel line and the unmerged ones get none" \
  'out="$("$n")"; grep -q "^parallel T007 " <<<"$out" && ! grep -qE "^parallel (T009|T010) " <<<"$out"'
check "then a task whose line on the base has no issue gets no parallel line" \
  'out="$("$n")"; grep -q "^open T011 #21" <<<"$out" && ! grep -q "^parallel T011 " <<<"$out"'
closed 1 2 3 10 21
check "then starting NEXT refuses and pushes no branch" \
  '[[ "$("$n" | tail -1)" == *"NEXT=T009" ]] && fails_with "merge the spec PR first" "$SCRIPTS/branch.sh" 001 T009 && ! git ls-remote --exit-code --heads origin "feat/001-t009-*"'
git switch --quiet main; git branch --quiet -D spec/001-converge

# A named feature beats the task branch: FEATURE= carries it to the start.
closed 1 2 3 10
mkdir -p specs/002-reports; printf '%s\n' '- [ ] T001 Report in `r` — #30' > specs/002-reports/tasks.md
git add specs; git commit --quiet -m "docs: 002"; git push --quiet origin main; git push --quiet origin main:develop
active="$(cat .specify/feature.json)"
check "when one other feature is startable, then next serves it, prints FEATURE= and leaves feature.json alone" \
  'out="$("$n")"; grep -qx "FEATURE=002" <<<"$out" && [[ "$(tail -1 <<<"$out")" == *"NEXT=T001" ]] && [[ "$(cat .specify/feature.json)" == "$active" ]]'
git switch --quiet -c feat/001-t001-first-in-a
check "when next 002 runs on a 001 task branch, then its FEATURE= and NEXT= start 002's task" \
  'out="$("$n" 002)"; "$SCRIPTS/branch.sh" "$(sed -n "s/^FEATURE=//p" <<<"$out")" "${out##*NEXT=}" && [[ "$(git branch --show-current)" == feat/002-t001-report ]]'
git switch --quiet main; git branch --quiet -D feat/001-t001-first-in-a feat/002-t001-report; git push --quiet origin --delete feat/002-t001-report
check "then the next skill starts <FEATURE> <NEXT> and makes the feature active before suggesting issues" \
  'grep -qF "Run \`/speckit-implement <FEATURE> <NEXT>\`" "$ROOT/skills/next/SKILL.md" && grep -qF "next.sh <FEATURE>\` first" "$ROOT/skills/next/SKILL.md"'
rm -rf specs/002-reports; echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json

mkdir -p "$TMP/mono/apps/web/.specify" && git -C "$TMP/mono" init --quiet
check "when spec-kit lives in a subfolder of the repo, then scripts refuse instead of writing into the parent" \
  '(cd "$TMP/mono/apps/web" && fails_with "a subfolder of the repository" "$SCRIPTS/next.sh") && [[ ! -e "$TMP/mono/.specify" ]]'

exit "$FAIL"
