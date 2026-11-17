#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash). Hands git commands to landspec's guard.
# Does nothing outside landspec projects or for commands that don't involve git, gh, aws,
# terraform/tofu, .env or .tfstate.
# Exit 2 blocks the command; the guard's stderr tells Claude why.
# The guard that runs is this plugin's own copy, never a script from the opened repository: the
# project only provides its config (level, base branch), so a stale or tampered copy there changes
# nothing.
set -uo pipefail
input="$(cat)"
field() { # field <name>: a string field from the hook's JSON input
  if command -v python3 >/dev/null; then
    python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("tool_input",{}).get(sys.argv[1], d.get(sys.argv[1], "")); print(v if isinstance(v,str) else "")' "$1" <<<"$input" 2>/dev/null
  else
    sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\1/p" <<<"$input" | sed -n 1p
  fi
}
cmd="$(field command)"
# gh: a PR opens only through pr.sh; the rest: the AWS rules (off unless `aws: on`).
[[ "$cmd" =~ git|gh|aws|terraform|tofu|\.env|\.tfstate ]] || exit 0
cwd="$(field cwd)"
cd "${cwd:-.}" 2>/dev/null || exit 0
# Fast path: no cd/pushd/-C/--git-dir/GIT_DIR=, so every git command runs here; nothing to check
# outside landspec.
if [[ ! "$cmd" =~ (^|[^[:alnum:]_-])(cd|pushd)[[:space:]]|[[:space:]]-C[[:space:]]|--git-dir|--work-tree|GIT_DIR=|GIT_WORK_TREE= ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
  [[ -d "$root/.specify/extensions/landspec" || -d "$root/.specify/extensions/jit" ]] || exit 0 # jit: the name before 2.0.0
fi
# The guard follows cd and git -C itself, and checks each git command in its own repository.
guard="$(cd "$(dirname "$0")/.." && pwd)/extension/scripts/guard.sh"
exec bash "$guard" "$cmd"
