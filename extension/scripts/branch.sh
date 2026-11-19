#!/usr/bin/env bash
# Switch to the feature's one branch, <branch_prefix>/<NNN>-<short-name>, creating it if needed.
# Usage: branch.sh [feature]   feature: a number (002) or folder name, else the active one
#   A new one starts from the base with the spec folder's current content committed on it, and is
#   pushed to origin at once. Tasks are built on the feature branch, never on a branch of their own.
#   Prints: BRANCH=<name> FEATURE=<NNN> BASE=<base>. Once the feature PR is merged, it neither makes
#   nor pushes the branch: it refuses, naming implement.sh release-plan.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

feature=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    T[0-9]*) die "branch.sh takes a feature, not a task: tasks are built on the feature branch" ;;
    -*) die "usage: branch.sh [feature]" ;;
    *) [[ -z "$feature" ]] || die "usage: branch.sh [feature] (one feature at most)"; feature="$1" ;;
  esac; shift
done
landspec_cd_root

if [[ -n "$feature" ]]; then fdir="$(resolve_feature "$feature")"
# Follows what /speckit-specify just wrote, never the branch it ran on (a task ref included).
elif fdir="$(sed -n 's/.*"feature_directory": *"\([^"]*\)".*/\1/p' .specify/feature.json 2>/dev/null)" && [[ -n "$fdir" && -d "$fdir" ]]; then :
else fdir="$(feature_dir)"; fi

name="$(basename "$fdir")"
refuse_legacy "$fdir"
base="$(base_branch)"; branch="$(feature_branch "$fdir")"
if [[ "$(git branch --show-current)" != "$branch" ]]; then
  # The spec folder travels with us; anything else uncommitted is refused before any switch.
  [[ -z "$(git status --porcelain -- . ":(exclude)$fdir" ':(exclude).claude/worktrees')" ]] || die "uncommitted changes on '$(git branch --show-current)'; commit or stash them first"
  git fetch --quiet origin 2>/dev/null || true
  stuck="cannot switch to $branch: uncommitted changes in $fdir conflict with it; commit or stash them first"
  if git show-ref --verify --quiet "refs/heads/$branch"; then git switch --quiet "$branch" || die "$stuck"
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then git switch --quiet --track "origin/$branch" || die "$stuck"
  else
    if git show-ref --verify --quiet "refs/remotes/origin/$base"; then from="origin/$base"
    elif git show-ref --verify --quiet "refs/heads/$base"; then from="$base"
    else die "base branch '$base' does not exist; run /landspec:level to set up the branch flow"
    fi
    refuse_merged "$fdir" # GitHub deleted the merged branch: never make it again
    carry_switch "$fdir" "$branch" --no-track -c "$branch" "$from"
    git add -- "$fdir"
    git diff --cached --quiet || git commit --quiet -m "docs(specs): add $name spec"
    event start feature="$name"
  fi
fi
# A branch made here but never pushed (origin was down) is pushed on the next run.
# Its upstream is also gone once GitHub deleted the merged branch: that one is never pushed back.
git rev-parse --quiet --verify '@{u}' >/dev/null 2>&1 \
  || { refuse_merged "$fdir"; git push --quiet -u origin "$branch"; } || die "could not push $branch to origin; run branch.sh again once origin is reachable"
mkdir -p .specify
printf '{ "feature_directory": "%s" }\n' "$fdir" > .specify/feature.json
echo "BRANCH=$branch FEATURE=$(feature_key "$fdir") BASE=$base"
