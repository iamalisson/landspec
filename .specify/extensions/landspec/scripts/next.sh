#!/usr/bin/env bash
# Show a feature's progress and the next task to build.
#   next.sh [feature]    feature: a number (002) or folder name (002-reports); it becomes the active one
# tasks.md and the landing commits are read from the feature branch (local, else origin's; before
# it exists, the checkout's tasks.md). A task is done when that branch holds its landing commit
# (Landspec-Task: <NNN>/Tnnn, lib.sh task_done), failed when its run record says so, waiting while a task its line
# "depends on" is not done, else pending. No GitHub issue is read.
# Prints "done|failed|pending|waiting Tnnn <summary>" per task, then
# FEATURE=<num> BRANCH=<branch> ISSUE=<#N|-> PR=<url|->, then DONE=x/y NEXT=<first pending Tnnn, or empty>.
# A legacy feature (a task line ends in " — #N") named here prints LEGACY=<name> and stops.
# With no argument on a task ref or a feature branch, it serves that branch's feature. Otherwise,
# legacy features left out, with several features that have a task to build it prints one
# "feature <name> DONE=x/y" line each and CHOOSE=<names>; run it again with the chosen one.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

landspec_cd_root
command -v gh >/dev/null || die "the GitHub CLI (gh) is required: https://cli.github.com"
# Another clone's landings reach origin's copy of the branch only with a fetch.
git fetch --quiet origin 2>/dev/null || echo "landspec: warning: cannot fetch origin; showing the last fetched state" >&2

# scan <feature dir> <print>: one line per task when print=true; sets DONE_N TOTAL NEXT_ID TASKS
scan() {
  local fdir="$1" show="$2" rdir line id state f fh d
  rdir="$(git rev-parse --git-common-dir)/landspec-run/$(basename "$fdir")"
  TASKS="$(git show "$(feature_ref "$fdir"):$fdir/tasks.md" 2>/dev/null || cat "$fdir/tasks.md")"
  NEXT_ID=""; DONE_N=0; TOTAL=0
  while IFS= read -r line; do
    id="$(sed -E 's/^- \[.\] (T[0-9]{3,}) .*/\1/' <<<"$line")"
    TOTAL=$((TOTAL + 1))
    f="$(sed -n 's/^failed=//p' "$rdir/$id" 2>/dev/null || true)"
    fh="$(sed -n 's/^head=//p' "$rdir/$id" 2>/dev/null || true)"
    if task_done "$fdir" "$id"; then state="done"; DONE_N=$((DONE_N + 1))
    # as implement.sh status: a failure holds while its task ref is still at the failed head
    elif [[ -n "$f" && ( -z "$fh" || "$fh" == "$(git rev-parse --quiet --verify "refs/heads/landspec/$(feature_key "$fdir")-$(tr '[:upper:]' '[:lower:]' <<<"$id")-task" || true)" ) ]]; then state=failed
    else
      state=pending
      for d in $(grep -oiE 'depends on T[0-9]{3,}([, ]+(and )?T[0-9]{3,})*' <<<"$line" | grep -oE 'T[0-9]{3,}' || true); do
        task_done "$fdir" "$d" || state=waiting
      done
      [[ "$state" != pending ]] || NEXT_ID="${NEXT_ID:-$id}"
    fi
    if $show; then echo "$state $id $(task_summary "$line")"; fi
  done < <(grep -E '^- \[.\] T[0-9]{3,} ' <<<"$TASKS" || true)
}

if [[ -n "${1:-}" ]]; then
  fdir="$(resolve_feature "$1")"
  mkdir -p .specify; printf '{ "feature_directory": "%s" }\n' "$fdir" > .specify/feature.json
  refuse_legacy "$fdir"
elif fdir="$(branch_feature)" && [[ -n "$fdir" ]]; then
  : # on a task ref or feature branch, its feature (no feature.json: the branch decides on every call)
else
  # Several features with a task to build: say so instead of silently serving the last one touched.
  startable=(); summary=""; last=""
  while IFS= read -r d; do
    [[ -f "$d/tasks.md" ]] && ! legacy_feature "$d" || continue
    scan "$d" false; last="$d"
    summary+="feature $(basename "$d") DONE=$DONE_N/$TOTAL"$'\n'
    [[ -z "$NEXT_ID" ]] || startable+=("$(basename "$d")")
  done < <(find specs -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if ((${#startable[@]} > 1)); then
    printf '%s' "$summary"; echo "CHOOSE=${startable[*]}"; exit 0
  elif ((${#startable[@]} == 1)); then
    fdir="specs/${startable[0]}"
  else
    fdir="$(feature_dir)"
    # nothing to build anywhere: a legacy active feature gives way to a feature of this flow
    if legacy_feature "$fdir" && [[ -n "$last" ]]; then fdir="$last"; fi
    refuse_legacy "$fdir"
  fi
fi
[[ -f "$fdir/tasks.md" ]] || die "$fdir/tasks.md not found; run /speckit-tasks first"

scan "$fdir" true
fb="$(feature_branch "$fdir")"
issue="$(sed -nE 's/^\*\*Issue\*\*: #([0-9]+)[[:space:]]*$/\1/p' <<<"$TASKS" | head -1)"
pr="$(gh pr list --head "$fb" --state open --json url,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)][0].url // empty')" \
  || die "cannot look up the feature's pull request; fix gh's error above"
echo "FEATURE=$(feature_key "$fdir") BRANCH=$fb ISSUE=${issue:+#}${issue:--} PR=${pr:--}"
echo "DONE=$DONE_N/$TOTAL NEXT=$NEXT_ID"
