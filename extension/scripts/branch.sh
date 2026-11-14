#!/usr/bin/env bash
# Switch to the branch for one task, creating it from the base branch if needed.
# Usage: branch.sh [feature] T003 [--from <branch>]   feature: a number (002) or folder name, else the active one
#   --from <branch>: a new branch starts from that task branch's reviewed head (a stack), not the base
# A new branch is pushed to origin at once, so the task shows as in progress to every clone.
# Prints: BRANCH=<name> ISSUE=<n> TASK=<id> BASE=<base>
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

task=""; feature=""; parent=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) parent="${2:-}"; [[ -n "$parent" ]] || die "usage: branch.sh [feature] T001 --from <branch>"; shift ;;
    T[0-9]*) [[ -z "$task" ]] || die "usage: branch.sh [feature] T001 (exactly one task ID)"; task="$1" ;;
    *) [[ -z "$feature" ]] || die "usage: branch.sh [feature] T001 (one feature at most)"; feature="$1" ;;
  esac; shift
done
[[ "$task" =~ ^T[0-9]{3,}$ ]] || die "usage: branch.sh [feature] T001 (exactly one task ID)"
landspec_cd_root

if [[ -n "$feature" ]]; then fdir="$(resolve_feature "$feature")"; else fdir="$(feature_dir)"; fi
line="$(task_line "$fdir" "$task")"
[[ -n "$line" ]] || die "$task not found in $fdir/tasks.md"
issue="$(task_issue "$line")"
[[ -n "$issue" ]] || die "$task has no issue yet (every task needs one); run /speckit-landspec-issues"

base="$(base_branch)"
git fetch --quiet origin 2>/dev/null || true
if git show-ref --verify --quiet "refs/remotes/origin/$base"; then from="origin/$base"
elif git show-ref --verify --quiet "refs/heads/$base"; then from="$base"
else die "base branch '$base' does not exist; run /landspec:level to set up the branch flow"
fi

# Task branches start from the base, so the spec, with this task's line, has to be merged there first.
on_base="$(git show "$from:$fdir/tasks.md" 2>/dev/null)" \
  || die "$fdir/tasks.md is not on '$base' yet; merge the spec PR first"
grep -qE "^- \[.\] $task " <<<"$on_base" \
  || die "$task is not in $fdir/tasks.md on '$base' yet; merge the spec PR first"

if [[ "$(landspec_level)" == full ]]; then
  marker="$(git rev-parse --git-common-dir)/landspec-analyzed/$(basename "$fdir")"
  want="$(git show "$from:$fdir/tasks.md" | sha256)"
  [[ -f "$marker" && "$(cat "$marker")" == "$want" ]] \
    || die "level 'full' requires /speckit-analyze on the current tasks.md before implementing"
fi

num="$(feature_key "$fdir")"
slug="$(task_summary "$line" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-' | tr -s '-' | sed 's/^-//; s/-$//' | cut -d- -f1-4)"
branch="$(cfg branch_prefix feat)/$num-$(tr '[:upper:]' '[:lower:]' <<<"$task")-$slug"

if [[ "$(git branch --show-current)" != "$branch" ]]; then
  # Never carry uncommitted work onto another task's branch.
  # A reviewer's copy (Claude Code puts it under .claude/worktrees) is not the author's work.
  [[ -z "$(git status --porcelain -- . ':(exclude).claude/worktrees')" ]] || die "uncommitted changes on '$(git branch --show-current)'; commit or stash them first"
  if git show-ref --verify --quiet "refs/heads/$branch"; then git switch --quiet "$branch"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then git switch --quiet --track "origin/$branch"
  else
    if [[ -n "$parent" ]]; then
      # A stack starts from the parent's reviewed head, read by name (it may be checked out elsewhere).
      git show-ref --verify --quiet "refs/heads/$parent" || die "--from $parent: no branch '$parent' in this clone"
      why="$(bash "$(dirname "$0")/review.sh" check --branch "$parent" 2>&1 >/dev/null)" \
        || die "--from $parent: its head has no recorded ready review ($(sed 's/^landspec: //' <<<"$why" | tail -1))"
      from="refs/heads/$parent"
    fi
    start="$(git branch --show-current)"; start_head="$(git rev-parse HEAD)"
    git switch --quiet --no-track -c "$branch" "$from"
    event start task="$task"
    if [[ -n "$parent" ]]; then
      git config "branch.$branch.landspec-parent" "$parent"
      d="$(git rev-parse --git-common-dir)/landspec-review"; mkdir -p "$d"
      git rev-parse "$from" > "$d/parent-head-${branch//\//__}"
    fi
    # The claim: an empty branch on origin tells every other clone's `next` this task is taken.
    # Of two clones starting the same task, only one wins: the lease refuses a branch already on
    # origin at another commit, and an up-to-date ref ("=": both claims are the same empty commit)
    # means another clone pushed it first.
    rc=0; err="$(git push --porcelain -u --force-with-lease="refs/heads/$branch:" origin "$branch" 2>&1)" || rc=$?
    if [[ $rc == 0 ]] && ! printf '%s\n' "$err" | grep -q '^='; then echo "claim: $branch pushed to origin" >&2
    elif [[ $rc == 0 ]] || git ls-remote --exit-code origin "refs/heads/$branch" >/dev/null 2>&1; then
      if [[ -n "$start" ]]; then git switch --quiet "$start"; else git switch --quiet --detach "$start_head"; fi
      git branch --quiet -D "$branch" # also drops its branch.<name>.* settings
      rm -f "$(git rev-parse --git-common-dir)/landspec-review/parent-head-${branch//\//__}"
      echo "landspec: $task was claimed elsewhere ($branch is on origin)" >&2; exit 3
    else echo "landspec: warning: could not claim $branch on origin: $(tr '\n' ' ' <<<"${err:-unknown error}" | sed 's/ *$//'); other clones may start this task" >&2
    fi
  fi
fi

# spec-kit's own /speckit-implement reads only this file (git-ignored, so a new worktree has none):
# point it at the task's feature, so landspec and spec-kit always work on the same one.
mkdir -p .specify
printf '{ "feature_directory": "%s" }\n' "$fdir" > .specify/feature.json

echo "BRANCH=$branch ISSUE=$issue TASK=$task BASE=$base"
