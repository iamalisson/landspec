#!/usr/bin/env bash
# Create one GitHub issue per task in the active feature's tasks.md and append "— #N" to its line.
# Idempotent: tasks that already end in "— #N" are skipped. With --sync, the open issue of each such
# task gets its body rewritten from the task's current sub-bullets (edits made on GitHub are lost).
# Usage: issues.sh [--dry-run|--sync]
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

dry=false sync=false
case "${1:-}" in --dry-run) dry=true ;; --sync) sync=true ;; "") ;; *) die "usage: issues.sh [--dry-run|--sync]" ;; esac
landspec_cd_root
command -v gh >/dev/null || die "the GitHub CLI (gh) is required: https://cli.github.com"

fdir="$(feature_dir)"
tasks="$fdir/tasks.md"
[[ -f "$tasks" ]] || die "$tasks not found; run /speckit-tasks first"
# The plan review (/speckit-landspec-review, plan mode) has to have read this tasks.md: issue bodies
# are the task lines, so they are right before any issue exists. Its model warning, if any, is said here too.
if ! $dry; then
  bash "$LANDSPEC_EXT_DIR/scripts/review.sh" report --plan | sed -n 's/^warning: /landspec: warning: /p' >&2
fi
base="$(base_branch)"
feature="$(basename "$fdir")"
num="$(feature_key "$feature")"

IFS=',' read -ra labels <<<"$(cfg issue_labels "type:task")"
if ! $dry; then
  for l in ${labels[@]+"${labels[@]}"}; do if [[ -n "$l" ]]; then gh label create "$l" >/dev/null 2>&1 || true; fi; done
fi
label_args=(); for l in ${labels[@]+"${labels[@]}"}; do if [[ -n "$l" ]]; then label_args+=(--label "$l"); fi; done

# A create that reached GitHub but failed on the client left an open issue with the task's exact
# title: reuse it. No --search or --label: they switch gh to the search API, which lags behind.
# shortcut: 1000 open issues, the newest first; page through them if a repo ever has more open
existing=""
if ! $dry; then
  existing="$(gh issue list --state open --limit 1000 --json number,title --jq '.[] | "\(.number) \(.title)"')" \
    || die "cannot list the repository's issues to avoid duplicates"
fi

# link <task line> <n>: append "— #n" to that line, at once, so an interrupted run never creates
# duplicates.
link() {
  L="$1" S=" — #$2" awk '!done && $0 == ENVIRON["L"] { print $0 ENVIRON["S"]; done = 1; next } { print }' \
    "$tasks" > "$tasks.tmp" && mv "$tasks.tmp" "$tasks"
}

created=0; skipped=0; updated=0; reused=0
while IFS= read -r line; do
  id="$(sed -E 's/^- \[.\] (T[0-9]{3,}) .*/\1/' <<<"$line")"
  linked="$(task_issue "$line")"
  if [[ -n "$linked" ]] && ! $sync; then skipped=$((skipped + 1)); continue; fi

  desc="$(task_desc "$line")"
  title="[$num] $id: $(task_summary "$line")"
  [[ ${#title} -gt 120 ]] && title="${title:0:117}..."
  comes="$(task_field "$fdir" "$id" "Comes from")"
  what="$(task_field "$fdir" "$id" "What")"
  done_when="$(task_field "$fdir" "$id" "Completed when")"
  impact="$(task_field "$fdir" "$id" "Impact")"
  body="**Feature:** \`$feature\` · **Task:** $id in [\`tasks.md\`](../blob/$base/$tasks)

**Task:** $desc"
  [[ -n "$comes" ]] && body+=$'\n\n'"**Comes from:** $comes"
  [[ -n "$what" ]] && body+=$'\n\n'"**What:** $what"
  [[ -n "$impact" ]] && body+=$'\n\n'"**Impact:** $impact"
  [[ -n "$done_when" ]] || done_when="_its tests pass and the change is verified as plan.md describes._"
  body+=$'\n\n'"**Completed when:** $done_when"
  body+=$'\n\n---\n'"**Done** = closed by the merged PR (\`Closes #N\`). Start it with \`/speckit-implement $id\`."

  if [[ -n "$linked" ]]; then
    # --sync: closed issues are history and stay as they are.
    cur="$(gh issue view "$linked" --json state,body --jq '.state + "\n" + .body')" || die "cannot read issue #$linked"
    if [[ "${cur%%$'\n'*}" == OPEN && "${cur#*$'\n'}" != "$body" ]]; then
      gh issue edit "$linked" --body "$body" >/dev/null || die "cannot update issue #$linked"
      echo "$id → #$linked (updated)"; updated=$((updated + 1))
    else skipped=$((skipped + 1)); fi
    continue
  fi
  if $dry; then echo "would create: $title"; created=$((created + 1)); continue; fi
  n="$(T="$title" awk '{ n = $1; sub(/^[^ ]+ /, ""); if ($0 == ENVIRON["T"]) { print n; exit } }' <<<"$existing")"
  if [[ -n "$n" ]]; then
    link "$line" "$n"; add_meta issue "$n"
    echo "$id → #$n (existing)"; skipped=$((skipped + 1)); reused=$((reused + 1)); continue
  fi
  url="$(gh issue create --title "$title" --body "$body" ${label_args[@]+"${label_args[@]}"})"
  n="${url##*/}"
  link "$line" "$n"
  add_meta issue "$url"
  echo "$id → #$n"
  created=$((created + 1))
done < <(grep -E '^- \[.\] T[0-9]{3,} ' "$tasks")

# stats.sh times the plan phase to the first run that created or linked an issue (a reused one was created by an earlier run).
if ! $dry && ((created + reused > 0)); then event issues feature="$feature" created="$((created + reused))"; fi
echo "CREATED=$created SKIPPED=$skipped UPDATED=$updated"
