#!/usr/bin/env bash
# Set up a project (new or existing) with spec-kit + landspec.
# Usage: setup.sh [project-dir] [--level lite|standard|full] [--integration claude] [--no-branches] [--downgrade]
# Idempotent: re-running updates the extension and preset and re-applies the level.
set -euo pipefail

SPECKIT_VERSION="v1.2.5" # the spec-kit release CI tests against
here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../extension/scripts/lib.sh
source "$here/extension/scripts/lib.sh" # version_newer
die() { echo "landspec: $*" >&2; exit 1; }
usage() { sed -n '3p' "$0" | sed 's/^# Usage/Usage/' >&2; exit 2; }

dir="."; level=""; integration="claude"; extra=(); downgrade=false
while (($#)); do
  case "$1" in
    --level) [[ -n "${2:-}" ]] || usage; level="$2"; shift 2 ;;
    --integration) [[ -n "${2:-}" ]] || usage; integration="$2"; shift 2 ;;
    --no-branches) extra+=(--no-branches); shift ;;
    --downgrade) downgrade=true; shift ;;
    -h|--help) usage ;;
    -*) echo "landspec: unknown option $1" >&2; usage ;;
    *) dir="$1"; shift ;;
  esac
done
case "$level" in ""|lite|standard|full) ;; *) die "unknown level '$level' (lite, standard or full)" ;; esac

# Run a command quietly, but show everything it printed if it fails (spec-kit reports errors on stdout).
quiet() {
  local out
  if ! out="$("$@" 2>&1)"; then
    echo "$out" >&2
    die "failed: $*"
  fi
}

command -v git >/dev/null || die "git is required"
command -v specify >/dev/null || die "spec-kit is required: uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@$SPECKIT_VERSION"
command -v gh >/dev/null || echo "landspec: warning: GitHub CLI (gh) not found; issues and PRs need it (https://cli.github.com)" >&2
if [[ "$integration" == claude ]] && ! command -v claude >/dev/null; then
  echo "landspec: warning: Claude Code CLI not found; install it to use the slash commands (https://claude.com/claude-code)" >&2
fi

mkdir -p "$dir" && cd "$dir"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { git init --quiet -b main && echo "git: initialized"; }

# An older plugin copy would take the project back, dropping the gates it has. The indented
# version: line is the extension's own (not schema_version or speckit_version).
ext_version() { sed -nE 's/^[[:space:]]+version:[[:space:]]*"?([^" ]*)"?.*/\1/p' "$1" 2>/dev/null | head -1 || true; }
plugin_v="$(ext_version "$here/extension/extension.yml")"; project_v="$(ext_version .specify/extensions/landspec/extension.yml)"
[[ -n "$project_v" ]] || project_v="$(ext_version .specify/extensions/jit/extension.yml)"
if ! $downgrade && version_newer "$project_v" "$plugin_v"; then
  die "this plugin copy is $plugin_v, the project is at $project_v; run /reload-plugins (or setup.sh --downgrade)"
fi
# A branch behind the base would rewrite an older copy that git cannot carry onto the base.
# Offline, or without origin, there is nothing to compare with, so it goes on.
if git remote get-url origin >/dev/null 2>&1; then
  base="$(base_branch)"; git fetch --quiet origin "$base" 2>/dev/null || true
  base_v="$(git show "refs/remotes/origin/$base:.specify/extensions/landspec/extension.yml" 2>/dev/null | ext_version /dev/stdin || true)"
  if version_newer "$base_v" "${project_v:-0}"; then
    die "origin/$base is at landspec $base_v, this branch at ${project_v:-none}; run it from $base: switch to it and pull, then /landspec:init again"
  fi
fi

if [[ ! -d .specify/templates ]]; then
  # The agent's own CLI may be installed later (or never, e.g. in CI); the warning above covers it.
  quiet specify init --here --force --non-interactive --ignore-agent-tools --integration "$integration"
  echo "spec-kit: initialized ($integration)"
fi

# A project set up before 2.0.0, when this was jit-speckit: drop the old registration and move what
# the user owns. The settings are saved first, because removing the extension deletes them, and to
# a file, so a run that fails below still has them on the next one.
old_cfg=.specify/landspec-config.moving
if [[ -d .specify/extensions/jit ]]; then
  if [[ -f .specify/extensions/jit/jit-config.yml ]]; then cp .specify/extensions/jit/jit-config.yml "$old_cfg"; fi
  specify preset remove jit >/dev/null 2>&1 || rm -rf .specify/presets/jit
  specify extension remove jit --force >/dev/null 2>&1 || rm -rf .specify/extensions/jit
  rm -rf .specify/extensions/.backup/jit .claude/skills/speckit-jit-*
  if [[ -f .specify/jit-files.sha256 ]]; then mv .specify/jit-files.sha256 .specify/landspec-files.sha256; fi
  for f in .specify/memory/constitution.md .pre-commit-config.yaml .husky/pre-commit .husky/pre-push .githooks/pre-commit .githooks/pre-push .github/copilot-instructions.md .github/pull_request_template.md; do
    if [[ -f "$f" ]]; then
      sed -i.bak -e 's/<!-- jit:/<!-- landspec:/g' -e 's/`jit:start`/`landspec:start`/g' -e 's/`jit:end`/`landspec:end`/g' -e 's#jit-speckit#landspec#g' -e 's/speckit-jit-/speckit-landspec-/g' -e 's#\.specify/extensions/jit/#.specify/extensions/landspec/#g' -e 's/id: jit-secrets/id: landspec-secrets/' -e 's/id: jit-prepush/id: landspec-prepush/' "$f" && rm -f "$f.bak"
    fi
  done
  echo "renamed: jit-speckit is now landspec; settings, hooks and the constitution block moved"
fi

quiet specify extension add --dev "$here/extension" --force
if [[ -f "$old_cfg" ]]; then mv "$old_cfg" .specify/extensions/landspec/landspec-config.yml; fi
echo "spec-kit: extension 'landspec' installed"
specify preset remove landspec >/dev/null 2>&1 || true
quiet specify preset add --dev "$here/preset"
echo "spec-kit: preset 'landspec' installed"

# spec-kit was initialized for another agent before: the hooks would be invisible to Claude Code.
if [[ "$integration" == claude && ! -d .claude/skills/speckit-landspec-branch ]]; then
  die "this project's spec-kit is set up for another agent; add Claude with: specify integration add claude"
fi

# A fresh project still has spec-kit's blank constitution; start from ours instead.
const=.specify/memory/constitution.md
if [[ ! -s "$const" ]] || cmp -s "$const" .specify/templates/constitution-template.md; then
  mkdir -p "$(dirname "$const")"
  cp "$here/preset/templates/constitution-template.md" "$const"
  echo "constitution: started from the landspec template"
fi

current="$(sed -nE 's/^level:[[:space:]]*([a-z]+).*/\1/p' .specify/extensions/landspec/landspec-config.yml 2>/dev/null || true)"
level="${level:-${current:-standard}}"
bash .specify/extensions/landspec/scripts/level.sh "$level" ${extra[@]+"${extra[@]}"}

cat <<EOF

Done. Next:
  existing code?  /landspec:adopt      (fills the constitution from this repo)
  new project?    /speckit-constitution   (fills the [PLACEHOLDERS])
  then per feature: /speckit-specify → /speckit-plan → /speckit-tasks → /landspec:implement
EOF
