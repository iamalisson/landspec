#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
I="$SCRIPTS/implement.sh"
# ready <branch> [<findings>]: a recorded ready review of its head, recorded by name from here.
ready() {
  printf 'Reviewed: %s..%s\nModel: claude-sonnet-4-7\n%s\nAssessment: ready\n' \
    "$(git merge-base "refs/heads/$1" "$(bash -c 'source "$0/lib.sh"; base_ref "$1"' "$SCRIPTS" "$1")")" "$(git rev-parse "refs/heads/$1")" "${2:-}" > "$TMP/r.md"
  "$SCRIPTS/review.sh" record --branch "$1" "$TMP/r.md" >/dev/null
}
state_of() { sed -n "s/^TASK=$1 STATE=\([^ ]*\).*/\1/p" <<<"$out"; }
line_of() { grep "^TASK=$1 " <<<"$out"; }
cfg_set() { sed -i.bak "/^parallel_tasks:/d" .specify/extensions/landspec/landspec-config.yml; [[ -z "$1" ]] || echo "parallel_tasks: $1" >> .specify/extensions/landspec/landspec-config.yml; }
# ── The release tests' repo: rs_setup, mkb and squash ──
# rs_setup: a lite repo (base main) with T001, T002 (depends on T001), T003 (depends on T002).
rs_setup() {
  cd "$TMP"; rm -rf "$TMP/origin.git" "$TMP/repo" "$TMP/w"; : > "$GH_CLOSED"; : > "$GH_OPEN"; : > "$GH_LOG"
  new_repo lite; commit_tasks '- [ ] T001 Add search in `a` — #1
- [ ] T002 Add filters in `b` (depends on T001) — #2
- [ ] T003 Add ranking in `c` (depends on T002) — #3'
  DEV="$(git rev-parse HEAD)"; git worktree add --quiet --detach "$TMP/w" origin/main
}
# mkb <branch> <from> <file>: a pushed task branch with one file of its own.
mkb() {
  git -C "$TMP/w" switch --quiet -c "$1" "$2"; printf 'l1\nl2\nl3\nl4\nl5\n' > "$TMP/w/$3"
  git -C "$TMP/w" add -A; git -C "$TMP/w" commit --quiet -m "feat: $1"; git -C "$TMP/w" push --quiet origin "$1"; git -C "$TMP/w" switch --quiet --detach
}
squash() { # squash <branch> <issue>: squash-merge it into main on origin, as GitHub does
  git -C "$TMP/w" switch --quiet --detach origin/main; git -C "$TMP/w" merge --quiet --squash "refs/heads/$1" >/dev/null
  git -C "$TMP/w" commit --quiet -m "squash $1"; git -C "$TMP/w" push --quiet origin HEAD:refs/heads/main; git -C "$TMP/w" switch --quiet --detach
  git fetch --quiet origin; echo "$2" >> "$GH_CLOSED"
}
B1=feat/001-t001-add-search-in-a; B2=feat/001-t002-add-filters-in-b; B3=feat/001-t003-add-ranking-in-c
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
  git switch --quiet --detach origin/main; git branch --quiet -f main origin/main; git switch --quiet main; DEV="$(git rev-parse HEAD)"
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

# ── Spec 008 T022: once the feature PR is merged, implement runs the release, not the end check ──
if command -v jq >/dev/null; then # GH_PR_JSON runs the script's own --jq
  fp_setup "feat: one PR per feature" MERGED
  # GitHub's PRs as JSON: a fork's merged PR from a branch of the same name first (never ours), then fp_setup's.
  jq -R -s '[{number: 39, title: "feat: a fork", headRefName: "feat/001-demo", state: "MERGED", mergeCommit: {oid: "0000000000000000000000000000000000000000"}, mergedAt: "2026-11-13T10:00:00Z", isCrossRepository: true}]
    + (split("\n") | map(select(. != "") | split("\t") | {number: (.[0] | tonumber), title: .[1], headRefName: .[2], state: .[3],
       mergeCommit: (if .[4] == "" then null else {oid: .[4]} end), mergedAt: (if .[5] == "" then null else .[5] end), isCrossRepository: false}))' "$GH_REL" > "$TMP/merged.json"
  export GH_PR_JSON="$TMP/merged.json"
  # GitHub deleted the merged head branch; this clone keeps it, with no upstream, and has no plan review or analysis.
  fh="$(git rev-parse feat/001-demo)"; git branch --quiet -u origin/feat/001-demo feat/001-demo; git push --quiet origin --delete feat/001-demo; git fetch --quiet --prune origin
  remote() { git ls-remote origin | sort; }; r0="$(remote)"
  check "when the feature PR is merged and the clone is off the branch, then status prints MERGED=40 alone, past the other gates" \
    '[[ "$("$I" status 2>&1)" == MERGED=40 ]]'
  check "when the feature PR is merged and the branch has no upstream, then branch.sh refuses naming release-plan and pushes nothing" \
    'one_refusal "the feature PR #40 is merged: run implement.sh 001-demo release-plan" "$SCRIPTS/branch.sh" 001 && [[ "$(remote)" == "$r0" ]]'
  git switch --quiet feat/001-demo
  check "when the feature PR is merged, then check refuses naming release-plan, and the branch and origin are unchanged" \
    'one_refusal "the feature PR #40 is merged: run implement.sh 001-demo release-plan" "$I" check && [[ "$(git rev-parse HEAD)" == "$fh" && "$(remote)" == "$r0" ]]'
  rp
  check "then release-plan still prints bump 1.5.0 with PRS=40, the fork's PR left out" '[[ "$out" == "RELEASE=bump 1.5.0 FILES=package.json NOTES=- PRS=40" ]]'
  git switch --quiet main; git branch --quiet -D feat/001-demo
  check "when the merged branch is in neither this clone nor origin, then branch.sh refuses before creating it, and origin gains no branch" \
    'one_refusal "the feature PR #40 is merged" "$SCRIPTS/branch.sh" 001 && [[ "$(remote)" == "$r0" ]] && ! git show-ref --verify --quiet refs/heads/feat/001-demo && [[ "$(git branch --show-current)" == main ]]'
  unset GH_PR_JSON
fi

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
# release_audit: on (the default) or off; off skips the audit without fetching or reading a record.
ra() { sed -i.bak '/^release_audit:/d' .specify/extensions/landspec/landspec-config.yml; rm -f .specify/extensions/landspec/landspec-config.yml.bak; [[ -z "$1" ]] || echo "release_audit: $1" >> .specify/extensions/landspec/landspec-config.yml; }
ra on; ap
check "when release_audit is on, then audit-plan says needed as with the key absent" '[[ "$out" == "AUDIT=needed COMMIT=$c1" ]]'
ou="$(git remote get-url origin)"; git remote set-url origin "$TMP/no-such-origin"; ra off; ap; git remote set-url origin "$ou"
check "when release_audit is off, then audit-plan prints exactly the skipped line, with origin unreachable" '[[ "$out" == "AUDIT=skipped (release_audit: off)" ]]'
ra maybe
check "when release_audit is neither on nor off, then audit-plan refuses naming the key and the two values" 'fails_with "release_audit must be on or off" "$I" audit-plan'
ra ""
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
check "when the feature PR is open and none is merged, then status prints no MERGED=" '! grep -q "^MERGED=" <<<"$out" && grep -q "^DONE=" <<<"$out"'
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
# Tests once per tree: mark implemented needs run_tests' green record for the ref's head tree, from any copy.
fsetup; mkdir -p .specify/memory; printf 'echo run >> "%s/runs"\n' "$TMP" > "$TMP/count.sh"; : > "$TMP/runs"
printf '**Commands**: build `[BUILD_COMMAND]` · test `bash %s` · lint `[LINT_COMMAND]`\n' "$TMP/count.sh" > .specify/memory/constitution.md
build "$R1"
check "when T001's ref has no green test run for its head tree, then mark implemented refuses it naming the ref and its head" \
  'one_refusal "no green test run for $R1 at $(git rev-parse "refs/heads/$R1")" "$I" mark T001 implemented'
cp -R .specify "$TMP/w/"; git -C "$TMP/w" switch --quiet "$R1" # .specify is ignored, so not checked out there
(cd "$TMP/w" && source "$SCRIPTS/lib.sh" && run_tests >/dev/null); git -C "$TMP/w" switch --quiet --detach
check "when run_tests was green on that tree in the implementer's copy, then mark implemented accepts it" \
  '"$I" mark T001 implemented >/dev/null && [[ "$(wc -l < "$TMP/runs")" -eq 1 ]]'
build "$R1"; printf '**Commands**: build `[BUILD_COMMAND]` · test `[TEST_COMMAND]` · lint `[LINT_COMMAND]`\n' > .specify/memory/constitution.md
check "when there is no test command, then mark implemented accepts a tree never tested" '"$I" mark T001 implemented >/dev/null'
# ── Spec 008 T013: the per-task modes are gone; status, the limits and the task record work on task refs ──
fsetup; plan_review >/dev/null 2>&1
for m in restack stack move check-copy; do
  check "when implement.sh <feature> $m runs, then it exits non-zero with the usage error, which names no per-task mode" \
    'fails_with "usage: implement.sh" "$I" 001 $m && ! "$I" 001 $m 2>&1 | grep -qE "restack|stack <|check-copy"'
done
git switch --quiet --detach
check "when status runs off the feature branch, then it refuses saying to switch to it" 'one_refusal "switch to it first (branch.sh 001-demo)" "$I" status'
git switch --quiet "$FB"
for v in 0 abc 17; do
  cfg_set "$v"
  check "when parallel_tasks is $v, then status dies with the exact message" \
    'fails_with "landspec: parallel_tasks must be a number from 1 to 16" "$I" status'
done
cfg_set ""
check "when gh cannot look up the feature's PR, then status stops with gh's error and prints no state" \
  'gf=0; o="$(GH_FAIL_PR_LIST=1 "$I" status 2>&1)" || gf=$?; ((gf != 0)) && grep -q "cannot look up the feature'"'"'s pull request" <<<"$o" && ! grep -q "^START=" <<<"$o"'
rec1() { sed -n "s/^$1=//p" "$(git rev-parse --git-common-dir)/landspec-run/001-demo/T001"; }
build "$R1"; "$I" mark T001 implemented >/dev/null
ph0="$(rec1 phase)"; h0="$(rec1 head)"; r0="$(rec1 round)"; "$I" mark T001 red >/dev/null; o2="$("$I" mark T001 red 2>&1)" || true; fs
check "when T001's tests are red twice after it said done, then red=2, with phase, head and round unchanged, and it is still built" \
  '[[ "$o2" == "MARKED=T001 PHASE=red RED=2" && "$(rec1 red)" == 2 && "$(rec1 phase)" == "$ph0" && "$(rec1 head)" == "$h0" && "$(rec1 round)" == "$r0" && "$(state_of T001)" == built ]]'
"$I" mark T001 implemented >/dev/null
check "when T001 is then marked implemented, then red= is gone" '[[ -z "$(rec1 red)" ]]'
"$I" mark T001 red >/dev/null; "$I" retry T001 >/dev/null
check "when T001 is red and then retried, then red= is gone" '[[ -z "$(rec1 red)" ]]'
build "$R1"; echo findings > "$TMP/r.md"; "$I" mark T001 changes "$TMP/r.md" >/dev/null; "$I" mark T001 changes "$TMP/r.md" >/dev/null
build "$R1"; "$I" mark T001 changes "$TMP/r.md" >/dev/null; fs
check "when a new commit lifts a review-rounds failure, then the next changes starts the rounds again (changes, not failed)" \
  'line_of T001 | grep -qx "TASK=T001 STATE=changes ROUND=1"'
check "then mark is logged with the task ref named" \
  'grep -qE " mark task=T001 phase=changes round=1 branch=$R1$" "$(git rev-parse --git-common-dir)/landspec-events"'
"$I" fail T003 "no idea" >/dev/null; build "$R3"; fs
check "when a task failed before its ref existed, then it stays failed after a commit on the ref, until retry" \
  'line_of T003 | grep -qx "TASK=T003 STATE=failed REASON=no idea" && grep -qE " fail task=T003 branch=$" "$(git rev-parse --git-common-dir)/landspec-events"'
"$I" retry T003 >/dev/null; fs
check "then retry lifts it, and its ref is gone, so it starts again from the feature head" '[[ "$(state_of T003)" == pending ]] && grep -qx "START=T003 REF=$R3 FROM=$(head_fb)" <<<"$out"'

# ── Spec 008 T008: the end check runs on the feature branch itself ──
ck() { out="$("$I" check 2>&1)" || true; }
ER() { echo "$(git rev-parse --git-common-dir)/landspec-review/feature-001-demo"; } # the end-check record
landed() { build "$2"; "$I" mark "$1" implemented >/dev/null; ready "$2"; "$I" mark "$1" ready >/dev/null; "$I" land "$1" >/dev/null 2>&1; }
fcommit() { printf '%s\n' "${2:-$RANDOM}" >> "$1"; git add "$1"; git commit --quiet -m "fix: $1"; }
# erep <line>: a feature review of the check ref (Copy: none: no check copy), base origin/develop.
erep() {
  printf -- '%s\nCopy: none (the main session)\nReviewed: %s..%s\nModel: claude-opus-5-5\n\nAssessment: ready\n' "$1" \
    "$(git rev-parse origin/develop)" "$(git rev-parse refs/landspec/check/001-demo)" > "$TMP/e.md"
  "$SCRIPTS/review.sh" record --feature "$TMP/e.md" 2>&1
}
fsetup; plan_review >/dev/null 2>&1; landed T001 "$R1"
check "when a task is not done, then check refuses naming it and points no check ref" \
  'one_refusal "T002 is not done" "$I" check && ! git show-ref --quiet refs/landspec/check/001-demo'
landed T002 "$R2"; landed T003 "$R3"; h1="$(head_fb)"; ck
check "when every task is done, then check prints CHECK=<head> ROUND=1 and the check ref points at the head" \
  '[[ "$out" == "CHECK=$h1 ROUND=1" && "$(git rev-parse refs/landspec/check/001-demo)" == "$h1" ]]'
check "then the end-check record holds head:, heads: and tests: pending" \
  '[[ "$(head -3 "$(ER)")" == "head: $h1"$'"'"'\n'"'"'"heads: $h1"$'"'"'\n'"'"'"tests: pending" ]]'
printf 'round=1\ncombo=x\noutcome=\n' > "$(ER)-round"; "$I" check-result red >/dev/null
check "when a round file still waits for its outcome, then check-result still sets tests: in the end-check record" 'grep -qx "tests: red" "$(ER)"'
rm -f "$(ER)-round"; ck
check "when check-result red then check on the same head, then UNCHANGED=1" '[[ "$out" == UNCHANGED=1 ]] && grep -qx "tests: red" "$(ER)"'
fcommit gap.txt; h2="$(head_fb)"; ck
check "when a new commit is on the branch, then check prints ROUND=2 and heads: lists both heads" \
  '[[ "$out" == "CHECK=$h2 ROUND=2" ]] && grep -qx "heads: $h1 $h2" "$(ER)" && grep -qx "tests: pending" "$(ER)"'
"$I" check-result green >/dev/null; erep '- not met: FR-001 — nothing searches' >/dev/null; ck
check "when this head is green but its own review has a not met line, then check prints UNCHANGED=2" '[[ "$out" == UNCHANGED=2 ]]'
git -C "$TMP/w" switch --quiet --detach origin/develop; echo base > "$TMP/w/base.txt"; git -C "$TMP/w" add base.txt
git -C "$TMP/w" commit --quiet -m "chore: on the base"; git -C "$TMP/w" push --quiet origin HEAD:develop; bc="$(git -C "$TMP/w" rev-parse HEAD)"
git -C "$TMP/w" switch --quiet --detach "$FB"; ck; h3="$(head_fb)"
check "when the base has a new commit, then check merges it into the branch first, pushes, and checks the merge: ROUND=3" \
  '[[ "$out" == "CHECK=$h3 ROUND=3" && "$(git rev-parse "$h3^1")" == "$h2" && "$(git rev-parse "$h3^2")" == "$bc" ]] \
   && [[ "$(git ls-remote origin "refs/heads/$FB" | cut -f1)" == "$h3" && "$(git rev-parse refs/landspec/check/001-demo)" == "$h3" ]]'
"$I" check-result green >/dev/null; eo="$(erep '- met: FR-001 — search.ts searches')"
check "after check, check-result green and a ready record --feature, then the record still holds tests: green, the verdict, reviewed: the head and the lines" \
  'grep -qx "REVIEW=ready" <<<"$eo" && f="$(ER)" && grep -qx "head: $h3" "$f" && grep -qx "tests: green" "$f" && grep -qx "verdict: ready" "$f" \
   && grep -qx "reviewed: $h3" "$f" && grep -qx -- "- met: FR-001 — search.ts searches" "$f" && [[ ! -e "$f-round" ]]'
eo="$(erep $'- met: FR-001 — a\n- not verifiable: SC-001 — needs a timed run')"
check "when a feature review has only met and not verifiable lines, then it records ready" 'grep -qx "REVIEW=ready" <<<"$eo"'
eo="$(erep $'- met: FR-001 — a\n- not met: FR-002 — nothing does it')"
check "when a feature review has a not met line, then it records changes needed, whatever its last line says" 'grep -qx "REVIEW=changes needed" <<<"$eo"'
check "when record --feature is given with --plan, then it is refused" 'fails_with "a feature review is recorded alone" "$SCRIPTS/review.sh" record --feature --plan "$TMP/e.md"'
fcommit gap.txt; ck
check "when a fourth head comes past feature_rounds (3), then check prints ROUNDS_EXHAUSTED=3 and leaves the ref" \
  '[[ "$out" == ROUNDS_EXHAUSTED=3 && "$(git rev-parse refs/landspec/check/001-demo)" == "$h3" ]]'
git reset --quiet --hard "$h3"; git -C "$TMP/w" switch --quiet --detach origin/develop; echo more > "$TMP/w/more.txt"; git -C "$TMP/w" add more.txt
git -C "$TMP/w" commit --quiet -m "chore: more on the base"; git -C "$TMP/w" push --quiet origin HEAD:develop; git -C "$TMP/w" switch --quiet --detach; ck
check "when the rounds are spent and only the base moved, then check prints ROUNDS_EXHAUSTED=3 before merging: the branch and origin stay at the last head" \
  '[[ "$out" == ROUNDS_EXHAUSTED=3 && "$(head_fb)" == "$h3" && "$(git ls-remote origin "refs/heads/$FB" | cut -f1)" == "$h3" ]]'
echo "feature_rounds: 9" >> .specify/extensions/landspec/landspec-config.yml
fcommit clash.txt mine; git -C "$TMP/w" switch --quiet --detach origin/develop; echo theirs > "$TMP/w/clash.txt"; git -C "$TMP/w" add clash.txt
git -C "$TMP/w" commit --quiet -m "chore: clash"; git -C "$TMP/w" push --quiet origin HEAD:develop; git -C "$TMP/w" switch --quiet --detach; h4="$(head_fb)"
check "when the base has a conflicting commit, then check stops naming the file and leaves the branch as it was" \
  'one_refusal "clash.txt" "$I" check && [[ "$(head_fb)" == "$h4" && -z "$(git status --porcelain --untracked-files=no)" ]] && ! git rev-parse --verify --quiet MERGE_HEAD >/dev/null'

exit "$FAIL"
