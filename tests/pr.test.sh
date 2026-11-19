#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
p="$SCRIPTS/pr.sh"
# range: the Reviewed: and Model: lines every task report states.
range() { printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n' "$(git merge-base HEAD origin/develop)" "$(git rev-parse HEAD)"; }
# reviewed: a ready review of HEAD that deep-checks every path review.sh risk flags.
reviewed() {
  { printf 'What changed: x\n\n'; { "$SCRIPTS/review.sh" risk 2>/dev/null || true; } | sed -n 's/^RISK=[a-z]* /- deep: /p' | sort -u
    echo; range; printf '\nAssessment: ready\n'; } > "$TMP/review.md"
  "$SCRIPTS/review.sh" record "$TMP/review.md" >/dev/null
}
scanned() { no_scanners; PATH="$TMP/none" bash "$SCRIPTS/security-scan.sh" --changed >/dev/null; }

new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'

check "when not on the task's branch, then it refuses" 'fails_with "not on T001" "$p" task T001 "feat: add search"'

"$SCRIPTS/branch.sh" T001 >/dev/null
echo 'export const search = 1' > search.ts
check "when there are uncommitted changes, then it refuses and names the files" 'fails_with "uncommitted changes; commit the work first (or git-ignore what the tests create): search.ts" "$p" task T001 "feat: add search"'
git add search.ts; git commit --quiet -m "feat(search): add search"
mkdir -p .claude/worktrees/agent-x; echo x > .claude/worktrees/agent-x/f
check "when only an untracked .claude/worktrees/agent-x/ folder is there, then it does not refuse for uncommitted changes" \
  'out="$("$p" task T001 "feat: add search" 2>&1 || true)"; [[ "$out" != *uncommitted* ]]'
rm -rf .claude

printf 'Adds search.\n\n## Review\n\nready: no findings\n\n## Evidence\n\n`npm test` passed\n' > "$TMP/body.md"
printf 'Adds search.\n\n## Evidence\n\n`npm test` passed\n' > "$TMP/unreviewed.md"
check "when no independent review was recorded for the diff, then it refuses at every level" \
  'fails_with "no independent review" "$p" task T001 "feat(search): add search" "$TMP/body.md"'
reviewed
check "when the body has no Review section, then it refuses" \
  'fails_with "Review" "$p" task T001 "feat(search): add search" "$TMP/unreviewed.md"'
check "when no scan was recorded for this diff, then it refuses and names security-scan.sh" \
  'fails_with "no security-scan.sh --changed result for this diff; run bash .specify/extensions/landspec/scripts/security-scan.sh --changed after the last commit" "$p" task T001 "feat(search): add search" "$TMP/body.md"'
scanned # with no scanner installed: every one is "missing", and that is enough
# A test command that prints 30 lines and fails: the refusal shows the last 20 (11 to 30).
mkdir -p .specify/memory
printf '#!/usr/bin/env bash\nfor i in $(seq 1 30); do echo "red line $i"; done\nexit 1\n' > "$TMP/red.sh"
printf '**Commands**: build `[BUILD_COMMAND]` · test `bash %s` · lint `[LINT_COMMAND]` · mutate `[MUTATE_COMMAND]`\n' "$TMP/red.sh" > .specify/memory/constitution.md
claim="$(git ls-remote origin "refs/heads/$(git branch --show-current)")"
red=0; out="$("$p" task T001 "feat(search): add search" "$TMP/body.md" 2>&1)" || red=$?
check "when the constitution's test command exits 1, then it refuses, prints its last 20 lines and pushes nothing" \
  '((red != 0)) && grep -qxF "landspec: the test command failed (bash $TMP/red.sh); fix it before opening the PR" <<<"$out" \
   && grep -qx "red line 30" <<<"$out" && grep -qx "red line 11" <<<"$out" && ! grep -qx "red line 10" <<<"$out" \
   && [[ "$(git ls-remote origin "refs/heads/$(git branch --show-current)")" == "$claim" ]] && ! grep -q "^pr create" "$GH_LOG" \
   && grep -qx "red line 1" "$(git rev-parse --git-common-dir)/landspec-test/feat__001-t001-add-search.log"'
check "then the red run is logged as a tests event with ok=0 before the refusal" \
  'grep -qE " feat/001-t001-add-search tests secs=[0-9]+ ok=0$" "$(git rev-parse --git-common-dir)/landspec-events"'
check "then a red run records nothing, so the next run tests again" \
  '[[ -z "$(find "$(git rev-parse --git-common-dir)/landspec-test" -type f ! -name "*.log")" ]]'
check "when a scan was recorded for this diff, then the scan check lets the PR through" \
  '! grep -q "no security-scan.sh --changed result" <<<"$out" && grep -qx "red line 30" <<<"$out"'
printf '#!/usr/bin/env bash\ntouch "%s/green.ran"\n' "$TMP" > "$TMP/green.sh"
printf '**Commands**: build `[BUILD_COMMAND]` · test `bash %s` · lint `[LINT_COMMAND]` · mutate `[MUTATE_COMMAND]`\n' "$TMP/green.sh" > .specify/memory/constitution.md
out="$("$p" task T001 "feat(search): add search" "$TMP/body.md" 2>"$TMP/pr.err")" || true
check "when the constitution's test command exits 0, then it opens the PR with no warning" \
  '[[ -f "$TMP/green.ran" && "$out" == *"PR=https://github.com/acme/app/pull/99" ]] && grep -q "^pr create" "$GH_LOG" && ! grep -q "^landspec:" "$TMP/pr.err"'
check "then the green run and the PR are logged, in that order" \
  'tail -2 "$(git rev-parse --git-common-dir)/landspec-events" | cut -d" " -f3- | tr "\n" "|" | grep -qE "^feat/001-t001-add-search tests secs=[0-9]+ ok=1\|feat/001-t001-add-search pr mode=task url=https://github.com/acme/app/pull/99\|$"'
check "then the body names each scanner that did not run" \
  'grep -qxF "Scanners not run: gitleaks (missing), osv-scanner (missing), semgrep (missing)" "$GH_LOG"'
rm -f "$TMP/green.ran"
printf '**Commands**: build `[BUILD_COMMAND]` · test `bash %s --again` · lint `[LINT_COMMAND]` · mutate `[MUTATE_COMMAND]`\n' "$TMP/green.sh" > .specify/memory/constitution.md
"$p" task T001 "feat(search): add search" "$TMP/body.md" >/dev/null 2>&1 || true
check "when the tree already passed but the test command changed, then it runs again" '[[ -f "$TMP/green.ran" ]]'
rm -f "$GH_PR"; : > "$GH_LOG" # the checks below are about the next run's PR alone
# F3.1/F4.3: the recorded review reaches the body; its findings never do, wherever the report puts them.
printf 'LEAK-1 before the marker\n\n- **What changed**: Adds LEAK-2 search.\n- **Findings**:\n  - High: LEAK-3 in src/a.ts:3\n\nSecurity: LEAK-4 token logged\n\n%s\n\nAssessment: ready\n' "$(range)" > "$TMP/review.md"
"$SCRIPTS/review.sh" record "$TMP/review.md" >/dev/null
rm .specify/memory/constitution.md
out="$("$p" task T001 "feat(search): add search" "$TMP/body.md" 2>"$TMP/pr.err")"
check "when the constitution has no test command, then it says the tests were not run and opens the PR" \
  'grep -qx "landspec: tests not run before the PR (no test command in the constitution)" "$TMP/pr.err" && [[ "$out" == *"PR=https://github.com/acme/app/pull/99" ]]'
check "when a review is recorded, then the body sent to gh pr create has the patch-id and Assessment lines, folded, before Closes" \
  'sed -n "/^pr create/,\$p" "$GH_LOG" | grep -A4 -xF "<details><summary>Independent review</summary>" | grep -xE -e "Independent review recorded for this diff \(patch id [0-9a-f]{12}\)" -e "Assessment: ready" | wc -l | grep -qx " *2" \
   && [[ "$(grep -nxF "</details>" "$GH_LOG" | tail -1 | cut -d: -f1)" -lt "$(grep -n "Closes #5" "$GH_LOG" | cut -d: -f1)" ]]'
check "then none of the report's text reaches the body" '! grep -qE "LEAK|What changed|token logged" "$GH_LOG"'
check "when the work is committed, then it pushes and opens the PR into the base" \
  '[[ "$out" == *"PR=https://github.com/acme/app/pull/99" ]] && git ls-remote --exit-code origin "$(git branch --show-current)" && grep -q -- "--base develop" "$GH_LOG"'
check "then the body links the issue with Closes #N" 'grep -q "Closes #5" "$GH_LOG"'
check "then no outside reviewer is asked for" '! grep -q "requested_reviewers" "$GH_LOG" && ! grep -qi copilot <<<"$out"'
check "then the user is assigned and no milestone or project is guessed" \
  'grep -q -- "^pr edit https://github.com/acme/app/pull/99 --add-assignee @me" "$GH_LOG" && ! grep -qE -- "--milestone|--add-project" "$GH_LOG"'

out="$("$p" task T001 "feat(search): add search" "$TMP/body.md")"
check "when the PR already exists, then it is reused, not duplicated" '[[ "$(grep -c "^pr create" "$GH_LOG")" == 1 ]]'
if command -v jq >/dev/null; then # GH_PR_JSON runs the script's own --jq
  printf '[{"url":"https://github.com/acme/app/pull/7","isCrossRepository":true}]' > "$TMP/fork.json"
  out="$(GH_PR_JSON="$TMP/fork.json" "$p" task T001 "feat(search): add search" "$TMP/body.md")"
  check "when the only open PR with this branch name is a fork's, then a new PR opens and the fork's is never edited" \
    '[[ "$(grep -c "^pr create" "$GH_LOG")" == 2 && "$out" == *"PR=https://github.com/acme/app/pull/99" ]] && ! grep -q "pull/7" "$GH_LOG"'
  printf '[{"url":"https://github.com/acme/app/pull/7","isCrossRepository":false}]' > "$TMP/own.json"
  out="$(GH_PR_JSON="$TMP/own.json" "$p" task T001 "feat(search): add search" "$TMP/body.md")"
  check "then the same PR from this repository is reused, with its body replaced" \
    '[[ "$(grep -c "^pr create" "$GH_LOG")" == 2 && "$out" == *"PR=https://github.com/acme/app/pull/7" ]] && grep -q "^pr edit https://github.com/acme/app/pull/7 --body" "$GH_LOG"'
fi

sed -i.bak 's/^level: .*/level: full/' .specify/extensions/landspec/landspec-config.yml
rm -f "$GH_PR"; printf 'No evidence here.\n' > "$TMP/thin.md"
check "when the level is full and the body has no Evidence section, then it refuses" \
  'fails_with "Evidence" "$p" task T001 "feat(search): add search" "$TMP/thin.md"'

sed -i.bak 's/^level: .*/level: standard/' .specify/extensions/landspec/landspec-config.yml
echo 'export const x = 2' >> search.ts; git commit --quiet -am "feat: more"
check "when the code changed after the review, then the PR is refused until a new review is recorded" \
  'fails_with "changed since" "$p" task T001 "feat(search): add search" "$TMP/body.md" && reviewed && scanned && "$p" task T001 "feat(search): add search" "$TMP/body.md" | grep -q "^PR="'
git switch --quiet main; rm -f "$GH_PR"
mkdir -p specs/002-new
printf '%s\n' '- [ ] T001 Thing in `a` — #11' '- [ ] T002 Other in `b` — #12' > specs/002-new/tasks.md
printf '%s\n' '- **FR-001**: the new thing MUST work.' > specs/002-new/spec.md
echo '{ "feature_directory": "specs/002-new" }' > .specify/feature.json
printf "milestone: v2\nproject: Board\n" >> .specify/extensions/landspec/landspec-config.yml # an old config's keys
plan_review claude-haiku-4-5 >/dev/null 2>&1
echo "local data" > a
check "when tasks.md names a file that is only untracked here, then the spec PR is refused before any switch" \
  'fails_with "not in git: a" "$p" spec && [[ "$(git branch --show-current)" == main ]]'
rm a
out="$("$p" spec)"
check "when the plan review's record has a model warning, then the spec PR body carries it" \
  'grep -qxF "**Plan review:** the review ran on claude-haiku-4-5; the review did not run on the configured model" "$GH_LOG"'
check "when opening the spec PR, then the spec folder is committed on spec/<feature>" \
  '[[ "$(git branch --show-current)" == spec/002-new ]] && [[ -z "$(git status --porcelain specs)" ]] && git ls-remote --exit-code origin spec/002-new'
check "then the spec PR lists the task issues" 'grep -q "#11 #12" "$GH_LOG"'
check "then it explains, folded away, why the spec is its own PR" 'grep -q "<summary>Why is the spec its own PR?</summary>" "$GH_LOG"'
check "then a milestone or project left in an old config is never set: the user is only assigned" \
  'grep -q -- "^pr edit https://github.com/acme/app/pull/99 --add-assignee @me$" "$GH_LOG" && ! grep -qE -- "--milestone|--add-project" "$GH_LOG"'
check "when the spec PR step runs again on its branch, then it reuses the branch and the PR" \
  'before="$(grep -c "^pr create" "$GH_LOG")"; "$p" spec && [[ "$(git branch --show-current)" == spec/002-new && "$(grep -c "^pr create" "$GH_LOG")" == "$before" ]]'
check "when the first spec PR was opened, then its commit says add" \
  '[[ "$(git log -1 --format=%s HEAD~0)" == "docs(specs): add 002-new spec, plan and tasks" ]]'
# #115/#116: a task added after the spec PR opened reaches its body, and the commit says update.
printf '%s\n' '- [ ] T004 Added after review in `d` — #14' >> specs/002-new/tasks.md
plan_review claude-haiku-4-5 >/dev/null 2>&1
: > "$GH_LOG"; out="$("$p" spec)"
check "when the open spec PR is updated with a new task issue, then its body is rewritten with every issue" \
  'grep -q "^pr edit https://github.com/acme/app/pull/99 --body" "$GH_LOG" && grep -q "#11 #12 #14" "$GH_LOG" && grep -qF "PR body replaced from the generated spec body" <<<"$out"'
check "then the new commit says update, not add" '[[ "$(git log -1 --format=%s)" == "docs(specs): update 002-new spec, plan and tasks" ]]'
printf '%s\n' '- [ ] T005 Outra tarefa em `e` — #15' >> specs/002-new/tasks.md
plan_review claude-haiku-4-5 >/dev/null 2>&1
"$p" spec "docs(specs): adiciona a tarefa T005" >/dev/null
check "when a title is given, then the commit uses it as written (the project's language)" \
  '[[ "$(git log -1 --format=%s)" == "docs(specs): adiciona a tarefa T005" ]]'

# The first spec PR was squash-merged (its branch is now stale), then /speckit-converge added a task.
git push --quiet --no-verify origin "spec/002-new:refs/heads/tmp-squash"
git -C "$TMP" clone --quiet "$TMP/origin.git" squash 2>/dev/null
(cd "$TMP/squash" && git config user.email t@t && git config user.name t && git switch --quiet develop \
  && git checkout --quiet origin/tmp-squash -- specs/002-new && git commit --quiet --no-verify -m "docs(specs): 002-new (#20)" \
  && git push --quiet --no-verify origin develop && git push --quiet --no-verify origin --delete tmp-squash)
git fetch --quiet origin; rm -f "$GH_PR"; git switch --quiet main
mkdir -p specs/002-new; git checkout --quiet origin/develop -- specs/002-new; git reset --quiet
printf '%s\n' '- [ ] T003 Added by converge in `c` — #13' >> specs/002-new/tasks.md
plan_review claude-haiku-4-5 >/dev/null 2>&1
"$p" spec >/dev/null
check "when a later spec PR follows a squash-merged one, then it starts fresh from the base" \
  'git merge-base --is-ancestor origin/develop HEAD && [[ "$(git branch --show-current)" == spec/002-new ]]'
check "then its commit says update: the spec is already on the base" \
  '[[ "$(git log -1 --format=%s)" == "docs(specs): update 002-new spec, plan and tasks" ]]'
check "then the new spec PR carries only what changed: the converge task" \
  '[[ "$(git diff --name-only origin/develop..HEAD)" == specs/002-new/tasks.md ]] && git diff origin/develop..HEAD | grep -q "^+- \[ \] T003 Added by converge"'

# F1.8: the spec PR is open and a teammate pushed to its branch; origin was fetched after that, so
# only the lookup (not --force-with-lease) can stop the fresh start from overwriting their commit.
git -C "$TMP" clone --quiet "$TMP/origin.git" mate 2>/dev/null
(cd "$TMP/mate" && git config user.email m@m && git config user.name m && git switch --quiet spec/002-new \
  && echo "teammate note" >> specs/002-new/tasks.md && git commit --quiet -am "docs: teammate" && git push --quiet origin spec/002-new)
mate="$(git -C "$TMP/mate" rev-parse HEAD)"; git fetch --quiet origin
out="$(GH_FAIL_PR_LIST=1 "$p" spec 2>&1)" && spec_rc=0 || spec_rc=$?
check "when gh pr list fails while the spec PR is open with a teammate's commit, then pr.sh spec exits non-zero after gh's error" \
  '((spec_rc != 0)) && grep -q "HTTP 502" <<<"$out" && grep -qxF "landspec: could not check for an open spec PR" <<<"$out"'
check "then origin's spec branch still has the teammate's commit" '[[ "$(git ls-remote origin refs/heads/spec/002-new | cut -f1)" == "$mate" ]]'

# ── Changing existing tests needs a reason ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"
new_repo standard
mkdir -p tests src; echo 'assert 1 == 1' > tests/test_price.py; echo 'x' > src/keep.test.ts
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
printf 'Adds search.\n\n## Review\n\nready: no findings\n' > "$TMP/plain.md"

echo 'assert True' > tests/test_price.py; git commit --quiet -am "feat: weaken"
check "when an existing test is edited and the body says nothing, then it refuses and names the file" \
  'fails_with "tests/test_price.py" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'
check "then no commit was pushed (origin still has only the empty claim)" \
  '[[ "$(git ls-remote origin "refs/heads/$(git branch --show-current)" | cut -f1)" == "$(git rev-parse origin/develop)" ]]'

git rm --quiet src/keep.test.ts; git commit --quiet -m "chore: drop test"; reviewed; scanned
check "when an existing test is deleted, then it refuses too" 'fails_with "src/keep.test.ts" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'

printf 'Adds search.\n\n## Review\n\nready: no findings\n\n## Test changes\n\nThe spec changed the price rule (FR-002).\n' > "$TMP/why.md"
check "when the body explains the test changes, then the PR opens" '"$p" task T001 "feat(search): add search" "$TMP/why.md" | grep -q "^PR="'

git push --quiet origin --delete "$(git branch --show-current)" 2>/dev/null || true; git reset --quiet --hard origin/develop; rm -f "$GH_PR"
mkdir -p attic; git mv tests/test_price.py attic/price_checks.py; git commit --quiet -m "chore: move"
check "when a test is moved out of the test folders, then it counts as deleted and is refused" \
  'fails_with "tests/test_price.py" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'

git branch --quiet develop origin/develop # the base exists locally...
git remote set-url origin "$TMP/no-such-remote.git"; git update-ref -d refs/remotes/origin/develop # ...but not on origin
check "when origin cannot be reached, then the check still runs against the local base branch" \
  'fails_with "existing tests were changed" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'
git remote set-url origin "$TMP/origin.git"; git fetch --quiet origin; git branch --quiet -D develop

# A fresh branch for this scenario: drop the pushed one and start again from the base.
git push --quiet origin --delete "$(git branch --show-current)" 2>/dev/null || true; git reset --quiet --hard origin/develop; rm -f "$GH_PR"
echo 'assert 2 == 2' > tests/test_new.py; git add tests/test_new.py; git commit --quiet -m "test: add"; reviewed; scanned
check "when only new tests are added, then no explanation is needed" '"$p" task T001 "feat(search): add search" "$TMP/plain.md" | grep -q "^PR="'

# ── FR-006: adding to an existing test file needs no explanation; a deletion, an edit or an added skip does ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"
new_repo standard
mkdir -p tests; printf 'check one\nexit "$FAIL"\n' > tests/a.test.sh; printf 'it("a")\n' > tests/b.test.js
printf 'one\n' > tests/xfail.test.sh; printf '\0\1' > tests/data.test.bin
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
fresh() { git push --quiet origin --delete "$(git branch --show-current)" 2>/dev/null || true; git reset --quiet --hard origin/develop; rm -f "$GH_PR"; }
opens() { git commit --quiet -am "test: change"; reviewed; scanned; "$p" task T001 "test: change" "$TMP/plain.md" | grep -q "^PR="; }
refused() { git commit --quiet -am "test: change"; fails_with "existing tests were changed: $1" "$p" task T001 "test: change" "$TMP/plain.md"; }
printf 'check one\ncheck two\nexit "$FAIL"\n' > tests/a.test.sh
check "when a test is added above a file's closing exit, then the PR opens with no Test changes section" opens; fresh
printf 'check one\nrun x || true\ncat > stub <<EOF\nexit 0\nEOF\nexit "$FAIL"\n' > tests/a.test.sh
check "when a new test holds || true and a heredoc stub with exit 0, then the PR opens with no Test changes section" opens; fresh
echo two >> tests/xfail.test.sh
check "when a line is added to a test whose path holds a skip word, then the path does not count as a skip" opens; fresh
printf 'it("a")\nit.skip("b")\n' > tests/b.test.js
check "when an added line skips a test, then it refuses and names the file" 'refused tests/b.test.js'; fresh
printf 'it("a")\n@Disabled\n' > tests/b.test.js
check "when an added skip is in another case (@Disabled), then it refuses too" 'refused tests/b.test.js'; fresh
printf 'it("changed")\n' > tests/b.test.js
check "when a line is edited, then it refuses" 'refused tests/b.test.js'; fresh
git config color.ui always; printf 'it("a")\nit("b")\n' > tests/b.test.js; git commit --quiet -am "test: more"
printf 'it("changed")\nit("b")\n' > tests/b.test.js
check "when a line is edited under color.ui=always, then it refuses" 'refused tests/b.test.js'; git config --unset color.ui; fresh
chmod +x tests/a.test.sh; echo x > other.txt; git add other.txt
check "when only a test's mode changes, then it refuses" 'refused tests/a.test.sh'; fresh
printf '\0\2' > tests/data.test.bin
check "when a binary test changes, then it refuses" 'refused tests/data.test.bin'; fresh

# ── Common test layouts count as tests, and the constitution can add one ──
layouts=$'app/tests.py\nTests/AppTests/AppTests.swift\nMyApp.Tests/FooTests.cs\ncypress/e2e/login.cy.ts\nsrc/Foo.Test.cs\nsrc/foo.spec.TS\ntests/test_a.py\nsrc/a.test.ts\n__tests__/a.js'
sources=$'src/latest.ts\nlib/contest.py\nsrc/attest.go\npkg/protest.rb\nsrc/greatest.js\nsrc/Contests.java\nsrc/Latests.cs\nsrc/utils.py\napp/Manifest.swift\nsrc/LatestRelease.swift\nsrc/specification.py\ndocs/e2e.md\nlib/testing.go'
check "the test-path pattern matches each of the 9 test layouts and none of the 13 source paths" \
  'source "$SCRIPTS/lib.sh"; [[ "$(grep -E "$TEST_PATH_RE" <<<"$layouts")" == "$layouts" && -z "$(grep -E "$TEST_PATH_RE" <<<"$sources" || true)" ]]'
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"
new_repo standard
mkdir -p app Tests/AppTests src checks
echo 'assert 1 == 1' > app/tests.py; echo 'XCTAssertEqual(1, 1)' > Tests/AppTests/AppTests.swift; echo 'x' > src/latest.ts; echo 'check 1' > checks/price.sh
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo 'pass' > app/tests.py; echo '// nothing checked' > Tests/AppTests/AppTests.swift; git commit --quiet -am "feat: weaken"; reviewed; scanned
check "when an existing app/tests.py or Tests/AppTests/AppTests.swift is edited and the body says nothing, then it refuses and names the file" \
  'fails_with "app/tests.py" "$p" task T001 "feat(search): add search" "$TMP/plain.md" && fails_with "Tests/AppTests/AppTests.swift" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'
git reset --quiet --hard origin/develop
echo 'y' > src/latest.ts; git commit --quiet -am "feat: latest"; reviewed; scanned
check "when an existing src/latest.ts is edited, then it is not taken for a test and the PR opens" \
  '"$p" task T001 "feat(search): add search" "$TMP/plain.md" | grep -q "^PR="'
echo 'check 2' > checks/price.sh; git commit --quiet -am "feat: weaken a check"; reviewed; scanned; rm -f "$GH_PR"
mkdir -p .specify/memory; printf '# Constitution\n\ntests: ^checks/\n' > .specify/memory/constitution.md
check "when the constitution adds a tests: regex, then a file it matches counts as a test" \
  'fails_with "existing tests were changed: checks/price.sh" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'
printf '# Constitution\n\ntests: ([\n' > .specify/memory/constitution.md
check "when the constitution's tests: regex is invalid, then it refuses and names it" \
  'fails_with "the constitution'"'"'s tests: regex is invalid: ([" "$p" task T001 "feat(search): add search" "$TMP/plain.md"'

# ── Mutation testing ran on this diff, when the constitution has a mutate command ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
mkdir -p src .specify/memory; echo 'export const search = 1' > src/search.ts; git add src; git commit --quiet -m "feat: search"; reviewed
mutate() { printf '**Commands**: build `[BUILD_COMMAND]` · test `[TEST_COMMAND]` · lint `[LINT_COMMAND]` · mutate `%s`\n' "$1" > .specify/memory/constitution.md; }
mutate true
check "when a mutate command is set and mutants.sh was not run on this diff, then it refuses and names mutants.sh" \
  'fails_with "no mutants.sh result for this diff; run bash .specify/extensions/landspec/scripts/mutants.sh after the last commit" "$p" task T001 "feat(search): add search" "$TMP/body.md"'
"$SCRIPTS/mutants.sh" >/dev/null; scanned
check "when mutants.sh ran on this diff, then the PR opens" '"$p" task T001 "feat(search): add search" "$TMP/body.md" | grep -q "^PR="'
echo 'export const more = 2' >> src/search.ts; git commit --quiet -am "feat: more"; reviewed; rm -f "$GH_PR"
check "when a commit follows the mutants.sh run, then it refuses again" \
  'fails_with "no mutants.sh result for this diff" "$p" task T001 "feat(search): add search" "$TMP/body.md"'
mutate false; "$SCRIPTS/mutants.sh" >/dev/null; scanned
check "when mutants.sh found survivors and Evidence does not mention them, then it refuses" \
  'fails_with "mutants.sh found surviving mutants; say in '"'"'## Evidence'"'"' why each changes nothing, or add the test that kills it" "$p" task T001 "feat(search): add search" "$TMP/body.md"'
printf 'Adds search.\n\n## Review\n\nready: no findings\n\n## Evidence\n\nOne survivor, in a log line: it changes nothing observable.\n' > "$TMP/survivor.md"
check "when Evidence says why the survivor changes nothing, then the PR opens" \
  '"$p" task T001 "feat(search): add search" "$TMP/survivor.md" | grep -q "^PR="'
{ cat "$TMP/survivor.md"; seq 1 20000; } > "$TMP/long.md"; rm -f "$GH_PR"
check "when Evidence explains the survivor and runs on past the pipe buffer, then the PR opens" \
  '"$p" task T001 "feat(search): add search" "$TMP/long.md" | grep -q "^PR="'
mutate no-such-mutator; "$SCRIPTS/mutants.sh" >/dev/null; rm -f "$GH_PR"
check "when the mutate command could not run, then it refuses naming it, whatever Evidence says of survivors" \
  'fails_with "the mutate command could not run (no-such-mutator)" "$p" task T001 "feat(search): add search" "$TMP/survivor.md"'
rm .specify/memory/constitution.md; rm -f "$GH_PR"; : > "$GH_LOG"
check "when there is no mutate command, then the body says mutation testing was not run" \
  '"$p" task T001 "feat(search): add search" "$TMP/body.md" | grep -q "^PR=" && grep -qxF "Mutation testing: not run (no mutate command in the constitution)" "$GH_LOG"'

# ── FR-030–FR-033: the review block carries the record's facts: model, warning, both risk maps ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"; : > "$GH_LOG"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
mkdir -p db/migrations; echo 'DROP TABLE users;' > db/migrations/002_drop.sql; git add db; git commit --quiet -m "feat: drop"; h1="$(git rev-parse HEAD)"
printf 'What changed: x\n\n- deep: db/migrations/002_drop.sql — PROSE-1 drops users: checked the backup\n\n%s\n\nAssessment: changes needed\n' "$(range)" > "$TMP/review.md"
"$SCRIPTS/review.sh" record "$TMP/review.md" >/dev/null 2>&1 || true
echo 'DROP TABLE orders;' >> db/migrations/002_drop.sql; git commit --quiet -am "fix: drop orders"
printf 'What changed: y\n\n- deep: db/migrations/002_drop.sql — PROSE-2 second drop\n\nDelta from: %s\nReviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$h1" "$h1" "$(git rev-parse HEAD)" > "$TMP/review.md"
CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 "$SCRIPTS/review.sh" record --delta "$TMP/review.md" >/dev/null 2>&1 || true
scanned; "$p" task T001 "feat: drop" "$TMP/body.md" >/dev/null 2>&1 || true
body="$(sed -n "/^pr create/,\$p" "$GH_LOG")"
check "after a delta, then the PR body lists both labeled risk maps, as paths" \
  'grep -A1 -xF "Risk map (round 1)" <<<"$body" | grep -qxF -- "- deep: db/migrations/002_drop.sql" && grep -A1 -xF "Risk map (fix round)" <<<"$body" | grep -qxF -- "- deep: db/migrations/002_drop.sql"'
check "when the record was made with CLAUDE_CODE_SUBAGENT_MODEL_FORCE set, then the PR body has the model and the warning, though pr.sh ran without it" \
  'grep -qxF "Model: claude-sonnet-4-7" <<<"$body" && grep -qxF "warning: CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set; the review did not run on the configured model" <<<"$body"'
check "then no risk-map prose reaches the PR body" '[[ -n "$body" ]] && ! grep -q PROSE "$GH_LOG"'
printf 'What changed: x\n\n- deep: db/migrations/002_drop.sql\n\n%s\n\nAssessment: ready\n' "$(range | sed 's/^Model: .*/Model: claude-sonnet-4-8/')" > "$TMP/review.md"
"$SCRIPTS/review.sh" record "$TMP/review.md" >/dev/null 2>&1 || true; rm -f "$GH_PR"; : > "$GH_LOG"
"$p" task T001 "feat: drop" "$TMP/body.md" >/dev/null 2>&1 || true
check "when Model: is outside the configured family, then the warning reaches the PR body from the record" \
  'grep -qxF "warning: the review ran on claude-sonnet-4-8, not opus; the review did not run on the configured model" "$GH_LOG"'

# ── FR-009: the diff id ignores the user's git config ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"
new_repo standard
seq 1 40 | sed '4s/.*//; 16s/.*//' > big.txt; echo one > a.conv; printf '*.conv diff=conv\n' > .gitattributes
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
sed -i.bak '5s/.*/five/; 15s/.*/fifteen/' big.txt; rm big.txt.bak; mkdir sub
git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),sub"; git add big.txt; git commit --quiet -m "feat: edit"
printf '#!/usr/bin/env bash\necho same\n' > "$TMP/same.sh"; chmod +x "$TMP/same.sh"
lib_id() { (source "$SCRIPTS/lib.sh"; diff_id); }
# config_case <key> <value> <edit>: with the key set, the id is the one without it, and a commit
# (whose change the key would hide) after a ready review makes pr.sh refuse.
config_case() {
  git config "$1" "$2"; reviewed
  on="$(lib_id)"; git config --unset "$1"; off="$(lib_id)"; git config "$1" "$2"
  eval "$3"; git commit --quiet -am "chore: $1"
  check "with $1 set, then the diff id is the one without it, and a commit after a ready review makes pr.sh refuse" \
    '[[ -n "$on" && "$on" == "$off" ]] && fails_with "changed since" "$p" task T001 "feat: edit" "$TMP/body.md"'
  git config --unset "$1"
}
config_case color.ui always 'echo a >> big.txt'
config_case diff.external "$TMP/same.sh" 'echo b >> big.txt'
config_case diff.conv.textconv "$TMP/same.sh" 'echo two > a.conv'
config_case diff.ignoreSubmodules all 'git update-index --cacheinfo "160000,$(git rev-parse HEAD~1),sub"'
config_case diff.interHunkContext 20 'echo c >> big.txt'
config_case diff.suppressBlankEmpty true 'echo d >> big.txt'

# A shallow clone that lost the merge base stops at once: an empty id would pass for an empty diff.
shallow_repo
check "on a --depth 1 clone with no merge base, then pr.sh task prints one refusal naming git fetch --unshallow and opens nothing" \
  ': > "$GH_LOG"; one_refusal "git fetch --unshallow" "$p" task T001 "feat: edit" "$TMP/body.md" && ! grep -q "^pr create" "$GH_LOG"'
cd "$TMP"

# ── FR-009: an open task PR stays true to its diff ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"; : > "$GH_LOG"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
mkdir -p .specify/memory; printf 'echo run >> "%s/runs"\n' "$TMP" > "$TMP/count.sh"; : > "$TMP/runs"
printf '**Commands**: build `[BUILD_COMMAND]` · test `bash %s` · lint `[LINT_COMMAND]` · mutate `[MUTATE_COMMAND]`\n' "$TMP/count.sh" > .specify/memory/constitution.md
echo 'export const search = 1' > search.ts; git add search.ts; git commit --quiet -m "feat: search"; reviewed; scanned
"$p" task T001 "feat: search" "$TMP/body.md" >/dev/null 2>&1
echo 'export const more = 2' >> search.ts; git commit --quiet -am "feat: more"; reviewed; scanned
printf 'gitleaks     missing   install: x\nosv-scanner  ok        none\nsemgrep      failed    exit 2: code patterns not scanned\n' > "$(source "$SCRIPTS/lib.sh"; diff_record landspec-security)"
id2="$(source "$SCRIPTS/lib.sh"; diff_id | cut -c1-12)"; : > "$GH_LOG"
out="$("$p" task T001 "feat: search" "$TMP/body.md")"
check "when a new commit changes the tree, then the test command runs again" '[[ "$(wc -l < "$TMP/runs")" -eq 2 ]]'
check "then a failed scanner is named in the body next to a missing one" 'grep -qxF "Scanners not run: gitleaks (missing), semgrep (failed)" "$GH_LOG"'
out="$("$p" task T001 "feat: search" "$TMP/body.md")"
check "when this tree already passed this test command, then it is not run again and pr.sh says so" \
  '[[ "$(wc -l < "$TMP/runs")" -eq 2 ]] && grep -qxF "landspec: tests already green for this tree (bash $TMP/count.sh)" <<<"$out"'
echo 'export const wip = 3' >> search.ts
check "when the tree has uncommitted changes on top of a green one, then run_tests runs the command again" \
  '(source "$SCRIPTS/lib.sh"; run_tests) && [[ "$(wc -l < "$TMP/runs")" -eq 3 ]]'
git checkout --quiet -- search.ts
git worktree add --quiet --detach "$TMP/copy2" HEAD; cp -R .specify "$TMP/copy2/" # ignored, so not checked out
check "when another copy of the repo has a tree tested green elsewhere, then run_tests there does not run it again" \
  '(cd "$TMP/copy2" && source "$SCRIPTS/lib.sh" && run_tests) && [[ "$(wc -l < "$TMP/runs")" -eq 3 ]]'
git worktree remove --force "$TMP/copy2"
check "when pr.sh task runs again on an open PR, then the body is updated to the new patch id and no PR is created" \
  'grep -q "^pr edit https://github.com/acme/app/pull/99 --body " "$GH_LOG" && grep -qxF "Independent review recorded for this diff (patch id $id2)" "$GH_LOG" && ! grep -q "^pr create" "$GH_LOG"'
check "then it prints that the body was replaced from the author's file" 'grep -qxF "PR body replaced from $TMP/body.md; edits made on GitHub are gone" <<<"$out"'
edit_rc=0; out="$(GH_FAIL_EDIT=1 "$p" task T001 "feat: search" "$TMP/body.md" 2>"$TMP/pr.err")" || edit_rc=$?
check "when the edit fails, then it prints one refusal naming the PR and no PR= line" \
  '((edit_rc != 0)) && [[ "$(wc -l < "$TMP/pr.err")" -eq 1 ]] && grep -q "^landspec: .*https://github.com/acme/app/pull/99" "$TMP/pr.err" && ! grep -q "^PR=" <<<"$out"'
list_rc=0; out="$(GH_FAIL_PR_LIST=1 "$p" task T001 "feat: search" "$TMP/body.md" 2>&1)" || list_rc=$?
check "when the open-PR lookup fails, then it stops after gh's error and creates no PR" \
  '((list_rc != 0)) && grep -q "HTTP 502" <<<"$out" && grep -qxF "landspec: could not check for an open PR" <<<"$out" && ! grep -q "^PR=" <<<"$out" && ! grep -q "^pr create" "$GH_LOG"'
printf 'What changed: x\n\n- deep: ghp_abc123\n- deep: Token=abc\n- deep: search.ts\n\n%s\n\nAssessment: ready\n' "$(range)" > "$TMP/review.md"
"$SCRIPTS/review.sh" record "$TMP/review.md" >/dev/null 2>&1; : > "$GH_LOG"
"$p" task T001 "feat: search" "$TMP/body.md" >/dev/null
check "when a report's map names a token outside the diff, then it never reaches the body, and a path in the diff does" \
  '! grep -qE "ghp_abc123|Token=abc" "$GH_LOG" && grep -qxF -- "- deep: search.ts" "$GH_LOG"'

# ── A stale plan review stops pr.sh spec ──
git switch --quiet main; rm -f "$GH_PR"; : > "$GH_LOG"
check "when no plan review was recorded, then pr.sh spec stops and opens nothing" \
  'fails_with "no independent review" "$p" spec && ! grep -q "^pr create" "$GH_LOG"'
plan_review >/dev/null
printf '%s\n' '- [ ] T002 Added by analysis in `b`' >> specs/001-demo/tasks.md
printf '## Specification Analysis Report\n\nCoverage Summary Table\n' > "$TMP/analysis.md"; "$SCRIPTS/analyzed.sh" "$TMP/analysis.md" >/dev/null
check "when the analysis changed tasks.md after the plan review, then pr.sh spec stops, pushes nothing and stays on the branch" \
  'fails_with "changed since the last review" "$p" spec && ! grep -q "^pr create" "$GH_LOG" && [[ "$(git branch --show-current)" == main ]] && ! git ls-remote --exit-code origin spec/001-demo'
git checkout --quiet -- specs/001-demo/tasks.md
areas="$(git rev-parse --git-common-dir)/landspec-review/plan-001-demo.areas"; echo "due tasks" > "$areas"
check "when the ready plan has a Simplify question open, then pr.sh spec stops and opens nothing" \
  'fails_with "a Simplify question is open for tasks" "$p" spec && ! grep -q "^pr create" "$GH_LOG" && ! git ls-remote --exit-code origin spec/001-demo'
rm "$areas"

# ── FR-022: the review gate and the refusals, found by their messages, on a scan recorded for the diff ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"; : > "$GH_LOG"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo 'export const search = 1' > search.ts; git add search.ts; git commit --quiet -m "feat: search"
scanned # the scan is there from the start, so only the check under test can refuse
branch="$(git branch --show-current)"
# unopened: nothing was pushed past the claim and no PR was created.
unopened() { ! grep -q "^pr create" "$GH_LOG" && [[ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" == "$(git rev-parse origin/develop)" ]]; }
check "when the body has no '## Review' section, then it refuses with that message and opens nothing" \
  'fails_with "landspec: the PR body needs a '"'"'## Review'"'"' section: the independent review'"'"'s findings and what was done about them" "$p" task T001 "feat: search" "$TMP/unreviewed.md" && unopened'
set_cfg base_branch nosuch
check "when the base branch is on neither the machine nor origin, then it refuses naming it and opens nothing" \
  'fails_with "landspec: base branch '"'"'nosuch'"'"' not found locally or on origin" "$p" task T001 "feat: search" "$TMP/body.md" && unopened'
set_cfg base_branch auto
mkdir -p .specify/memory; printf '# Constitution\n\ntests: ([\n' > .specify/memory/constitution.md
check "when the constitution's tests: regex is invalid, then it refuses with the regex in the message and opens nothing" \
  'fails_with "landspec: the constitution'"'"'s tests: regex is invalid: ([" "$p" task T001 "feat: search" "$TMP/body.md" && unopened'
rm .specify/memory/constitution.md
check "when no review was recorded for the diff, then it refuses saying so and opens nothing" \
  'fails_with "landspec: no independent review recorded for this branch'"'"'s diff" "$p" task T001 "feat: search" "$TMP/body.md" && unopened'
printf 'What changed: x\n\n%s\n\nAssessment: changes needed\n' "$(range)" > "$TMP/review.md"
"$SCRIPTS/review.sh" record "$TMP/review.md" >/dev/null
check "when the recorded review said changes needed, then it refuses saying so and opens nothing" \
  'fails_with "landspec: the last review said '"'"'changes needed'"'"'" "$p" task T001 "feat: search" "$TMP/body.md" && unopened'
reviewed
echo 'export const more = 2' >> search.ts; git commit --quiet -am "feat: more"; scanned
check "when a commit follows a ready review (the scan is current), then it refuses with changed since and opens nothing" \
  'fails_with "landspec: this branch'"'"'s diff changed since the last review" "$p" task T001 "feat: search" "$TMP/body.md" && unopened'
reviewed
out="$("$p" task T001 "feat: search" "$TMP/body.md")"
check "when the review is ready and current, then it pushes HEAD itself: origin's branch is the commit being reviewed" \
  '[[ "$out" == *"PR=https://github.com/acme/app/pull/99" ]] && grep -q "^pr create" "$GH_LOG" && [[ "$(git ls-remote origin "refs/heads/$branch" | cut -f1)" == "$(git rev-parse HEAD)" ]]'

# fake_gh: pr list --head <branch> answers only for the branch the PR was created for.
check "when a PR was created for a branch, then pr list --head names it for that branch and prints nothing for another" \
  '[[ "$(gh pr list --head "$branch" --state open --json url)" == https://github.com/acme/app/pull/99 && -z "$(gh pr list --head other --state open --json url)" ]]'

# ── The spec folder survives a refused branch switch ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"
new_repo standard
echo a > app.txt; git add app.txt; git commit --quiet -m app; git push --quiet origin main; git push --quiet origin main:develop
echo b > app.txt; git add app.txt; git commit --quiet -m app2   # local only: HEAD differs from origin/develop...
echo c > app.txt                                                  # ...and an unstaged edit on top: git switch refuses
printf '%s\n' '- [ ] T001 Thing in `a` — #11' > specs/001-demo/tasks.md; printf 'draft\n- **FR-001**: x\n' > specs/001-demo/spec.md
plan_review >/dev/null
check "when the switch to the spec branch is refused, then it fails and the spec folder is put back untouched" \
  'fails_with "put back" "$p" spec && [[ "$(cat specs/001-demo/spec.md)" == "draft"$'"'"'\n'"'"'"- **FR-001**: x" && "$(cat specs/001-demo/tasks.md)" == *"#11" && "$(git branch --show-current)" == main ]]'

# ── A PR that is not a task (pr.sh fix): the same review gate, at every level, without an issue ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR"; : > "$GH_LOG"
new_repo lite
rm .specify/feature.json # a small fix belongs to no feature
check "when pr.sh fix runs on the base branch, then it refuses" 'fails_with "never a base branch" "$p" fix "fix: typo" "$TMP/body.md"'
git switch --quiet -c fix/typo
echo typo > typo.txt; git add typo.txt; git commit --quiet -m "fix: typo"
check "when a fix PR has no recorded review (level lite), then it refuses" \
  'fails_with "no independent review" "$p" fix "fix: typo" "$TMP/body.md" && ! grep -q "^pr create" "$GH_LOG"'
check "when pr.sh fix has no body file, then it refuses with its usage" 'fails_with "usage: pr.sh fix" "$p" fix "fix: typo"'
range() { printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n' "$(git merge-base HEAD origin/main)" "$(git rev-parse HEAD)"; }
reviewed; scanned
out="$("$p" fix "fix: typo" "$TMP/body.md" 2>/dev/null)" || true
check "when it was reviewed and scanned, then it opens the PR into the base, with the review block and no Closes line" \
  '[[ "$out" == *"PR=https://github.com/acme/app/pull/99" ]] && grep -q "^pr create --base main --head fix/typo" "$GH_LOG" \
   && grep -q "Independent review" "$GH_LOG" && ! grep -q "Closes #" "$GH_LOG"'

# ── Spec 004 T003: a stacked task's PR goes into its parent, as a draft ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5
- [ ] T002 Add filters in `src/filters.ts` — #6'
P=feat/001-t001-add-search; C=feat/001-t002-add-filters
range() { printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n' "$(git merge-base HEAD origin/develop)" "$(git rev-parse HEAD)"; }
"$SCRIPTS/branch.sh" T001 >/dev/null 2>&1
mkdir -p .github/workflows; printf 'on:\n  pull_request:\n    branches: [develop]\njobs: {}\n' > .github/workflows/w.yml
echo 'export const search = 1' > search.ts; git add search.ts .github; git commit --quiet -m "feat: search"
reviewed; scanned
"$SCRIPTS/branch.sh" T002 --from "$P" >/dev/null 2>&1
echo 'export const f = 1' > filters.ts; git add filters.ts; git commit --quiet -m "feat: filters"
range() { printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n' "$(git merge-base HEAD "$P")" "$(git rev-parse HEAD)"; }
reviewed; scanned
printf 'Adds filters.\n\n## Review\n\nready\n\n## Evidence\n\nran\n' > "$TMP/body.md"
check "when the parent has no PR yet, then the stacked PR refuses" \
  'fails_with "open the PR of $P first" "$p" task T002 "feat: filters" "$TMP/body.md" && ! grep -q "^pr create" "$GH_LOG"'
parent_pr() { echo "https://github.com/acme/app/pull/98" > "$GH_PR"; echo "$P" > "$GH_PR.head"; : > "$GH_LOG"; }
parent_pr
out="$("$p" task T002 "feat: filters" "$TMP/body.md" 2>"$TMP/pr.err")" || true
check "when the parent has a PR, then the stacked PR is a draft into the parent, with the Stacked on line" \
  'grep -q "^pr create --draft --base $P --head $C" "$GH_LOG" && grep -q "Stacked on #98 (merge it first)" "$GH_LOG" && [[ "$out" == *PR=* ]]'
check "then a workflow whose pull_request branches leave out the parent is warned about" \
  'grep -qxF "landspec: warning: .github/workflows/w.yml never runs on a PR into $P: its pull_request branches filter it out" "$TMP/pr.err"'
parent_pr
out="$(GH_NO_DRAFT=1 "$p" task T002 "feat: filters" "$TMP/body.md" 2>"$TMP/pr.err")" || true
check "when gh refuses --draft, then a normal PR opens with the drafts warning" \
  'grep -q "^pr create --base $P --head $C" "$GH_LOG" && grep -qxF "landspec: warning: drafts are not available: merge #98 first, and only after this PR'"'"'s review is current" "$TMP/pr.err" && [[ "$out" == *PR=* ]]'
git switch --quiet "$P"; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
range() { printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n' "$(git merge-base HEAD origin/develop)" "$(git rev-parse HEAD)"; }
"$p" task T001 "feat: search" "$TMP/body.md" >/dev/null 2>"$TMP/pr.err" || true
check "when the branch is not stacked, then its PR goes into the base, not as a draft, with no filter warning and no Stacked line" \
  'grep -q "^pr create --base develop --head $P" "$GH_LOG" && ! grep -q -- "--draft" "$GH_LOG" && ! grep -q "never runs" "$TMP/pr.err" && ! grep -q "Stacked on" "$GH_LOG"'
git switch --quiet "$C"; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
f="$(ls -d specs/001-*)"; echo '- [ ] T003 Add sort in `src/sort.ts`' >> "$f/tasks.md"
plan_review >/dev/null 2>&1
"$p" spec >/dev/null 2>"$TMP/pr.err" || true
check "when pr.sh spec runs on a stacked task branch, then the spec branch starts from the base, with none of the parent's commits" \
  's="$(git rev-parse --verify --quiet "refs/heads/spec/$(basename "$f")")" && [[ "$(git merge-base "$s" "$P")" == "$(git merge-base origin/develop "$P")" ]] && ! git merge-base --is-ancestor "$(git rev-parse "$P")" "$s"'

# ── Spec 006 T006: with aws: on, an infrastructure diff needs its Terraform plan recorded ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
fake_terraform
printf '{"format_version": "1.2", "planned_values": {}, "resource_changes": [{"address": "aws_s3_bucket.logs", "type": "aws_s3_bucket", "change": {"actions": ["delete"]}}, {"address": "aws_vpc.main", "type": "aws_vpc", "change": {"actions": ["create"]}}]}\n' > "$TMP/plan.json"
printf '  # aws_s3_bucket.logs will be destroyed\n\n  # aws_vpc.main will be created\n\nPlan: 1 to add, 0 to change, 1 to destroy.\n' > "$TMP/plan.txt" # the same plan, where python3 is missing
export TF_PLAN_JSON="$TMP/plan.json" TF_PLAN_TEXT="$TMP/plan.txt"
later() { local s=$(($(date +%s) + 2)); touch -d "@$s" "$1" 2>/dev/null || touch -t "$(date -r "$s" +%Y%m%d%H%M.%S)" "$1"; }
new_repo standard
echo tfplan >> .gitignore
commit_tasks '- [ ] T001 Add infra in `infra/main.tf` — #5'
printf 'aws: on\n' >> .specify/extensions/landspec/landspec-config.yml
"$SCRIPTS/branch.sh" T001 >/dev/null
mkdir infra; echo 'resource "aws_s3_bucket" "logs" {}' > infra/main.tf; git add infra; git commit --quiet -m "feat: infra"
reviewed; scanned
check "when aws is on, the level standard and the diff touches infra/main.tf with no plan recorded, then it refuses and opens nothing" \
  'fails_with "landspec: no Terraform plan recorded for this diff; run terraform plan -out=tfplan in infra, then bash .specify/extensions/landspec/scripts/tfplan.sh record tfplan" "$p" task T001 "feat: infra" "$TMP/body.md" && ! grep -q "^pr create" "$GH_LOG"'
echo plan > infra/tfplan; later infra/tfplan; (cd infra && bash "$SCRIPTS/tfplan.sh" record tfplan >/dev/null)
"$p" task T001 "feat: infra" "$TMP/body.md" >/dev/null 2>&1 || true
check "after tfplan.sh record, then the body has ## Terraform plan with the stateful lines before the counts" \
  'grep -qx "## Terraform plan" "$GH_LOG" && grep -qx "### infra" "$GH_LOG" \
   && [[ "$(grep -nxF "**Destroys or replaces stateful resources:**" "$GH_LOG" | cut -d: -f1)" -lt "$(grep -nx "create 1 · destroy 1" "$GH_LOG" | cut -d: -f1)" ]] \
   && grep -qx -- "- destroy \`aws_s3_bucket.logs\`" "$GH_LOG" && ! grep -q aws_vpc "$GH_LOG"'
rm -f "$GH_PR"; : > "$GH_LOG"
echo 'resource "aws_vpc" "main" {}' >> infra/main.tf; git commit --quiet -am "feat: vpc"; reviewed; scanned
check "when a new commit follows the plan, then it refuses again" 'fails_with "no Terraform plan recorded for this diff" "$p" task T001 "feat: infra" "$TMP/body.md"'
printf 'infra_dir: deploy\n' >> .specify/extensions/landspec/landspec-config.yml
check "then the refusal names infra_dir as the folder to plan in" 'fails_with "run terraform plan -out=tfplan in deploy, then" "$p" task T001 "feat: infra" "$TMP/body.md"'
set_cfg aws off
"$p" task T001 "feat: infra" "$TMP/body.md" >/dev/null 2>&1 || true
check "when aws is off, then the same diff opens with no plan and no Terraform section" 'grep -q "^pr create" "$GH_LOG" && ! grep -q "Terraform plan" "$GH_LOG"'

# ── Spec 006 T009: a diff of infrastructure code that is not Terraform says the plan gate was skipped ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
new_repo standard
commit_tasks '- [ ] T001 Add the stack in `cdk/cdk.json` — #5'
printf 'aws: on\n' >> .specify/extensions/landspec/landspec-config.yml
"$SCRIPTS/branch.sh" T001 >/dev/null
# swap <path>...: the branch's one commit now adds exactly these files, reviewed and scanned again.
swap() { git reset --quiet --hard "$(git merge-base HEAD origin/develop)"; local f; for f; do mkdir -p "$(dirname "$f")"; echo x > "$f"; done
  git add -- "$@"; git commit --quiet -m "feat: stack"; git push --quiet --force origin HEAD 2>/dev/null; reviewed; scanned; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"; }
for f in cdk/cdk.json stack/Pulumi.dev.yaml deploy/app.template.yaml; do
  swap "$f"
  "$p" task T001 "feat: stack" "$TMP/body.md" >/dev/null 2>&1 || true
  check "when aws is on, the level standard and the diff has only $f, then the PR opens and its body says the plan gate was skipped, naming it" \
    'grep -q "^pr create" "$GH_LOG" && grep -qx "## Terraform plan" "$GH_LOG" && grep -qxF "Skipped: this diff changes infrastructure code that is not Terraform ($f); the plan gate covers Terraform only." "$GH_LOG"'
done
swap infra/main.tf cdk.json
check "when the diff has infra/main.tf and cdk.json with no plan recorded, then it refuses and opens nothing" \
  'fails_with "landspec: no Terraform plan recorded for this diff" "$p" task T001 "feat: stack" "$TMP/body.md" && ! grep -q "^pr create" "$GH_LOG"'
swap src/app.py
printf 'infra_dir: .\n' >> .specify/extensions/landspec/landspec-config.yml
"$p" task T001 "feat: stack" "$TMP/body.md" >/dev/null 2>&1 || true
check "when the diff has only src/app.py, with infra_dir ., then the PR opens with no Terraform section" 'grep -q "^pr create" "$GH_LOG" && ! grep -q "Terraform plan" "$GH_LOG"'
swap cdk/cdk.json; set_cfg aws off
"$p" task T001 "feat: stack" "$TMP/body.md" >/dev/null 2>&1 || true
check "when aws is off and the diff has cdk/cdk.json, then the PR opens with no Terraform section" 'grep -q "^pr create" "$GH_LOG" && ! grep -q "Terraform plan" "$GH_LOG"'

# ── Spec 007 T010: pr.sh state reads a PR's conflict, CI and Copilot state, and answers Copilot's threads ──
check "when pr.sh state has no PR number, then it prints its usage" 'fails_with "usage: pr.sh state <pr> [--reply <thread id> [<file>]]" "$p" state'
check "when pr.sh state gets a PR that is not a number, then it prints its usage" 'fails_with "usage: pr.sh state" "$p" state abc'
if ! command -v jq >/dev/null; then echo "skip - pr.sh state checks need jq (the fake gh runs the script's own --jq)"
else
export GH_STATE="$TMP/state.json"
cop=copilot-pull-request-reviewer
# st <mergeable> [rollup] [requests] [reviews] [comments] [threads]: GitHub's JSON answer to the PR query
st() { printf '{"data":{"repository":{"pullRequest":{"headRefOid":"h1","mergeable":"%s","commits":{"nodes":[{"commit":{"oid":"h1","statusCheckRollup":%s}}]},"reviewRequests":{"nodes":[%s]},"reviews":{"nodes":[%s]},"comments":{"nodes":[%s]},"reviewThreads":{"nodes":[%s]}}}}}\n' \
  "$1" "${2:-null}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" > "$GH_STATE"; }
ctx() { printf '{"contexts":{"nodes":[%s]}}' "$1"; }
crun() { printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "$3"; }
sctx() { printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"; }
req() { printf '{"requestedReviewer":{"login":"%s"}}' "$1"; }
rev() { printf '{"author":{"login":"%s"},"commit":{"oid":"h1"},"body":"%s","submittedAt":"%s"}' "$1" "$2" "$3"; }
com() { printf '{"author":{"login":"%s"},"body":"%s","createdAt":"%s"}' "$1" "$2" "$3"; }
# th <n> <isResolved> <isOutdated> <line> <originalLine> <login>...: thread PRRT_<n> on src/f<n>.ts, one comment per login (ids <n>00, <n>01, ...)
th() {
  local n=$1 r=$2 o=$3 l=$4 ol=$5 c="" k=0 a; shift 5
  for a in "$@"; do c+="${c:+,}{\"author\":{\"login\":\"$a\"},\"databaseId\":$n$((k / 10))$((k % 10)),\"body\":\"$a on f$n\\nsecond line\"}"; k=$((k + 1)); done
  printf '{"id":"PRRT_%s","isResolved":%s,"isOutdated":%s,"path":"src/f%s.ts","line":%s,"originalLine":%s,"comments":{"nodes":[%s]}}' "$n" "$r" "$o" "$n" "$l" "$ol" "$c"
}
line() { "$p" state 12 | grep "^$1="; }
quota="Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota. Try requesting a review at a lower effort level."
report="$(git rev-parse --git-common-dir)/landspec-review/copilot-12"

st MERGEABLE;   check "when the PR is MERGEABLE, then CONFLICT=no" '[[ "$(line CONFLICT)" == CONFLICT=no ]]'
st CONFLICTING; check "when the PR is CONFLICTING, then CONFLICT=yes" '[[ "$(line CONFLICT)" == CONFLICT=yes ]]'
st UNKNOWN;     check "when GitHub has not computed it (UNKNOWN), then CONFLICT=unknown" '[[ "$(line CONFLICT)" == CONFLICT=unknown ]]'

st MERGEABLE "$(ctx "$(crun test IN_PROGRESS null),$(crun lint COMPLETED '"FAILURE"')")"
check "when one check run is in progress beside a failed one, then CI=pending" '[[ "$(line CI)" == CI=pending ]]'
st MERGEABLE "$(ctx "$(crun lint COMPLETED '"SUCCESS"'),$(sctx ci/x PENDING)")"
check "when a status context is pending, then CI=pending" '[[ "$(line CI)" == CI=pending ]]'
st MERGEABLE "$(ctx "$(crun test COMPLETED '"FAILURE"'),$(crun macos COMPLETED '"CANCELLED"'),$(crun lint COMPLETED '"SUCCESS"')")"
check "when a run failed and one was cancelled, then CI=fail names both with their conclusion" '[[ "$(line CI)" == "CI=fail test (FAILURE),macos (CANCELLED)" ]]'
st MERGEABLE "$(ctx "$(crun a COMPLETED '"TIMED_OUT"'),$(crun b COMPLETED '"ACTION_REQUIRED"'),$(crun c COMPLETED '"STARTUP_FAILURE"'),$(sctx ci/x ERROR),$(sctx ci/y FAILURE)")"
check "when runs timed out, need action or failed to start and statuses errored or failed, then CI=fail names each" \
  '[[ "$(line CI)" == "CI=fail a (TIMED_OUT),b (ACTION_REQUIRED),c (STARTUP_FAILURE),ci/x (error),ci/y (failure)" ]]'
st MERGEABLE "$(ctx "$(crun test COMPLETED '"SUCCESS"'),$(crun docs COMPLETED '"SKIPPED"'),$(crun opt COMPLETED '"NEUTRAL"'),$(sctx ci/x SUCCESS)")"
check "when every check succeeded (or was skipped or neutral), then CI=pass" '[[ "$(line CI)" == CI=pass ]]'
st MERGEABLE null;        check "when the head has no check at all, however recent the push, then CI=none (never waited for)" '[[ "$(line CI)" == CI=none ]]'
st MERGEABLE "$(ctx "")"; check "when the rollup has no context, then CI=none" '[[ "$(line CI)" == CI=none ]]'

st MERGEABLE null "$(req $cop)"
check "when a Copilot review request is open and no review yet, then COPILOT=pending" '[[ "$(line COPILOT)" == COPILOT=pending ]]'
st MERGEABLE null "$(req octocat)"
check "when only a user's review is requested, then COPILOT=none" '[[ "$(line COPILOT)" == COPILOT=none ]]'
st MERGEABLE null "$(req Copilot)" "$(rev $cop "" 2026-01-01T00:00:00Z)" "" "$(th 1 false false 10 10 $cop),$(th 2 false false 3 3 $cop)"
check "when a Copilot request is open beside unanswered threads, then COPILOT=pending still" '[[ "$(line COPILOT)" == COPILOT=pending ]]'
st MERGEABLE null "" "" "$(com $cop "$quota" 2026-01-02T00:00:00Z)"
check "when Copilot's newest comment says it was unable to review, with nothing open, then COPILOT=unavailable and its first sentence" \
  '[[ "$(line COPILOT)" == "COPILOT=unavailable Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota." ]]'
st MERGEABLE null "" "$(rev $cop "" 2026-01-01T00:00:00Z)" "$(com $cop "$quota" 2026-01-02T00:00:00Z)" "$(th 1 false false 10 10 $cop),$(th 2 false false 3 3 $cop)"
check "when the same comment follows a review whose two Copilot threads are unanswered, then COPILOT=comments 2, not unavailable" \
  '[[ "$(line COPILOT)" == "COPILOT=comments 2 REPORT=$report" ]]'
st MERGEABLE null "" "$(rev $cop "" 2026-01-03T00:00:00Z)" "$(com $cop "$quota" 2026-01-02T00:00:00Z)"
check "when a Copilot review is newer than its unable-to-review comment, then COPILOT=clean" '[[ "$(line COPILOT)" == COPILOT=clean ]]'
st MERGEABLE null "" "" "$(com octocat "Copilot was unable to review this, sadly." 2026-01-02T00:00:00Z)"
check "when only a user's comment says unable to review, then COPILOT=none" '[[ "$(line COPILOT)" == COPILOT=none ]]'

st MERGEABLE null "" "$(rev $cop "" 2026-01-01T00:00:00Z)" "" \
  "$(th 1 false false 10 9 $cop),$(th 2 false true null 7 $cop),$(th 3 false false 5 5 $cop octocat),$(th 4 true false 6 6 $cop),$(th 5 false false 8 8 octocat)"
out="$("$p" state 12)"
check "when a review on the head left two unanswered Copilot threads, one replied and one resolved, then COPILOT=comments 2 with RESOLVE= the replied one" \
  '[[ "$out" == "$(printf "CONFLICT=no\nCI=none\nCOPILOT=comments 2 REPORT=%s RESOLVE=PRRT_3" "$report")" ]]'
printf '%s\n' '## Findings' "- src/f1.ts:10 thread=PRRT_1 $cop on f1" "  $cop on f1" '  second line' \
  "- src/f2.ts:7 thread=PRRT_2 (outdated) $cop on f2" "  $cop on f2" '  second line' > "$TMP/want.md"
check "then the report holds the two under ## Findings with path:line and ids, the outdated one marked, a null line read from originalLine, and no user's thread" \
  'diff "$TMP/want.md" "$report"'
st MERGEABLE null "" "" "" "$(th 1 false false null null $cop)"
"$p" state 12 >/dev/null
check "when a thread has neither line nor originalLine, then its report line says :1" 'grep -qx -- "- src/f1.ts:1 thread=PRRT_1 $cop on f1" "$report"'
st MERGEABLE null "" "" "" "$(th 3 false false 5 5 $cop octocat),$(th 5 false false 8 8 octocat)"
check "when the only Copilot thread left is replied to, then COPILOT=comments 0 with RESOLVE= it, and a user's thread is never counted" \
  '[[ "$(line COPILOT)" == "COPILOT=comments 0 REPORT=$report RESOLVE=PRRT_3" && "$(cat "$report")" == "## Findings" ]]'
st MERGEABLE null "" "" "" "$(th 6 false false 5 5 $cop octocat $cop)"
check "when Copilot wrote again after a reply, then the thread is unanswered" '[[ "$(line COPILOT)" == "COPILOT=comments 1 REPORT=$report" ]]'
st MERGEABLE null "" "$(rev $cop "" 2026-01-01T00:00:00Z)" "" "$(th 4 true false 6 6 $cop),$(th 5 false false 8 8 octocat)"
check "when Copilot reviewed and nothing is left, then COPILOT=clean" '[[ "$(line COPILOT)" == COPILOT=clean ]]'
st MERGEABLE null "" "$(rev octocat "" 2026-01-01T00:00:00Z)" "$(com octocat hi 2026-01-01T00:00:00Z)"
check "when no Copilot request, review or comment exists, then COPILOT=none" '[[ "$(line COPILOT)" == COPILOT=none ]]'
check "when given the PR's URL, then it reads that PR" '"$p" state https://github.com/acme/app/pull/12 | grep -qx COPILOT=none'

st MERGEABLE null "" "$(rev $cop "" 2026-01-01T00:00:00Z)" "" \
  "$(th 1 false false 10 9 $cop),$(th 3 false false 5 5 $cop octocat),$(th 4 true false 6 6 $cop),$(th 5 false false 8 8 octocat)"
printf 'Fixed in abc123.\n' > "$TMP/answer.md"; : > "$TMP/empty.md"; printf ' \n' > "$TMP/blank.md"
posted() { grep -q replies "$GH_LOG" || grep -q resolveReviewThread "$GH_LOG"; }
: > "$GH_LOG"; out="$("$p" state 12 --reply PRRT_1 "$TMP/answer.md")"
check "when --reply answers an unreplied Copilot thread, then it posts the file to its first comment's replies, then resolves it" \
  '[[ "$out" == REPLIED=PRRT_1 ]] && grep -qxF "api repos/{owner}/{repo}/pulls/12/comments/100/replies -F body=@$TMP/answer.md" "$GH_LOG" \
   && grep resolveReviewThread "$GH_LOG" | grep -q -- "-F id=PRRT_1 " && [[ "$(grep -n replies "$GH_LOG" | cut -d: -f1)" -lt "$(grep -n resolveReviewThread "$GH_LOG" | cut -d: -f1)" ]]'
: > "$GH_LOG"; out="$("$p" state 12 --reply PRRT_3 "$TMP/answer.md")"
check "when --reply names a thread already replied to, then it only resolves it and posts nothing" \
  '[[ "$out" == RESOLVED=PRRT_3 ]] && ! grep -q replies "$GH_LOG" && grep resolveReviewThread "$GH_LOG" | grep -q -- "-F id=PRRT_3 "'
: > "$GH_LOG"
check "when --reply names a user's thread, then it is refused and nothing is posted" 'one_refusal "thread PRRT_5 was not opened by Copilot" "$p" state 12 --reply PRRT_5 "$TMP/answer.md" && ! posted'
check "when --reply names a resolved thread, then it is refused and nothing is posted" 'one_refusal "thread PRRT_4 is already resolved" "$p" state 12 --reply PRRT_4 "$TMP/answer.md" && ! posted'
check "when --reply names a thread of another PR, then it is refused and nothing is posted" 'one_refusal "thread PRRT_9 is not on PR #12" "$p" state 12 --reply PRRT_9 "$TMP/answer.md" && ! posted'
check "when --reply has no file for an unreplied thread, then it is refused and nothing is posted" 'one_refusal "thread PRRT_1 has no reply yet" "$p" state 12 --reply PRRT_1 && ! posted'
check "when --reply has an empty file for an unreplied thread, then it is refused and nothing is posted" 'one_refusal "thread PRRT_1 has no reply yet" "$p" state 12 --reply PRRT_1 "$TMP/empty.md" && ! posted'
check "when --reply has a blank or a missing file, then it is refused and nothing is posted" \
  'one_refusal "thread PRRT_1 has no reply yet" "$p" state 12 --reply PRRT_1 "$TMP/blank.md" && one_refusal "thread PRRT_1 has no reply yet" "$p" state 12 --reply PRRT_1 "$TMP/nope.md" && ! posted'
check "when --reply names no thread, or one that is not a node id, then it prints its usage and posts nothing" \
  'fails_with "usage: pr.sh state" "$p" state 12 --reply && fails_with "usage: pr.sh state" "$p" state 12 --reply "a\"b" && ! posted'
check "when pr.sh state gets an unknown option, then it prints its usage" 'fails_with "usage: pr.sh state" "$p" state 12 --bogus'
check "when the reply cannot be posted, then nothing is resolved" \
  'GH_FAIL_REPLY=1 fails_with "could not post the reply to thread PRRT_1; nothing resolved" "$p" state 12 --reply PRRT_1 "$TMP/answer.md" && ! grep -q resolveReviewThread "$GH_LOG"'
set +e; out="$(GH_FAIL_RESOLVE=1 "$p" state 12 --reply PRRT_1 "$TMP/answer.md" 2>/dev/null)"; code=$?; set -e
check "when the resolve fails, then --reply prints REPLIED= and exits 1" '[[ "$out" == REPLIED=PRRT_1 && "$code" == 1 ]]'
fi

# ── Spec 008 T003: one draft PR per feature, from the feature branch, with the task table ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"; rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
new_repo standard
FB=feat/001-demo; PID=0123456789abcdef0123456789abcdef01234567
printf '%s\n' '# Tasks' '' '**Issue**: #42' '' '- [ ] T001 Add search in `src/search.ts`' \
  '- [ ] T002 Add ranking in `src/rank.ts` (depends on T001)' '- [ ] T003 Add export in `src/export.ts`' > specs/001-demo/tasks.md
"$SCRIPTS/branch.sh" >/dev/null 2>&1
# landed <id> <file>: what implement.sh land makes, a --no-ff merge of a task ref carrying its tick, with both trailers.
landed() {
  git switch --quiet -c "landspec/001-$1-task"; echo "$1" > "$2"
  sed -i.bak "s/^- \[ \] $1 /- [X] $1 /" specs/001-demo/tasks.md; rm -f specs/001-demo/tasks.md.bak
  git add -A; git commit --quiet -m "feat: $1"; git switch --quiet "$FB"
  git merge --quiet --no-ff -m "$1: x" -m "Landspec-Task: 001/$1"$'\n'"Landspec-Review: ready $PID" "landspec/001-$1-task"
  git branch --quiet -D "landspec/001-$1-task"
}
landed T001 search.ts; landed T002 rank.ts
printf 'The demo feature.\n\n## Evidence\n\nran\n' > "$TMP/fbody.md" # no ## Review: the feature PR needs none
git switch --quiet main
check "when pr.sh feature runs off the feature branch, then it refuses naming branch.sh <feature>" \
  'one_refusal "run branch.sh 001-demo" "$p" feature "feat: demo" "$TMP/fbody.md"'
git switch --quiet "$FB"
check "when no scan was recorded for the feature diff, then pr.sh feature refuses (the shared gates run)" \
  'fails_with "no security-scan.sh --changed result for this diff" "$p" feature "feat: demo" "$TMP/fbody.md" && ! grep -q "^pr create" "$GH_LOG"'
sed -i.bak 's/^- \[ \] T003 /- [X] T003 /' specs/001-demo/tasks.md; rm -f specs/001-demo/tasks.md.bak; git commit --quiet -am "docs: tick T003 by hand"
check "when a task is ticked with no landing commit, then pr.sh feature refuses it" \
  'one_refusal "T003 is ticked but was never landed: untick it or run /landspec:implement" "$p" feature "feat: demo" "$TMP/fbody.md"'
git reset --quiet --hard HEAD~1
scanned
mkdir -p .specify/memory
printf '**Commands**: build `[BUILD_COMMAND]` · test `bash %s` · lint `[LINT_COMMAND]` · mutate `[MUTATE_COMMAND]`\n' "$TMP/red.sh" > .specify/memory/constitution.md
check "when the test command is red, then pr.sh feature refuses and opens nothing" \
  'fails_with "the test command failed" "$p" feature "feat: demo" "$TMP/fbody.md" && ! grep -q "^pr create" "$GH_LOG"'
rm .specify/memory/constitution.md
out="$("$p" feature "feat: demo" "$TMP/fbody.md" 2>/dev/null)" || true
check "when two tasks are landed, with no review record of the branch, then one draft PR opens into the base and prints READY=no" \
  '[[ "$out" == *"PR=https://github.com/acme/app/pull/99 READY=no" ]] && grep -q "^pr create --draft --base develop --head $FB" "$GH_LOG" && [[ "$(grep -c "^pr create" "$GH_LOG")" == 1 ]]'
check "then the body has the Tasks table: each task's state, landing commit and review, and no Independent review block" \
  'grep -qxF "## Tasks" "$GH_LOG" && grep -qxF "| Task | Summary | State | Landing commit | Review |" "$GH_LOG" \
   && grep -qxF "| T001 | Add search | done | $(git log -1 --format=%h --grep="^Landspec-Task: 001/T001$") | ready (patch id ${PID:0:12}) |" "$GH_LOG" \
   && grep -qxF "| T002 | Add ranking | done | $(git log -1 --format=%h --grep="^Landspec-Task: 001/T002$") | ready (patch id ${PID:0:12}) |" "$GH_LOG" \
   && grep -qxF "| T003 | Add export | pending | - | - |" "$GH_LOG" && ! grep -q "Independent review" "$GH_LOG"'
check "then the body closes no issue, though tasks.md still has an **Issue** line, and has no End check yet" '! grep -q "Closes #" "$GH_LOG" && ! grep -q "## End check" "$GH_LOG"'
: > "$GH_LOG"; out="$("$p" feature "feat: demo" "$TMP/fbody.md" 2>/dev/null)" || true
check "when pr.sh feature runs again, then it replaces that PR's body and opens no other" \
  '! grep -q "^pr create" "$GH_LOG" && grep -q "^pr edit https://github.com/acme/app/pull/99 --body" "$GH_LOG" && [[ "$out" == *"PR=https://github.com/acme/app/pull/99 READY=no" ]]'
old="$(git rev-parse HEAD~1)"; mkdir -p "$(git rev-parse --git-common-dir)/landspec-review"
printf 'head: %s\nheads: %s %s\ntests: green\nverdict: changes needed\nreviewed: %s\n\n- met: FR-001 the demo searches\n- not met: SC-001 ranking is tested\n' \
  "$old" "$(git rev-parse HEAD~2)" "$old" "$old" > "$(git rev-parse --git-common-dir)/landspec-review/feature-001-demo"
rm -f "$GH_PR" "$GH_PR.head"; : > "$GH_LOG"
out="$(GH_NO_DRAFT=1 "$p" feature "feat: demo" "$TMP/fbody.md" 2>"$TMP/pr.err")" || true
check "when gh refuses drafts, then a normal PR opens with the do-not-merge warning" \
  'grep -q "^pr create --base develop --head $FB" "$GH_LOG" && grep -qxF "landspec: warning: drafts are not available: do not merge this PR before pr.sh feature --ready" "$TMP/pr.err" && [[ "$out" == *"READY=no" ]]'
check "when the feature has a changes needed end check for an older head, then the body has End check with its lines and checked at" \
  'grep -qxF "## End check" "$GH_LOG" && grep -qxF "Head: $old (round 2), tests: green" "$GH_LOG" && grep -qxF "Assessment: changes needed" "$GH_LOG" \
   && grep -qxF -- "- not met: SC-001 ranking is tested" "$GH_LOG" && grep -qxF -- "- met: FR-001 the demo searches" "$GH_LOG" \
   && grep -qxF "checked at $old; the branch is now at $(git rev-parse HEAD)" "$GH_LOG"'

exit "$FAIL"
