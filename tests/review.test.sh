#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
r="$SCRIPTS/review.sh"
# Every task report states its range (the merge-base with the base, then HEAD) and the reviewer's model.
range() { echo "Reviewed: $(git merge-base HEAD origin/develop)..$(git rev-parse HEAD)"; }
report() { printf 'What changed: x\n\nFindings: none\n\n%s\nModel: claude-sonnet-4-7\n\nAssessment: %s\n' "$(range)" "$1" > "$TMP/report.md"; }

new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo 'export const search = 1' > search.ts; git add search.ts; git commit --quiet -m "feat: search"

check "when no review was recorded, then check refuses and says how to record one" 'fails_with "no independent review" "$r" check'
check "when no task review was recorded on a task branch, then the hint is review.sh record <report-file>, without --plan" \
  'fails_with "record its report: review.sh record <report-file>" "$r" check'
: > "$TMP/empty.md"
check "when the report file is empty, then record (and record --feature) refuses and says the reviewer did not write it" \
  'fails_with "is empty: the reviewer named it but did not write it" "$r" record "$TMP/empty.md" && fails_with "is empty" "$r" record --feature "$TMP/empty.md"'
printf 'Looks fine to me.\n' > "$TMP/report.md"
check "when the report has no assessment line, then it is refused" 'fails_with "Assessment" "$r" record "$TMP/report.md"'
printf 'Assessment: not ready, changes needed\n' > "$TMP/report.md"
check "when the verdict is not the exact line (not ready, already), then it is refused" 'fails_with "exactly" "$r" record "$TMP/report.md"'
printf 'Assessment: changes needed\n\nmy risk assessment is that the retry path is already covered\n%s\nModel: claude-sonnet-4-7\n' "$(range)" > "$TMP/report.md"
check "when prose after the verdict mentions ready, then the verdict still counts" '"$r" record "$TMP/report.md" | grep -q "^REVIEW=changes needed"'
report "changes needed"
check "when the review said changes needed, then check refuses" '"$r" record "$TMP/report.md" && fails_with "changes needed" "$r" check'
report ready
check "when the review said ready on this diff, then check passes" '"$r" record "$TMP/report.md" | grep -q "^REVIEW=ready" && "$r" check'
# F3.1/F4.3: report prints only what the script checked (the patch id and the verdict), never the report's text,
# even a body line shaped like a header field (warning:, map-full:, map-fix:).
printf 'Preamble LEAK-1\n\n- **What changed**: Adds LEAK-2 search.\n- **Findings**:\n  - High: LEAK-3 in src/a.ts:3\n  - Security: LEAK-4 token logged\nwarning: LEAK-5\nmap-full: - deep: LEAK-6\nmap-fix: - deep: LEAK-7\n\n%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(range)" > "$TMP/report.md"
"$r" record "$TMP/report.md" >/dev/null; out="$("$r" report 2>&1)" || true
id="$(sed -n 's/^state: //p' "$(git rev-parse --git-common-dir)/landspec-review/task-$(git branch --show-current | sed 's|/|__|g')" | cut -c1-12)"
check "when a review is recorded, then report prints exactly the patch-id line, the Assessment line and the Model line" \
  '[[ ${#id} == 12 && "$out" == "Independent review recorded for this diff (patch id $id)"$'"'"'\n'"'"'"Assessment: ready"$'"'"'\n'"'"'"Model: claude-sonnet-4-7" ]]'
check "then report prints nothing from the report body (What changed, findings, the security finding)" \
  '! grep -qiE "LEAK|search|what changed|findings|token" <<<"$out"'
report "changes needed"; "$r" record "$TMP/report.md" >/dev/null
check "when the review said changes needed, then report refuses as check does" 'fails_with "changes needed" "$r" report'
report ready; "$r" record "$TMP/report.md" >/dev/null
echo 'export const more = 2' >> search.ts; git commit --quiet -am "feat: more"
check "when the code changed after the review, then check refuses until a new review is recorded" \
  'fails_with "changed since" "$r" check && report ready && "$r" record "$TMP/report.md" >/dev/null && "$r" check'
printf 'export const search = 1\n    export const more = 2\n' > search.ts; git commit --quiet -am "style: indent"
check "when a commit only re-indents a line, then the diff counts as changed (whitespace matters)" 'fails_with "changed since" "$r" check'
report ready; "$r" record "$TMP/report.md" >/dev/null
echo dirty > search.ts
check "when tracked files are dirty, then record refuses (the review is of the committed diff)" 'fails_with "commit the work first" "$r" record "$TMP/report.md"'
git checkout --quiet -- search.ts
echo note > notes.txt
check "when only untracked files exist (the report itself, say), then record still works" '"$r" record "$TMP/report.md" >/dev/null'
rm notes.txt
git checkout --quiet --detach
check "when HEAD is detached, then record and check refuse" 'fails_with "not on a branch" "$r" check && fails_with "not on a branch" "$r" record "$TMP/report.md"'
git switch --quiet -
# The base moves on with unrelated work; merging it changes the diff's text but not its content.
git switch --quiet main; echo x > other.txt; git add other.txt; git commit --quiet -m other; git push --quiet origin main:develop; git switch --quiet -
git fetch --quiet origin; git merge --quiet --no-edit origin/develop >/dev/null
check "when the base is merged in without touching the change, then the review still holds" '"$r" check'

# Plan review: tied to the feature folder, ignoring the issue numbers issues.sh appends.
git switch --quiet main
# sedi <sed args> <file>: edit in place, leaving no .bak behind (the plan state hashes every file of the folder).
sedi() { local f="${*: -1}"; sed -i.bak "$@" && rm -f "$f.bak"; }
check "when no plan review was recorded, then check --plan refuses" 'fails_with "no independent review" "$r" check --plan'
check "then the plan hint keeps --plan" 'fails_with "record its report: review.sh record --plan <report-file>" "$r" check --plan'
plan_report
check "when the plan review said ready, then check --plan passes" '"$r" record --plan "$TMP/plan.md" >/dev/null && "$r" check --plan'
sedi 's/ — #5$/ — #9/' specs/001-demo/tasks.md
check "when only the issue numbers changed, then the plan review still holds" '"$r" check --plan'
echo '# Plan: data model changed' > specs/001-demo/plan.md
check "when plan.md changed, then the plan needs a new review" 'fails_with "changed since" "$r" check --plan'
plan_review >/dev/null
printf '%s\n' '- [ ] T002 New task in `b`' >> specs/001-demo/tasks.md
check "when a task was added, then the plan needs a new review" 'fails_with "changed since" "$r" check --plan'

# #186: the record holds only for the plan state the reviewer read (its "Plan state:" line).
printf '%s\n' '  - What: the first version' >> specs/001-demo/tasks.md
plan_report
check "when a ready plan report carries the current Plan state:, then record --plan prints REVIEW=ready" \
  '[[ "$("$r" record --plan "$TMP/plan.md")" == REVIEW=ready ]]'
sedi 's/the first version/an edited version/' specs/001-demo/tasks.md
check "when a sub-bullet in tasks.md is edited and the same report is recorded again, then it fails and check --plan fails" \
  'fails_with "the plan changed since this review: run the review again" "$r" record --plan "$TMP/plan.md" && fails_with "changed since" "$r" check --plan'
plan_report
sedi -E '/ — #[0-9]+$/!s/^(- \[ \] T00[0-9].*)$/\1 — #42/' specs/001-demo/tasks.md
check "when only — #N is appended to the task lines, then the same report still records ready" \
  'grep -q "T002 New task in \`b\` — #42$" specs/001-demo/tasks.md && [[ "$("$r" record --plan "$TMP/plan.md")" == REVIEW=ready ]]'
st="$("$r" state --plan)"
printf 'Plan read.\n\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' > "$TMP/plan.md"
check "when the plan report has no Plan state: line, then record --plan refuses it" \
  'fails_with "the report has no Plan state line: run the review again (this landspec version records it)" "$r" record --plan "$TMP/plan.md"'
printf 'Plan read.\n\n**Plan state:** %s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$st" > "$TMP/plan.md"
check "when the line is written **Plan state:** <hash>, then it is read" '[[ "$("$r" record --plan "$TMP/plan.md")" == REVIEW=ready ]]'
printf 'Plan read.\n\nPlan state: unavailable (refused)\nModel: claude-sonnet-4-7\n\nAssessment: changes needed\n' > "$TMP/plan.md"
check "when the line is Plan state: unavailable (refused), then record refuses it as missing" \
  'fails_with "the report has no Plan state line" "$r" record --plan "$TMP/plan.md"'
printf 'Plan read.\n\nPlan state: %s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(tr a-f A-F <<<"$st")" > "$TMP/plan.md"
check "when the Plan state: hash is not lowercase hex, then record refuses it as missing" \
  'fails_with "the report has no Plan state line" "$r" record --plan "$TMP/plan.md"'
printf 'Plan read.\n\nPlan state: %s\nPlan state: %064d\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$st" 0 > "$TMP/plan.md"
check "when the report has two Plan state: lines, then the last one decides" \
  'fails_with "the plan changed since this review" "$r" record --plan "$TMP/plan.md"'
# The reviewer runs state in its own clean copy: no record folder, no active feature.
git add specs; git commit --quiet -m "plan"; git push --quiet origin main
git clone --quiet --branch main "$TMP/origin.git" "$TMP/fresh" 2>/dev/null
cp -R .specify "$TMP/fresh/"
check "when state --plan runs in a clone with no .git/landspec-review, then it prints the state and the folder still does not exist" \
  '[[ ! -e "$TMP/fresh/.git/landspec-review" && "$(cd "$TMP/fresh" && "$r" state --plan)" == "$st" && ! -e "$TMP/fresh/.git/landspec-review" ]]'
check "when state runs without --plan, then it fails with its usage and writes nothing" \
  '(cd "$TMP/fresh" && fails_with "usage: review.sh state --plan" "$r" state) && [[ ! -e "$TMP/fresh/.git/landspec-review" ]]'
check "when no plan review was recorded, then diff --plan dies no plan review recorded yet and writes nothing" \
  '(cd "$TMP/fresh" && fails_with "no plan review recorded yet for 001-demo" "$r" diff --plan) && [[ ! -e "$TMP/fresh/.git/landspec-review" ]]'
check "when diff runs without --plan, then it fails with its usage" '(cd "$TMP/fresh" && fails_with "usage: review.sh diff --plan" "$r" diff)'
rm -rf "$TMP/fresh/.specify"; snap="$TMP/fresh/snap"; mkdir -p "$snap" "$TMP/fresh/sub"; cp -R specs/001-demo/. "$snap/"
check "when state --plan <dir> runs in a clone with no .specify/feature.json, then it prints the same state as the active feature" \
  '[[ "$(cd "$TMP/fresh" && "$r" state --plan "$snap")" == "$st" ]]'
check "when <dir> is relative, then it is read from where state was called, not the repository root" \
  '[[ "$(cd "$TMP/fresh/sub" && "$r" state --plan ../snap)" == "$st" ]]'
rm "$snap/tasks.md"
check "when <dir> has no tasks.md, then state --plan fails" '(cd "$TMP/fresh" && fails_with "no tasks.md in" "$r" state --plan "$snap")'
cp specs/001-demo/tasks.md "$snap/"; rm "$snap/plan.md"
check "when <dir> has no plan.md, then state --plan fails" '(cd "$TMP/fresh" && fails_with "no plan.md in" "$r" state --plan "$snap")'
rm -rf "$snap" "$TMP/fresh"
printf 'Plan read.\n\nAssessment: ready\n' > "$TMP/plan.md"
check "when a plan report has no Model: line, then record --plan refuses" \
  'fails_with "the report must state Model: <id> for the plan: run the review again" "$r" record --plan "$TMP/plan.md"'
printf 'Plan read.\n\nPlan state: %s\nModel: ghp_abc123\n\nAssessment: ready\n' "$st" > "$TMP/plan.md"
check "when a plan report's Model: is ghp_abc123, then the plan record stores unknown" \
  '"$r" record --plan "$TMP/plan.md" >/dev/null 2>&1; grep -qx "model: unknown" "$(git rev-parse --git-common-dir)/landspec-review/plan-001-demo"'

# FR-009 (#206): the plan state is every file of the feature folder, and record keeps the folder it recorded.
d=specs/001-demo; kept="$(git rev-parse --git-common-dir)/landspec-review/plan-001-demo.reviewed"
printf '# Data model\n\n- entity: search\n' > $d/data-model.md; printf '%s\n' '- [ ] T003 Third task' >> $d/tasks.md
plan_review >/dev/null; st="$("$r" state --plan)"
sedi 's/entity: search/entity: query/' $d/data-model.md
check "when one line of data-model.md is edited, then the state changes and check --plan refuses changed since" \
  '[[ "$("$r" state --plan)" != "$st" ]] && fails_with "changed since" "$r" check --plan'
sedi 's/entity: query/entity: search/' $d/data-model.md
sedi 's/^\(- \[ \] T003 Third task\)$/\1 — #42/' $d/tasks.md
check "when — #42 is added to a task line, then the state is the same and check --plan passes" \
  'grep -q "T003 Third task — #42$" $d/tasks.md && [[ "$("$r" state --plan)" == "$st" ]] && "$r" check --plan'
mkdir -p $d/contracts; echo 'GET /search' > $d/contracts/api.md
check "when a file is added under contracts/, then the state changes" '[[ "$("$r" state --plan)" != "$st" ]]'
rm -r $d/contracts
for f in tasks.md.tmp .DS_Store tasks.md.swp plan.md~; do
  echo leftover > "$d/$f"
  check "when a leftover $f is in the folder, then the state is the same" '[[ "$("$r" state --plan)" == "$st" ]]'
  rm "$d/$f"
done
for f in tasks.tmp.md swp.md notes.txt; do
  echo leftover > "$d/$f"
  check "when $f (not a temp or editor name) is in the folder, then the state changes" '[[ "$("$r" state --plan)" != "$st" ]]'
  rm "$d/$f"
done
mkdir -p "$TMP/h1" "$TMP/h2" "$TMP/h3"; for h in h1 h2 h3; do cp $d/plan.md $d/tasks.md "$TMP/$h/"; done
printf X > "$TMP/h1/a"; printf Y > "$TMP/h1/b"; printf 'Xb\nY' > "$TMP/h2/a"; printf 'Xb\0\nY' > "$TMP/h3/a"
check "when one folder has a=X, b=Y and another a=Xb<newline>Y (or Xb<NUL><newline>Y), then they hash differently" \
  'h1="$("$r" state --plan "$TMP/h1")" && [[ "$h1" != "$("$r" state --plan "$TMP/h2")" && "$h1" != "$("$r" state --plan "$TMP/h3")" ]]'
rm -rf "$TMP/h1" "$TMP/h2" "$TMP/h3"
check "when a plan review is recorded, then the kept copy holds the folder, tasks.md without its issue numbers" \
  '[[ -f "$kept/data-model.md" ]] && grep -qx -- "- \[ \] T003 Third task" "$kept/tasks.md" && ! grep -q " — #" "$kept/tasks.md"'
cp -R "$kept" "$TMP/kept0"; plan_report; sedi 's/entity: search/entity: refused/' $d/data-model.md
check "when record --plan is refused (the plan changed since), then the kept copy is as it was" \
  'fails_with "the plan changed since" "$r" record --plan "$TMP/plan.md" && diff -r "$TMP/kept0" "$kept"'
sedi 's/entity: refused/entity: search/' $d/data-model.md; rm -rf "$TMP/kept0"
printf 'Plan read.\n\nPlan state: %s\nModel: claude-sonnet-4-7\n\nAssessment: changes needed\n' "$("$r" state --plan)" > "$TMP/plan.md"
"$r" record --plan "$TMP/plan.md" >/dev/null
sedi 's/entity: search/entity: lookup/' $d/data-model.md; sedi 's/ — #42$/ — #43/' $d/tasks.md
check "after a recorded changes needed, then diff --plan shows exactly the edited line (issue numbers stripped on both sides)" \
  '[[ "$("$r" diff --plan | grep -E "^[-+]" | grep -vE "^(---|\+\+\+) ")" == "-- entity: search"$'"'"'\n'"'"'"+- entity: lookup" ]]'
check "when nothing changed since the recorded round, then diff --plan prints nothing" \
  'plan_review >/dev/null && [[ -z "$("$r" diff --plan)" ]]'
# Upgrade: a record written by 2.7.0 holds the hash of plan.md and tasks.md only.
old="$({ cat $d/plan.md; sed -E 's/ — #[0-9]+[[:space:]]*$//' $d/tasks.md; } | if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1)"
rec="$(git rev-parse --git-common-dir)/landspec-review/plan-001-demo"; sedi "s/^state: .*/state: $old/" "$rec"
check "when the record holds a 2.7.0 state, then check --plan refuses once, and passes after the review is recorded again" \
  'fails_with "changed since" "$r" check --plan && plan_review >/dev/null && "$r" check --plan'

# ── FR-030/FR-031: the risk map sets the minimum depth ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo 'export const search = 1' > search.ts; git add search.ts; git commit --quiet -m "feat: search"
# rep <assessment> <line...>: a full-round report for HEAD with the given lines (risk map, findings).
rep() { local v="$1"; shift; { echo 'What changed: x'; echo; printf '%s\n' "$@"; echo; range; echo 'Model: claude-sonnet-4-7'; echo; echo "Assessment: $v"; } > "$TMP/report.md"; }
# drep <assessment> <from> <line...>: a delta report reviewing <from>..HEAD.
drep() { local v="$1" f="$2"; shift 2; { echo 'What changed: y'; echo; printf '%s\n' "$@"; echo; echo "Delta from: $f"; echo "Reviewed: $f..$(git rev-parse HEAD)"; echo 'Model: claude-sonnet-4-7'; echo; echo "Assessment: $v"; } > "$TMP/report.md"; }
check "when the diff touches nothing risky, then review.sh risk prints exactly RISK=none" '[[ "$("$r" risk)" == RISK=none ]]'
drep ready "$(git rev-parse HEAD)"
check "when no full review was recorded for the branch, then record --delta refuses" \
  'fails_with "a delta follows a recorded full review of this branch: run a new full review, then record it with review.sh record <report-file>" "$r" record --delta "$TMP/report.md"'
check "when record --plan --delta is used, then it is refused" \
  'fails_with "a plan review is always full: review.sh record --plan <report-file>" "$r" record --plan --delta "$TMP/report.md"'
check "when review.sh risk --plan runs, then it refuses" 'fails_with "risk maps a diff; a plan review has none" "$r" risk --plan'

mkdir -p db/migrations src tests
printf 'DROP TABLE users;\n' > db/migrations/002_drop.sql; echo 'def can(u): return True' > src/authorization.py
printf 'make x || true\n' > build.sh; printf 'assert 1\nassert 2\nassert 3\n' > tests/drop.test.sh
git add db src build.sh tests; git commit --quiet -m "feat: risky"
check "when the diff adds db/migrations/002_drop.sql with DROP TABLE, then risk prints RISK=migration and RISK=delete for it" \
  'out="$("$r" risk)"; grep -qx "RISK=migration db/migrations/002_drop.sql" <<<"$out" && grep -qx "RISK=delete db/migrations/002_drop.sql" <<<"$out"'
check "when the diff adds src/authorization.py, then risk prints RISK=auth for it" '"$r" risk | grep -qx "RISK=auth src/authorization.py"'
check "when an added line swallows a failure (x || true), then risk prints RISK=gate for its file" '"$r" risk | grep -qx "RISK=gate build.sh"'
check "then risk prints only paths and categories, never the line content" '! "$r" risk | grep -qiE "drop table|make x"'
mkdir -p web; printf 'a { color: #8a90ad }\n' > web/site.css; printf '<a href="/">x</a>\n' > web/page.html; echo 'x = 1' > src/util.py
git add web src/util.py; git commit --quiet -m "feat: page"
check "when the diff adds a stylesheet or a page template, then risk prints RISK=ui for each, and not for other code" \
  'out="$("$r" risk)"; grep -qx "RISK=ui web/site.css" <<<"$out" && grep -qx "RISK=ui web/page.html" <<<"$out" && ! grep -q "src/util.py" <<<"$out"'
git reset --quiet --hard HEAD~1
deep=("- deep: src/authorization.py — always allows: checked the callers" "- deep: build.sh")
rep ready "${deep[@]}"
check "when the report has no '- deep:' line for a risky path, then record refuses, names the path and says to run the review again" \
  'fails_with "the report does not check db/migrations/002_drop.sql (" "$r" record "$TMP/report.md" && fails_with "run the review again" "$r" record "$TMP/report.md"'
rep ready "${deep[@]}" "- deep: db/migrations/002_drop.sql.bak"
check "when a '- deep:' line names a longer path (002_drop.sql.bak), then it does not cover 002_drop.sql" \
  'fails_with "the report does not check db/migrations/002_drop.sql (" "$r" record "$TMP/report.md"'
rep ready "${deep[@]}" "- proven: db/migrations/002_drop.sql"
check "when a '- proven:' line names no test, then record refuses" \
  'fails_with "db/migrations/002_drop.sql is not proven by <file>:<n> (not a test file, or no such line): check it deep or name the test" "$r" record "$TMP/report.md"'
rep ready "${deep[@]}" "- proven: db/migrations/002_drop.sql by search.ts:1"
check "when a '- proven:' line names a file that is not a test, then record refuses" \
  'fails_with "db/migrations/002_drop.sql is not proven by search.ts:1 (not a test file" "$r" record "$TMP/report.md"'
rep ready "${deep[@]}" "- proven: db/migrations/002_drop.sql by tests/drop.test.sh:4"
check "when a '- proven:' line names a line past the test file's end, then record refuses" \
  'fails_with "db/migrations/002_drop.sql is not proven by tests/drop.test.sh:4" "$r" record "$TMP/report.md"'
rep ready "${deep[@]}" "- proven: db/migrations/002_drop.sql by tests/drop.test.sh:3"
check "when a '- proven:' line names an existing test line for a path flagged delete, then record refuses: only '- deep:' clears it" \
  'fails_with "the report does not check db/migrations/002_drop.sql (delete, migration): add '"'"'- deep: db/migrations/002_drop.sql'"'"'" "$r" record "$TMP/report.md"'
rep ready "${deep[0]}" "- deep: db/migrations/002_drop.sql" "- proven: build.sh by tests/drop.test.sh:3"
check "when a '- proven:' line names an existing test line for a non-test path flagged gate (build.sh), then record refuses: only '- deep:' clears it" \
  'fails_with "the report does not check build.sh (gate): add '"'"'- deep: build.sh'"'"'" "$r" record "$TMP/report.md"'
rep ready "- proven: src/authorization.py by tests/drop.test.sh:3 — asserts the check denies" "- deep: build.sh" "- deep: db/migrations/002_drop.sql"
check "when every risky path is deep or proven by an existing test line, then record prints REVIEWED=<HEAD> then REVIEW=ready, and check passes" \
  'out="$("$r" record "$TMP/report.md")"; [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$(git rev-parse HEAD)")" ]] && "$r" check'

# Every report states its range and model; plain record takes only a full one.
mb="$(git merge-base HEAD origin/develop)"; all=("${deep[@]}" "- deep: db/migrations/002_drop.sql")
range_msg="the report must state Reviewed: <from>..<head> and Model: <id> for $mb..$(git rev-parse HEAD): run the review again"
rep ready "${all[@]}"; sed -i.bak '/^Reviewed: /d' "$TMP/report.md"
check "when a report has no Reviewed: line, then record refuses" 'fails_with "$range_msg" "$r" record "$TMP/report.md"'
rep ready "${all[@]}"; sed -i.bak '/^Model: /d' "$TMP/report.md"
check "when a report has no Model: line, then record refuses" 'fails_with "$range_msg" "$r" record "$TMP/report.md"'
rep ready "${all[@]}"; sed -i.bak "s/^Reviewed: [0-9a-f]*\.\./Reviewed: $(git rev-parse HEAD~1)../" "$TMP/report.md"
check "when the range does not start at the merge-base with the base, then record refuses" 'fails_with "$range_msg" "$r" record "$TMP/report.md"'
rep ready "${all[@]}"; sed -i.bak "s/\.\.[0-9a-f]*$/..$(git rev-parse HEAD~1)/" "$TMP/report.md"
check "when the range does not end at HEAD (a commit made while the review ran), then record refuses" 'fails_with "$range_msg" "$r" record "$TMP/report.md"'
rep ready "${all[@]}" "Delta from: $(git rev-parse HEAD)"
check "when a report with a Delta from: line is recorded without --delta, then record refuses" \
  'fails_with "this is a delta report: record it with --delta, or run a new full review" "$r" record "$TMP/report.md"'

# The model the review ran on: a warning, stored in the record, never a silent downgrade.
warn() { echo "landspec: warning: $1; the review did not run on the configured model"; }
rep ready "${all[@]}"; sed -i.bak 's/^Model: .*/Model: claude-haiku-4-5/' "$TMP/report.md"
check "when review_model is unset or opus and Model: is claude-haiku-4-5, then record prints exactly one warning, the review ran on <id>" \
  'err="$("$r" record "$TMP/report.md" 2>&1 >/dev/null)"; [[ "$err" == "$(warn "the review ran on claude-haiku-4-5")" ]] \
   && echo "review_model: opus" >> .specify/extensions/landspec/landspec-config.yml && err="$("$r" record "$TMP/report.md" 2>&1 >/dev/null)" \
   && [[ "$err" == "$(warn "the review ran on claude-haiku-4-5")" ]]'
check "when CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set, then its reason wins over an outside-family model (one line)" \
  'err="$(CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 "$r" record "$TMP/report.md" 2>&1 >/dev/null)"; [[ "$err" == "$(warn "CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set")" ]]'
sed -i.bak '/^review_model:/d' .specify/extensions/landspec/landspec-config.yml; echo "review_model: sonnet" >> .specify/extensions/landspec/landspec-config.yml
rep ready "${all[@]}"; sed -i.bak 's/^Model: .*/Model: claude-opus-4-7/' "$TMP/report.md"
check "when Model: is opus and review_model is sonnet, then record warns the review ran on <id>, not sonnet" \
  'err="$("$r" record "$TMP/report.md" 2>&1 >/dev/null)"; [[ "$err" == "$(warn "the review ran on claude-opus-4-7, not sonnet")" ]]'
sed -i.bak '/^review_model:/d' .specify/extensions/landspec/landspec-config.yml; echo "review_model: haiku" >> .specify/extensions/landspec/landspec-config.yml
check "when review_model is haiku, then record refuses (the config cannot lower the bar)" \
  'fails_with "landspec: review_model must be sonnet, opus or fable" "$r" record "$TMP/report.md"'
sed -i.bak '/^review_model:/d' .specify/extensions/landspec/landspec-config.yml

# Model: reaches the PR body, so only something shaped like a model id is stored.
rec() { echo "$(git rev-parse --git-common-dir)/landspec-review/task-$(git branch --show-current | sed 's|/|__|g')"; }
model_is() { rep ready "${all[@]}"; sed -i.bak "s/^Model: .*/Model: $1/" "$TMP/report.md"; err="$("$r" record "$TMP/report.md" 2>&1 >/dev/null)"; [[ "$(sed -n 's/^model: //p' "$(rec)" | head -1)" == "$2" ]]; }
echo "review_model: opus" >> .specify/extensions/landspec/landspec-config.yml
check "when Model: is claude-opus-4-8[1m], then it is kept with no warning" 'model_is "claude-opus-4-8[1m]" "claude-opus-4-8[1m]" && [[ -z "$err" ]]'
check "when Model: is us.anthropic.claude-opus-4-1-20250805-v1:0, then it is kept with no warning" \
  'model_is us.anthropic.claude-opus-4-1-20250805-v1:0 us.anthropic.claude-opus-4-1-20250805-v1:0 && [[ -z "$err" ]]'
sed -i.bak '/^review_model:/d' .specify/extensions/landspec/landspec-config.yml
check "when Model: is claude-haiku-4-5, then it is kept, with its warning" 'model_is claude-haiku-4-5 claude-haiku-4-5 && [[ "$err" == "$(warn "the review ran on claude-haiku-4-5")" ]]'
for bad in Token=abc ghp_abc123; do
  check "when Model: is $bad, then unknown is stored in the record and the warning, and the value in neither" \
    'model_is "$bad" unknown && [[ "$err" == "$(warn "the review ran on unknown")" ]] && grep -qx "warning: the review ran on unknown; the review did not run on the configured model" "$(rec)" && ! sed "/^$/q" "$(rec)" | grep -qF "$bad"'
done
long="claude-$(head -c 80 /dev/zero | tr '\0' x)"
check "when Model: is over 80 characters, then unknown is stored" 'model_is "$long" unknown'

# ── FR-032/FR-033: delta rounds ──
rep ready "${all[@]}"; "$r" record "$TMP/report.md" >/dev/null || true
drep ready "$(git rev-parse HEAD)" "${all[@]}"
check "when nothing was committed since the last full review, then record --delta refuses" \
  'fails_with "nothing was committed since the last review ($(git rev-parse HEAD)): commit the fixes, then run the delta review" "$r" record --delta "$TMP/report.md"'
rep "changes needed" "${all[@]}" "Findings:" "- High: search.ts:1 the search is wrong"
"$r" record "$TMP/report.md" >/dev/null || true; h1="$(git rev-parse HEAD)"
seq 1 25 | sed 's/^/export const s/; s/$/ = 1/' >> search.ts; seq 1 30 | sed 's/^/assert /' > tests/search.test.ts
git add search.ts tests/search.test.ts; git commit --quiet -m "fix: search"
drep ready "$h1"; sed -i.bak '/^Delta from: /d' "$TMP/report.md"
check "when a delta report has no Delta from: line, then record --delta refuses" \
  'fails_with "a delta report names its base: Delta from: $h1; run the delta review again" "$r" record --delta "$TMP/report.md"'
drep ready "$mb"
check "when Delta from: names another commit than the recorded head, then record --delta refuses" \
  'fails_with "the delta must review $h1..HEAD (Reviewed: $h1..$(git rev-parse HEAD)): run the delta review again from $h1" "$r" record --delta "$TMP/report.md"'
drep ready "$h1"; sed -i.bak "s/^Reviewed: [0-9a-f]*\.\./Reviewed: $mb../" "$TMP/report.md"
check "when a delta's range starts elsewhere, then record --delta prints exactly one refusal line, the delta one" \
  'err="$("$r" record --delta "$TMP/report.md" 2>&1)" && exit 1; [[ "$err" == "landspec: the delta must review $h1..HEAD (Reviewed: $h1..$(git rev-parse HEAD)): run the delta review again from $h1" ]]'
drep ready "$h1"; sed -i.bak '/^Model: /d' "$TMP/report.md"
check "when a delta report has no Model: line, then record --delta refuses" \
  'fails_with "the report must state Reviewed: <from>..<head> and Model: <id> for $h1..$(git rev-parse HEAD)" "$r" record --delta "$TMP/report.md"'
drep ready "$h1" "round: full"
check "when the fix changes 25 lines of a findings file plus a new 30-line test, then a ready delta is recorded and check passes on the whole diff" \
  'out="$("$r" record --delta "$TMP/report.md")"; [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$(git rev-parse HEAD)")" ]] && "$r" check'
h3="$(git rev-parse HEAD)"; echo "// fix" >> search.ts; git add search.ts; git commit --quiet -m "fix: second round"
drep ready "$h3"
check "when the last round was a delta, then another delta from its head is recorded, so fix rounds can always end" \
  'out="$("$r" record --delta "$TMP/report.md")"; [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$(git rev-parse HEAD)")" ]] && "$r" check'
ev="$(git rev-parse --git-common-dir)/landspec-events"
check "when full and delta reviews are recorded, then each appends one review line to .git/landspec-events with its round, verdict and branch" \
  'b="$(git branch --show-current)"; grep -qE "^[0-9]+ [0-9T:-]+Z $b review round=full verdict=ready branch=$b$" "$ev" && [[ "$(grep -c " review round=delta verdict=ready branch=$b$" "$ev")" == 2 ]]'
check "when the event log cannot be written (a directory in its place), then event prints nothing and returns 0" \
  'mv "$ev" "$ev.keep"; mkdir "$ev"; out="$(bash -c "source \"$SCRIPTS/lib.sh\"; event review round=full" 2>&1)"; rc=$?; rmdir "$ev"; mv "$ev.keep" "$ev"; ((rc == 0)) && [[ -z "$out" ]]'

rep "changes needed" "${all[@]}" "Findings:" "- High: search.ts:1 still wrong"
"$r" record "$TMP/report.md" >/dev/null || true; h2="$(git rev-parse HEAD)"
rep "changes needed" "${all[@]}" "Findings:" "- High: search.ts:1 still wrong" "Findings: 1 high, 2 medium, 0 low"; "$r" record "$TMP/report.md" >/dev/null || true
check "when the report has the Findings count line, then the review event carries hm, its high and medium sum" \
  'grep -q " review round=full verdict=changes-needed hm=3 branch=" "$ev" && ! grep -q "verdict=ready hm=" "$ev"'
seq 1 21 | sed 's/^/export const o/; s/$/ = 1/' > other.ts; git add other.ts; git commit --quiet -m "fix: other"
drep ready "$h2"
check "when the fix adds 21 lines to a file outside the previous findings, then record --delta refuses and check still refuses" \
  'fails_with "the delta changes 21 lines outside the previous findings (limit 20): run a new full review" "$r" record --delta "$TMP/report.md" && fails_with "changed since" "$r" check'
o="$(git rev-parse HEAD)"; git reset --quiet --hard "$h2"
rep "changes needed" "${all[@]}" "**Claims** (before the findings):" "- held: a claim — a case: stopped at other.ts:1" "Findings:" "- High: search.ts:1 still wrong"
"$r" record "$TMP/report.md" >/dev/null || true; git cherry-pick --quiet "$o"; drep ready "$h2"
check "when the 21 lines are in a file only a held claim names, then record --delta still refuses" \
  'fails_with "the delta changes 21 lines outside the previous findings (limit 20): run a new full review" "$r" record --delta "$TMP/report.md"'
git reset --quiet --hard "$h2"
echo 'DROP TABLE orders;' >> db/migrations/002_drop.sql; git commit --quiet -am "fix: drop orders"
drep ready "$h2"
check "when the fix adds DROP TABLE to a path round 1 marked deep and the delta has no '- deep:' for it, then record --delta refuses" \
  'fails_with "the report does not check db/migrations/002_drop.sql (" "$r" record --delta "$TMP/report.md"'
drep ready "$h2" "- deep: db/migrations/002_drop.sql — drops orders: checked"
check "when the delta deep-checks it, then the delta is recorded and report lists both labeled risk maps, paths only" \
  '"$r" record --delta "$TMP/report.md" >/dev/null && out="$("$r" report)" && grep -A3 -x "Risk map (round 1)" <<<"$out" | grep -qx -- "- deep: build.sh" \
   && grep -A1 -x "Risk map (fix round)" <<<"$out" | grep -qx -- "- deep: db/migrations/002_drop.sql" && ! grep -qE "drops|checked|always allows" <<<"$out"'

rep ready "${all[@]}"; "$r" record "$TMP/report.md" >/dev/null || true; h3="$(git rev-parse HEAD)"
git reset --quiet --hard HEAD~1; git commit --quiet --amend -m rewritten
drep ready "$h3"
check "when the last reviewed commit is no longer on the branch (rebased), then record --delta refuses" \
  'fails_with "$h3 is no longer on this branch (rebased?): run a new full review" "$r" record --delta "$TMP/report.md"'

# A skipped test cannot fail, so it cannot prove itself: a gate path, or a test path, needs '- deep:'.
git reset --quiet --hard "$h2"
printf "it('works', () => {})\n" > tests/a.test.js; git add tests/a.test.js; git commit --quiet -m "test: a"
printf "it.skip('works', () => {})\n" > tests/a.test.js; git commit --quiet -am "test: skip a"
rep ready "${all[@]}" "- proven: tests/a.test.js by tests/a.test.js:1"
check "when a commit changes it( to it.skip( in tests/a.test.js and the report says '- proven: tests/a.test.js by tests/a.test.js:1', then record refuses" \
  '"$r" risk | grep -qx "RISK=gate tests/a.test.js" && fails_with "the report does not check tests/a.test.js (gate): add '"'"'- deep: tests/a.test.js'"'"'" "$r" record "$TMP/report.md"'
echo "it('denies', () => {})" > tests/login.test.js; git add tests/login.test.js; git commit --quiet -m "test: login"
rep ready "${all[@]}" "- deep: tests/a.test.js" "- proven: tests/login.test.js by tests/login.test.js:1"
check "when a test path flagged only auth (tests/login.test.js) is 'proven' by its own line, then record refuses" \
  '"$r" risk | grep -qx "RISK=auth tests/login.test.js" && fails_with "the report does not check tests/login.test.js (auth): add '"'"'- deep: tests/login.test.js'"'"'" "$r" record "$TMP/report.md"'

# review.sh risk reads only the diff, so it needs no branch.
git checkout --quiet --detach
check "when HEAD is detached, then review.sh risk still prints the risk map" '"$r" risk | grep -qx "RISK=gate tests/a.test.js"'
git switch --quiet -

# ── FR-022: the rules that decide a review, one case each, on a branch of their own ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
mkdir -p src tests; echo 'export const search = 1' > search.ts; echo 'export const login = 1' > src/login.ts
printf 'assert 1\nassert 2\nassert 3\n' > tests/p.test.sh
git add search.ts src tests; git commit --quiet -m "feat: search"
# rr <line...>: a full-round report for HEAD (its range, then the given lines: Model:, findings, verdicts).
rr() { { echo 'What changed: x'; echo; printf 'Reviewed: %s..%s\n' "$(git merge-base HEAD origin/develop)" "$(git rev-parse HEAD)"; printf '%s\n' "$@"; } > "$TMP/report.md"; }
login='- deep: src/login.ts'; sonnet='Model: claude-sonnet-4-7'
verdict_of() { local out; out="$("$r" record "$TMP/report.md")"; sed -n 's/^REVIEW=//p' <<<"$out"; }
stored_model() { sed -n 's/^model: //p' "$(rec)" | head -1; }
rr "$login" "$sonnet" 'Assessment: ready' 'Assessment: changes needed'
check "when a report has two verdict lines, ready then changes needed, then the last one decides" '[[ "$(verdict_of)" == "changes needed" ]]'
rr "$login" "$sonnet" 'Assessment: changes needed' 'Assessment: ready'
check "when a report has two verdict lines, changes needed then ready, then the last one decides" '[[ "$(verdict_of)" == ready ]]'
rr "$login" "$sonnet" 'Assessment: ready to merge'
check "when the verdict line carries prose after it (ready to merge), then record refuses" 'fails_with "exactly" "$r" record "$TMP/report.md"'
rr "$login" "$sonnet" 'I would say the Assessment: ready'
check "when the verdict is only inside a sentence, then record refuses" 'fails_with "exactly" "$r" record "$TMP/report.md"'
rr "$login" 'Model: claude-haiku-4-5' 'Model: claude-opus-4-8' 'Assessment: ready'
check "when a report has two Model: lines, haiku then opus, then the last one is stored" '"$r" record "$TMP/report.md" >/dev/null 2>&1 && [[ "$(stored_model)" == claude-opus-4-8 ]]'
rr "$login" 'Model: claude-opus-4-8' 'Model: claude-haiku-4-5' 'Assessment: ready'
check "when a report has two Model: lines, opus then haiku, then the last one is stored" '"$r" record "$TMP/report.md" >/dev/null 2>&1 && [[ "$(stored_model)" == claude-haiku-4-5 ]]'
rr "$login" "$sonnet" "- proven: src/login.ts by tests/p.test.sh:0" 'Assessment: ready'
check "when a '- proven:' line names line 0 of an existing test file, then record refuses (lines start at 1)" \
  'fails_with "src/login.ts is not proven by tests/p.test.sh:0 (not a test file, or no such line)" "$r" record "$TMP/report.md"'
rr "$login" "$sonnet" "- proven: src/login.ts by tests/p.test.sh:1" 'Assessment: ready'
check "when it names line 1 of the same file, then record accepts it" '[[ "$(verdict_of)" == ready ]]'

# A fix round may change 20 lines outside the findings' files, and a binary file counts as more.
rr "$login" "$sonnet" 'Findings:' '- High: search.ts:1 the search is wrong' 'Assessment: changes needed'
"$r" record "$TMP/report.md" >/dev/null; h1="$(git rev-parse HEAD)"
seq 1 20 | sed 's/^/export const o/; s/$/ = 1/' > other.ts; git add other.ts; git commit --quiet -m "fix: other"
drep ready "$h1"
check "when the fix adds exactly 20 lines to a file outside the findings, then the delta is recorded" \
  'out="$("$r" record --delta "$TMP/report.md")"; [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$(git rev-parse HEAD)")" ]]'
h2="$(git rev-parse HEAD)"; printf '\0\1' > bin.dat; git add bin.dat; git commit --quiet -m "fix: binary"
drep ready "$h2"
check "when the fix adds a binary file outside the findings, then it counts as 21 lines and record --delta refuses" \
  'fails_with "the delta changes 21 lines outside the previous findings (limit 20): run a new full review" "$r" record --delta "$TMP/report.md"'

# One path per risk category, each in its own commit: risk prints exactly that category and path.
echo old > old.txt; git add old.txt; git commit --quiet -m "chore: old"
rows=('delete|old.txt|__rm__' 'delete|clean.sh|rm -rf build' 'migration|db/migrate/001_add.rb|x' 'ci|.github/workflows/ci.yml|x'
  'auth|src/signup-login.ts|x' 'secrets|config/secret.txt|x' 'money|src/billing.ts|x' 'gate|run.sh|make x || true')
for row in "${rows[@]}"; do
  IFS="|" read -r cat_ path_ txt_ <<<"$row"
  if [[ "$txt_" == __rm__ ]]; then git rm --quiet "$path_"; else mkdir -p "$(dirname "$path_")"; printf '%s\n' "$txt_" > "$path_"; git add -- "$path_"; fi
  git commit --quiet -m "chore: $cat_"
  check "when the diff has only $path_ ($cat_), then risk prints exactly RISK=$cat_ $path_" '[[ "$("$r" risk HEAD~1)" == "RISK=$cat_ $path_" ]]'
done

# ── FR-006: no merge base is a refusal, an empty diff is not ──
rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/shallow"; cd "$TMP"
new_repo standard
git commit --quiet --allow-empty -m one; git commit --quiet --allow-empty -m two # so depth 3 leaves the clone shallow
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo a > a.txt; git add a.txt; git commit --quiet -m "feat: a"
task_record() { echo ".git/landspec-review/task-$(git branch --show-current | sed 's|/|__|g')"; }
shallow_repo
# The range the old fallback accepted: with no merge base, diff_base is HEAD.
printf 'What changed: x\n\nReviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" > "$TMP/report.md"
check "on a --depth 1 clone with no merge base, then record prints one refusal naming git fetch --unshallow and writes no record" \
  'one_refusal "git fetch --unshallow" "$r" record "$TMP/report.md" && [[ ! -e "$(task_record)" ]]'
check "then check prints one refusal naming git fetch --unshallow" 'one_refusal "git fetch --unshallow" "$r" check'
cd "$TMP/repo"; git switch --quiet --orphan feat/001-t001-unrelated
echo b > b.txt; git add b.txt; git commit --quiet -m "feat: unrelated"
check "when a full clone's branch shares no history with the base, then check refuses without naming git fetch --unshallow" \
  'one_refusal "no history" "$r" check && out="$("$r" check 2>&1 || true)" && [[ "$out" != *unshallow* ]]'
git switch --quiet feat/001-t001-add-search
git revert --no-edit HEAD >/dev/null
shallow_repo 3
check "on a shallow clone that has the merge base, then a commit and its revert are an empty diff, not a refusal" \
  '[[ "$(git rev-parse --is-shallow-repository)" == true ]] && one_refusal "no independent review" "$r" check'

# ── Spec 003: record removes the reviewer's copy when it is surely the one made for this review ──
rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/out" "$TMP/linked"; cd "$TMP"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo a > a.txt; git add a.txt; git commit --quiet -m "feat: a"
author() { git status --porcelain -- . ':(exclude).claude/worktrees'; }
# copy <name> [<commit>] [detach]: a worktree like Claude Code's, with an uncommitted change in it.
copy() {
  git worktree add --quiet -b "worktree-$1" ".claude/worktrees/$1" "${2:-HEAD}"
  if [[ "${3:-}" == detach ]]; then git -C ".claude/worktrees/$1" checkout --quiet --detach; fi
  echo wip > ".claude/worktrees/$1/wip.txt"
}
# copy_report <Copy: value> [plan]: a ready report naming that copy.
copy_report() {
  if [[ "${2:-}" == plan ]]; then printf 'Copy: %s\nPlan state: %s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$1" "$("$r" state --plan)" > "$TMP/report.md"
  else printf 'What changed: x\n\nCopy: %s\n%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$1" "$(range)" > "$TMP/report.md"; fi
}
before="$(author)"
copy agent-x; copy_report "$PWD/.claude/worktrees/agent-x"
check "when a task report names .claude/worktrees/agent-x on worktree-agent-x at the reviewed commit, with an uncommitted change in it, then record removes it and its branch and says so" \
  'out="$("$r" record "$TMP/report.md" 2>&1)" && grep -q "^REVIEW=ready" <<<"$out" && grep -qF "landspec: removed the reviewer'"'"'s copy $PWD/.claude/worktrees/agent-x" <<<"$out" && [[ ! -e .claude/worktrees/agent-x ]] && ! git show-ref --quiet refs/heads/worktree-agent-x'
check "when the same report is recorded twice, then the second prints no error and removes nothing" \
  'out="$("$r" record "$TMP/report.md" 2>&1)" && [[ "$out" != *"reviewer'"'"'s copy"* ]]'
prev="$(git rev-parse HEAD)"; echo b >> a.txt; git commit --quiet -am "fix: b"
copy agent-d HEAD detach
printf 'Copy: %s\nDelta from: %s\nReviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$PWD/.claude/worktrees/agent-d" "$prev" "$prev" "$(git rev-parse HEAD)" > "$TMP/report.md"
check "when a delta report names a detached agent-d copy at the reviewed commit, then record --delta removes it" \
  'out="$("$r" record --delta "$TMP/report.md" 2>&1)" && grep -qF "removed the reviewer'"'"'s copy" <<<"$out" && [[ ! -e .claude/worktrees/agent-d ]]'
copy agent-p; copy_report "$PWD/.claude/worktrees/agent-p" plan
check "when a plan report names an agent-p copy at HEAD, then record --plan removes it" \
  'out="$("$r" record --plan "$TMP/report.md" 2>&1)" && grep -qF "removed the reviewer'"'"'s copy" <<<"$out" && [[ ! -e .claude/worktrees/agent-p ]]'
copy_report "none (running in $PWD)"
check "when the report says Copy: none (...), then record prints and removes nothing about a copy" \
  'out="$("$r" record "$TMP/report.md" 2>&1)" && [[ "$out" != *"reviewer'"'"'s copy"* ]]'
report ready
check "when the report has no Copy: line, then record works as before" \
  'out="$("$r" record "$TMP/report.md" 2>&1)" && grep -q "^REVIEW=ready" <<<"$out" && [[ "$out" != *"reviewer'"'"'s copy"* ]]'
# Each of these is left, with a line saying so, and the record still succeeds.
copy feature
copy agent-y HEAD~1
mkdir -p .claude/worktrees/agent-m; echo m > .claude/worktrees/agent-m/f
mkdir -p "$TMP/out/.claude/worktrees"; git worktree add --quiet -b worktree-agent-o "$TMP/out/agent-o" HEAD
for lc in "a listed worktree .claude/worktrees/feature on worktree-feature|$PWD/.claude/worktrees/feature" \
  "an agent-y worktree at another commit|$PWD/.claude/worktrees/agent-y" "the repository root|$PWD" \
  "an agent-o worktree outside .claude/worktrees/|$TMP/out/agent-o" "a folder made with mkdir under .claude/worktrees/|$PWD/.claude/worktrees/agent-m"; do
  c="${lc#*|}"; copy_report "$c"
  check "when the report names ${lc%%|*}, then record succeeds, leaves it and says so" \
    'out="$("$r" record "$TMP/report.md" 2>&1)" && grep -q "^REVIEW=ready" <<<"$out" && grep -qF "landspec: left the reviewer'"'"'s copy $c (" <<<"$out" && [[ -d "$c" ]]'
done
check "then every left copy keeps its files" \
  '[[ -f .claude/worktrees/feature/wip.txt && -f .claude/worktrees/agent-y/wip.txt && -f .claude/worktrees/agent-m/f && -d "$TMP/out/agent-o" ]]'
check "then the author's git status is the same as before (copies aside)" '[[ "$(author)" == "$before" ]]'
# The author works in a linked worktree: Claude Code puts the copy under the main worktree's .claude/worktrees.
git worktree add --quiet -b feat/001-t001-linked "$TMP/linked" HEAD
main="$PWD"; cd "$TMP/linked"
git worktree add --quiet -b worktree-agent-l "$main/.claude/worktrees/agent-l" HEAD
copy_report "$main/.claude/worktrees/agent-l"
check "when the author's checkout is a linked worktree, then a copy under the main worktree's .claude/worktrees is removed" \
  'out="$("$r" record "$TMP/report.md" 2>&1)" && grep -qF "removed the reviewer'"'"'s copy" <<<"$out" && [[ ! -e "$main/.claude/worktrees/agent-l" ]]'
cd "$main"

# ── Spec 004 T002: a stacked branch is diffed against its parent; any branch is read by name ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5
- [ ] T002 Add filters in `src/filters.ts` — #6'
P=feat/001-t001-add-search; C=feat/001-t002-add-filters
"$SCRIPTS/branch.sh" T001 >/dev/null 2>&1
mkdir -p .github/workflows; echo 'on: push' > .github/workflows/x.yml; git add .github; git commit --quiet -m "ci: parent change"
printf -- '- deep: .github/workflows/x.yml — ci: read\n\n%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(range)" > "$TMP/report.md"
"$r" record "$TMP/report.md" >/dev/null
"$SCRIPTS/branch.sh" T002 --from "$P" >/dev/null 2>&1
echo 'export const f = 1' > filters.ts; git add filters.ts; git commit --quiet -m "feat: filters"
check "on a stacked branch, then review.sh risk covers only its own commit (not the parent's workflow)" \
  '[[ "$("$r" risk)" == "RISK=none" ]]'
printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(git merge-base HEAD origin/develop)" "$(git rev-parse HEAD)" > "$TMP/report.md"
check "on a stacked branch, then a report reviewed from the base's merge base is refused with the existing message" \
  'fails_with "the report must state Reviewed: <from>..<head>" "$r" record "$TMP/report.md"'
printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$(git merge-base HEAD "$P")" "$(git rev-parse HEAD)" > "$TMP/report.md"
check "on a stacked branch, then a report reviewed from the merge base with the parent is recorded" \
  '"$r" record "$TMP/report.md" 2>/dev/null | grep -q "^REVIEW=ready"'
export SCRIPTS; id_on="$(bash -c 'source "$SCRIPTS/lib.sh"; diff_id')"; ck_on="$("$r" check 2>&1 || true)"; git switch --quiet --detach
check "from a detached HEAD, then review.sh check --branch <b> gives the same answer as on <b>" \
  '[[ "$("$r" check --branch "$C" 2>&1 || true)" == "$ck_on" && "$ck_on" == REVIEW=ready ]] && fails_with "no branch" "$r" check --branch feat/001-t009-none'
check "from a detached HEAD, then diff_id <b> equals diff_id run on <b>" \
  '[[ "$(bash -c "source \"$SCRIPTS/lib.sh\"; diff_id \"$C\"")" == "$id_on" && -n "$id_on" ]]'
check "from a detached HEAD without --branch, then check still refuses as before" 'fails_with "detached HEAD" "$r" check'
# /landspec:implement records a fix round of a branch checked out in another copy.
hc="$(git rev-parse "$C")"; git switch --quiet "$C"; echo 'export const g = 1' >> filters.ts; git commit --quiet -am "fix: filters"
hf="$(git rev-parse HEAD)"; git switch --quiet "$P"
printf 'Delta from: %s\nReviewed: %s..%s\nModel: claude-sonnet-4-7\n\nAssessment: ready\n' "$hc" "$hc" "$hf" > "$TMP/report.md"
check "from another branch, then record --delta --branch <b> records the fix round of <b>, and check --branch <b> passes" \
  'out="$("$r" record --delta --branch "$C" "$TMP/report.md")" && [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$hf")" ]] && "$r" check --branch "$C" >/dev/null'
git switch --quiet -c spec/001-demo origin/develop
check "on a spec branch (pr.sh spec mode), then base_ref is the base: it never has a parent" '[[ "$(bash -c "source \"$SCRIPTS/lib.sh\"; base_ref")" == origin/develop ]]'
git switch --quiet "$P"
check "on the parent (no parent of its own), then base_ref is still the base" '[[ "$(bash -c "source \"$SCRIPTS/lib.sh\"; base_ref")" == origin/develop ]]'

# ── FR-014 (#216): a delta counts the fix round's own lines, not a merge of the base ──
rm -rf "$TMP/origin.git" "$TMP/repo"; cd "$TMP"
new_repo standard
commit_tasks '- [ ] T001 Add search in `src/search.ts` — #5'
"$SCRIPTS/branch.sh" T001 >/dev/null
echo 'export const search = 1' > search.ts; echo task > c.txt; git add search.ts c.txt; git commit --quiet -m "feat: search"
rep "changes needed" "${all[@]}" "Findings:" "- High: search.ts:1 the search is wrong"
"$r" record "$TMP/report.md" >/dev/null || true; h1="$(git rev-parse HEAD)"; cp "$TMP/report.md" "$TMP/full.md"
# to_base <file> <n>: a commit of <n> lines in <file> on the base (develop), as another task's merged PR.
to_base() { git switch --quiet main; seq 1 "$2" > "$1"; git add "$1"; git commit --quiet -m "feat: $1"; git push --quiet origin main:develop; git switch --quiet -; git fetch --quiet origin; }
# fix <n>: a commit of <n> lines in fix.ts, outside the findings' files.
fix() { seq 1 "$1" | sed 's/^/export const f/; s/$/ = 1/' > fix.ts; git add fix.ts; git commit --quiet -m "fix: $1 lines"; }
to_base big.txt 300; git merge --quiet --no-edit origin/develop >/dev/null; hm="$(git rev-parse HEAD)"
# A git that has no merge-tree --write-tree (before 2.38), for the fallback.
mkdir -p "$TMP/oldgit"; real_git="$(command -v git)"
printf '#!/usr/bin/env bash\n[[ "$1 $2" == "merge-tree --write-tree" ]] && { echo "error: unknown option" >&2; exit 129; }\nexec "%s" "$@"\n' "$real_git" > "$TMP/oldgit/git"; chmod +x "$TMP/oldgit/git"
fix 5; drep ready "$h1"
check "on a git without merge-tree --write-tree, when the base (300 lines) was merged in and a 5-line fix follows, then the delta counts from the last review, as before" \
  'PATH="$TMP/oldgit:$PATH" fails_with "the delta changes 305 lines outside the previous findings (limit 20)" "$r" record --delta "$TMP/report.md"'
if git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
  # Refusals first: an accepted delta moves the record on, so each one ends a setup.
  git reset --quiet --hard "$hm"; fix 30; drep ready "$h1"
  check "when the base (300 lines) was merged in and a 30-line fix follows, then record --delta refuses, counting the 30 lines only" \
    'fails_with "the delta changes 30 lines outside the previous findings (limit 20)" "$r" record --delta "$TMP/report.md"'
  git reset --quiet --hard "$hm"; git switch --quiet -c side main; seq 1 25 > side.txt; git add side.txt; git commit --quiet -m side
  git switch --quiet -; git merge --quiet --no-edit side >/dev/null; drep ready "$h1"
  check "when a branch other than the base (25 lines) is merged in after the base, then record --delta refuses, counting its 25 lines" \
    'fails_with "the delta changes 25 lines outside the previous findings (limit 20)" "$r" record --delta "$TMP/report.md"'
  git reset --quiet --hard "$hm"; fix 5; drep ready "$h1"
  check "when the base (300 lines) was merged in since the full review and a 5-line fix follows, then record --delta gives REVIEW=ready" \
    'out="$("$r" record --delta "$TMP/report.md")"; [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$(git rev-parse HEAD)")" ]]'
  # The base adds c.txt too: the merge conflicts, and its resolution is 3 lines of neither side.
  git reset --quiet --hard "$h1"; "$r" record "$TMP/full.md" >/dev/null || true
  to_base c.txt 1; git merge --quiet --no-edit origin/develop >/dev/null 2>&1 || true
  printf 'r1\nr2\nr3\n' > c.txt; git add c.txt; git commit --quiet --no-edit; hc="$(git rev-parse HEAD)"; fix 13; drep ready "$h1"
  # The resolution replaces merge-tree's conflicted c.txt (5 lines: both sides and 3 markers): 5 + 3 lines, plus the fix.
  check "when a base merge's conflict is resolved by 3 lines of its own and a 13-line fix follows, then record --delta refuses, counting the resolution's lines with the fix's" \
    'fails_with "the delta changes 21 lines outside the previous findings (limit 20)" "$r" record --delta "$TMP/report.md"'
  git reset --quiet --hard "$hc"; fix 12; drep ready "$h1"
  check "when the same resolution is followed by a 12-line fix, then record --delta gives REVIEW=ready (20 lines, the limit)" \
    'out="$("$r" record --delta "$TMP/report.md")"; [[ "$out" == "$(printf "REVIEWED=%s\nREVIEW=ready" "$(git rev-parse HEAD)")" ]]'
else
  echo "skip - base-merge delta counts (this git has no merge-tree --write-tree); the count from the last review is checked above"
fi

exit "$FAIL"
