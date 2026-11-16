#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
i="$SCRIPTS/issues.sh"
plan_reviewed() { plan_review claude-opus-4-7 >/dev/null; }

new_repo standard
commit_tasks '# Tasks

- [ ] T001 Create the schema in `db/schema.sql`
  - Comes from: FR-001
  - Impact: tests/test_schema.py lists every table and
    must include the new one
  - Completed when: `make test` passes
- [ ] T002 [P] [US1] Price * filter [beta] & co in `src/a.ts` — #7
- [ ] T003 [US1] Show prices in src/view.tsx and src/list.tsx, with tests in tests/view.test.ts'

check "when the plan was not reviewed, then no issue is created" 'fails_with "no independent review" "$i" && ! grep -qs "^issue create" "$GH_LOG"'
CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 plan_reviewed 2>/dev/null
out="$("$i" 2>"$TMP/issues.err")"
check "when the plan record has a model warning, then issues.sh prints it as it creates the issues" \
  'grep -qxF "landspec: warning: CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set; the review did not run on the configured model" "$TMP/issues.err" && grep -q "^issue create" "$GH_LOG"'
check "when tasks have no issue, then one issue is created per task" '[[ "$(grep -c "^issue create" "$GH_LOG")" == 2 ]]'
check "then each issue number is written at the end of its task line" \
  'grep -qx -- "- \[ \] T001 Create the schema in \`db/schema.sql\` — #1" specs/001-demo/tasks.md && grep -q "T003 \[US1\] Show prices in src/view.tsx and src/list.tsx, with tests in tests/view.test.ts — #2$" specs/001-demo/tasks.md'
check "then a task that already had an issue is left alone" 'grep -qx -- "- \[ \] T002 \[P\] \[US1\] Price \* filter \[beta\] & co in \`src/a.ts\` — #7" specs/001-demo/tasks.md'
check "then it reports what it did" '[[ "$out" == *"CREATED=2 SKIPPED=1"* ]]'
check "then the title has the feature number and no file path, with or without backticks" \
  'grep -qF -- "--title [001] T001: Create the schema --body" "$GH_LOG" && grep -qF -- "--title [001] T003: Show prices --body" "$GH_LOG"'
check "then the body carries Comes from, Impact (a wrapped line keeps its newline) and Completed when" \
  'grep -qF "**Comes from:** FR-001" "$GH_LOG" && grep -qxF "**Impact:** tests/test_schema.py lists every table and" "$GH_LOG" && grep -qxF "must include the new one" "$GH_LOG" && grep -qF "**Completed when:** \`make test\` passes" "$GH_LOG"'
check "then the configured label is applied" 'grep -q -- "--label type:task" "$GH_LOG"'
check "then the user is assigned after creation" '[[ "$(grep -c "^issue edit https://github.com/acme/app/issues/[0-9]* --add-assignee @me" "$GH_LOG")" == 2 ]]'
check "when no milestone or project is configured, then none is set" '! grep -qE -- "--milestone|--add-project" "$GH_LOG"'

out="$("$i")"
check "when run again, then no issue is created twice" '[[ "$out" == *"CREATED=0 SKIPPED=3"* && "$(grep -c "^issue create" "$GH_LOG")" == 2 ]]'
check "when --sync, then each open linked issue gets its body rewritten from tasks.md, and nothing is created" \
  'out="$("$i" --sync)"; [[ "$out" == *"CREATED=0 SKIPPED=0 UPDATED=3"* && "$(grep -c "^issue edit [0-9]* --body \*\*Feature:\*\*" "$GH_LOG")" == 3 && "$(grep -c "^issue create" "$GH_LOG")" == 2 ]]'
check "when --sync and the issues are closed, then they are left alone" \
  'out="$(GH_VIEW_STATE=CLOSED "$i" --sync)"; [[ "$out" == *"SKIPPED=3 UPDATED=0"* && "$(grep -c "^issue edit [0-9]* --body" "$GH_LOG")" == 3 ]]'

printf '%s\n' '- [ ] T004 Dry task in `x`' >> specs/001-demo/tasks.md
check "when a task was added since the plan review, then it refuses until the plan is reviewed again" 'fails_with "changed since" "$i"'
plan_reviewed
check "when --dry-run, then nothing is created or written" \
  'out="$("$i" --dry-run)"; grep -q "would create" <<<"$out" && [[ "$(grep -c "^issue create" "$GH_LOG")" == 2 ]] && ! grep -q "T004.*#" specs/001-demo/tasks.md'

set_cfg milestone '"Sprint #3"'; set_cfg project '"Road map" # the team board'
printf '%s\n' '- [ ] T005 Meta task in `y`' >> specs/001-demo/tasks.md; plan_reviewed
"$i" >/dev/null
check "when a quoted milestone contains #, then it is kept whole" 'grep -q -- "^issue edit .* --milestone Sprint #3$" "$GH_LOG"'
check "then the project is set, and a trailing comment after the quotes is ignored" 'grep -q -- "^issue edit .* --add-project Road map$" "$GH_LOG"'

set_cfg milestone "'Q4 #2' # single quotes work too"
set_cfg project 'Board # unquoted, comment stripped'
printf '%s\n' '- [ ] T006 Scope task in `z`' >> specs/001-demo/tasks.md; plan_reviewed
out="$(GH_FAIL_EDIT=1 "$i" 2>&1)"
check "when setting metadata fails, then the issue is still created and linked" 'grep -q "T006 Scope task in \`z\` — #[0-9]*$" specs/001-demo/tasks.md'
check "then a single-quoted milestone is read whole, without its quotes" 'grep -q -- "^issue edit .* --milestone Q4 #2$" "$GH_LOG"'
check "then the warning shows gh's own error, for each item that failed" \
  '[[ "$(grep -c "Could not resolve to a ProjectV2" <<<"$out")" == 3 ]] && grep -q "could not set add-project .Board." <<<"$out"'

# F1.7: a create that reached GitHub but failed on the client leaves an open issue with the task's title.
printf '%s\n' '- [ ] T007 Retry task in `r`' >> specs/001-demo/tasks.md; plan_reviewed
GH_FAIL_CREATE_ONCE=1 "$i" >/dev/null 2>&1 || true
lost="$(cat "$GH_N")"; creates="$(grep -c "^issue create" "$GH_LOG")"
check "when the first gh issue create for a task reached GitHub but failed on the client, then a rerun makes no second create and writes the existing number back" \
  'out="$("$i")"; [[ "$(grep -c "^issue create" "$GH_LOG")" == "$creates" ]] && grep -q "T007 Retry task in \`r\` — #$lost$" specs/001-demo/tasks.md && grep -qx "T007 → #$lost (existing)" <<<"$out"'
check "then the lookup asks for open issues only (a closed one never matches), without --search or --label" \
  'grep -q "^issue list --state open --limit 1000 --json number,title" "$GH_LOG" && ! grep "^issue list" "$GH_LOG" | grep -qE -- "--search|--label"'
printf '%s\n' '- [ ] T009 Lookup task in `l`' >> specs/001-demo/tasks.md; plan_reviewed
creates="$(grep -c "^issue create" "$GH_LOG")"
check "when the open-issue lookup fails, then it stops and creates no issue" \
  'GH_FAIL_ISSUE_LIST=1 fails_with "cannot list the repository" "$i" && [[ "$(grep -c "^issue create" "$GH_LOG")" == "$creates" ]] && ! grep -q "T009.*#" specs/001-demo/tasks.md'
sed -i.bak '/T009 Lookup task/d' specs/001-demo/tasks.md && rm -f specs/001-demo/tasks.md.bak; plan_reviewed
printf '%s\n' "$((lost + 50)) [001] T008: Regenerated task" > "$GH_CLOSED" # an old issue: same prefix, another summary
printf '%s\n' '- [ ] T008 Brand new summary in `n`' >> specs/001-demo/tasks.md; plan_reviewed
check "when an open issue has the same [NNN] Tnnn: prefix but another summary, then a new issue is created" \
  'out="$("$i")"; [[ "$(grep -c "^issue create" "$GH_LOG")" == "$((creates + 1))" ]] && ! grep -q "#$((lost + 50))" specs/001-demo/tasks.md && grep -q "T008 Brand new summary in \`n\` — #[0-9]*$" specs/001-demo/tasks.md'

# gh picks upstream, then github, before origin, while every push goes to origin.
slug_of() { (git remote set-url origin "$1"; source "$SCRIPTS/lib.sh"; origin_slug); }
check "when origin is on github.com, then its owner/name is read from any URL form, dots in the name kept" \
  '[[ "$(slug_of git@github.com:acme/app.git)" == acme/app && "$(slug_of https://github.com/acme/my.app.git)" == acme/my.app && "$(slug_of https://github.com/acme/my.app)" == acme/my.app && "$(slug_of ssh://git@github.com/acme/app.git)" == acme/app ]]'
check "when origin is elsewhere, then nothing is read" \
  '[[ -z "$(slug_of https://gitlab.com/acme/app.git)" && -z "$(slug_of https://notgithub.com/acme/app.git)" && -z "$(slug_of /tmp/origin.git)" ]]'
keep_url="$(git remote get-url origin)"
git remote add upstream https://github.com/their/template.git
git remote set-url origin git@github.com:acme/app.git
printf -- '- [ ] T100 Land on origin in `o`\n' >> specs/001-demo/tasks.md; plan_reviewed
rm -f "$GH_LOG.repo"; "$i" >/dev/null
check "when another remote exists, then every gh call of issues.sh goes to origin's repository" \
  'grep -q "^acme/app label create" "$GH_LOG.repo" && grep -q "^acme/app issue create" "$GH_LOG.repo" && grep -q "^acme/app issue list" "$GH_LOG.repo" && grep -q "^acme/app issue edit" "$GH_LOG.repo" && ! grep -qv "^acme/app " "$GH_LOG.repo"'
printf -- '- [ ] T101 Stay where the user said in `o`\n' >> specs/001-demo/tasks.md; plan_reviewed
rm -f "$GH_LOG.repo"; GH_REPO=mine/own "$i" >/dev/null
check "when the user set GH_REPO, then it stays" 'grep -q "^mine/own issue create" "$GH_LOG.repo" && ! grep -q "^acme/app " "$GH_LOG.repo"'
mkdir -p "$TMP/gh-up"; printf '#!/bin/sh\necho their/template\n' > "$TMP/gh-up/gh"; chmod +x "$TMP/gh-up/gh"
check "then repo_slug names origin too, whatever gh repo view says" \
  '[[ "$(PATH="$TMP/gh-up:$PATH"; source "$SCRIPTS/lib.sh"; repo_slug)" == acme/app ]]'
git remote remove upstream; git remote set-url origin "$keep_url"

# #107: a field keeps every line indented under it, nested lists and blank lines included.
printf '%s\n' '- [ ] T200 Nest fields in `src/a.py`' '  - Comes from: FR-001' '  - Impact:' '    - first item' '    - second item' \
  '  - Completed when: `pytest tests/test_a.py` passes:' '    - case one' '' '    And then a note after a blank line.' \
  '- [ ] T201 Sibling fields in `src/b.py`' '  - Impact: one line' '    - nested' '  - What: next field' \
  '' '- [ ] T202 Last task in `src/c.py`' '  - Comes from: FR-002' '  - Completed when: the end' '    - last nested' '' >> specs/001-demo/tasks.md
plan_reviewed
tf() { (source "$SCRIPTS/lib.sh"; task_field specs/001-demo "$@"); }
check "when Impact is a nested list, then task_field returns every item on its own line" \
  '[[ "$(tf T200 Impact)" == $'"'"'\n- first item\n- second item'"'"' ]]'
check "when Completed when has a nested list and a note after a blank line, then all of it is kept, blank line included" \
  '[[ "$(tf T200 "Completed when")" == $'"'"'`pytest tests/test_a.py` passes:\n- case one\n\nAnd then a note after a blank line.'"'"' ]]'
check "when a field is followed by a sibling field, then it stops there and the sibling is read on its own" \
  '[[ "$(tf T201 Impact)" == $'"'"'one line\n- nested'"'"' && "$(tf T201 What)" == "next field" ]]'
check "when the field is the last of the last task, then it ends at the file end without trailing blank lines" \
  '[[ "$(tf T202 "Completed when")" == $'"'"'the end\n- last nested'"'"' ]]'
check "when a field is absent or one line, then it is empty or that line" '[[ -z "$(tf T202 Impact)" && "$(tf T202 "Comes from")" == FR-002 ]]'
: > "$GH_LOG"; "$i" >/dev/null
check "then the issue body carries the nested lists as markdown" \
  'grep -qxF "**Impact:** " "$GH_LOG" && grep -qxF -- "- first item" "$GH_LOG" && grep -qxF "**Completed when:** \`pytest tests/test_a.py\` passes:" "$GH_LOG" && grep -qxF "And then a note after a blank line." "$GH_LOG"'
t200="$(grep -o 'T200 Nest fields in `src/a.py` — #[0-9]*' specs/001-demo/tasks.md)"; t200="${t200##*#}"
base="$(source "$SCRIPTS/lib.sh"; base_branch)"
# The body issues.sh built before #107: no Impact, and the default Completed when.
truncated="**Feature:** \`001-demo\` · **Task:** T200 in [\`tasks.md\`](../blob/$base/specs/001-demo/tasks.md)

**Task:** Nest fields in \`src/a.py\`

**Comes from:** FR-001

**Completed when:** _its tests pass and the change is verified as plan.md describes._

---
**Done** = closed by the merged PR (\`Closes #N\`). Start it with \`/speckit-implement T200\`."
: > "$GH_LOG"
check "when --sync meets an issue whose body was built truncated, then it rewrites it with the whole fields" \
  'out="$(GH_VIEW_BODY="$truncated" "$i" --sync)"; grep -qF "T200 → #$t200 (updated)" <<<"$out" && grep -q "^issue edit $t200 --body" "$GH_LOG" && grep -qxF -- "- first item" "$GH_LOG" && grep -qxF "And then a note after a blank line." "$GH_LOG"'

exit "$FAIL"
