#!/usr/bin/env bash
# Find the pre-commit hooks that would rewrite most of the existing files (run by /landspec:adopt).
#   formatters.sh
# Runs each hook of .pre-commit-config.yaml with `pre-commit run --all-files <id>` in a throwaway
# worktree at HEAD, so the user's files are never touched. Prints, per hook:
#   REWRITES=<hook> <changed>/<covered>  the hook changed more than half of the files it covers
#   UNCHECKED=<hook> <reason>            the hook could not run (pre-commit's first error line)
# then FORMATTERS=checked <n> hooks, or FORMATTERS=skipped <why>. Always exits 0.
set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
landspec_cd_root
top="$(pwd -P)"
cfg_file=.pre-commit-config.yaml

[[ -f "$cfg_file" ]] || { echo "FORMATTERS=skipped no $cfg_file"; exit 0; }
command -v pre-commit >/dev/null || { echo "FORMATTERS=skipped pre-commit is not installed"; exit 0; }

tmp="$(mktemp -d)" || die "cannot create a temporary folder"
wt="$tmp/wt"
cleanup() { git worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$tmp"; git worktree prune >/dev/null 2>&1; }
trap cleanup EXIT # bash runs it on an interrupt or a TERM too
if ! err="$(git worktree add --quiet --detach "$wt" HEAD 2>&1)"; then
  echo "FORMATTERS=skipped cannot make a worktree at HEAD: $(grep -m1 . <<<"$err")"; exit 0
fi
wt="$(cd "$wt" && pwd -P)" || die "cannot enter the worktree $wt"

# A reset in the user's checkout would discard their work: refuse anything but the throwaway worktree.
reset_wt() {
  [[ -n "$wt" && "$wt" != "$top" && "$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)" == "$wt" ]] \
    || die "refusing to reset $wt: not the throwaway worktree"
  git -C "$wt" checkout -- . && git -C "$wt" clean -fdq
  # The working tree's config, even uncommitted, staged since pre-commit refuses an unstaged one.
  cp "$cfg_file" "$wt/$cfg_file" && git -C "$wt" add -- "$cfg_file"
}

# Files whose extension (or, with none, whose lack of one) is in the first list, counted in the second.
ext_count() {
  awk 'function ext(f) { sub(/.*\//, "", f); return match(f, /\.[^.]*$/) ? substr(f, RSTART) : "" }
       NR == FNR { e[ext($0)] = 1; next } (ext($0) in e) { n++ } END { print n + 0 }' "$1" "$2"
}

n=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  n=$((n + 1))
  reset_wt || { echo "UNCHECKED=$id cannot reset the worktree"; continue; }
  rc=0; out="$(cd "$wt" && pre-commit run --all-files "$id" 2>&1 </dev/null)" || rc=$?
  # pre-commit exits 1 both for a rewrite and for a hook that could not run: its output tells them apart.
  reason="$(grep -m1 -E 'Executable .* not found|An error has occurred|^\[ERROR\]' <<<"$out")"
  if [[ -z "$reason" && $rc != 0 && $rc != 1 ]]; then reason="$(grep -m1 . <<<"$out")"; reason="${reason:-pre-commit exited $rc}"; fi
  if [[ -n "$reason" ]]; then echo "UNCHECKED=$id $reason"; continue; fi
  git -C "$wt" -c core.quotePath=false diff --name-only > "$tmp/changed"
  changed="$(grep -c . "$tmp/changed")"
  ((changed > 0)) || continue
  # shortcut: the changed files' extensions stand in for pre-commit's `types` (it cannot list a hook's files), read the hook's types/files if a hook covers more than its extensions
  git -C "$wt" -c core.quotePath=false ls-files > "$tmp/tracked"
  covered="$(ext_count "$tmp/changed" "$tmp/tracked")"
  if ((changed * 2 > covered)); then echo "REWRITES=$id $changed/$covered"; fi
done < <(sed -nE 's/^[[:space:]]*-[[:space:]]+id:[[:space:]]*["'\'']?([^"'\''#[:space:]]+).*/\1/p' "$cfg_file" | awk '!seen[$0]++')
echo "FORMATTERS=checked $n hooks"
exit 0
