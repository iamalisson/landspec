#!/usr/bin/env bash
# Remove landspec from one project (the reverse of setup.sh). Spec-kit, your specs and your edits stay.
# Usage: remove.sh [project-dir] [--with-speckit]
#   --with-speckit  also delete spec-kit's own files (.specify/, the constitution with it, .claude/skills/speckit-*) for a reinstall from zero; specs/ is never touched
# Deletes only what landspec created: files that still carry its "managed file" marker and are
# unchanged since it wrote them (.specify/landspec-files.sha256), files identical to its scaffold, its
# lines in hook configs, and its block in the constitution. Safe to re-run: what it keeps stays in
# .specify/landspec-files.sha256. Two limits: --with-speckit deletes that record with .specify, and with
# no record (set up before 1.8.0) an edit committed between two runs looks like landspec's own file.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../extension/scripts/lib.sh
source "$here/extension/scripts/lib.sh" # sha256
die(){ echo "landspec: $*" >&2; exit 1; }
usage() { sed -n '3p' "$0" | sed 's/^# Usage/Usage/' >&2; exit 2; }

dir="."; speckit=false
while (($#)); do
  case "$1" in
    --with-speckit) speckit=true; shift ;;
    -h|--help) usage ;;
    -*) echo "landspec: unknown option $1" >&2; usage ;;
    *) dir="$1"; shift ;;
  esac
done
cd "$dir" 2>/dev/null || die "no such directory: $dir"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository: $dir"
cd "$(git rev-parse --show-toplevel)"
gone() { echo "removed: $1"; }
[[ ! -d .specify/extensions/jit ]] || die "this project still uses the name jit-speckit; run /landspec:init once, then remove it"
const=.specify/memory/constitution.md
constitution_markers "$const" # before anything is deleted

# ── spec-kit registrations: extension, preset, hook skills ───────────────────
if [[ -d .specify/extensions/landspec || -d .specify/presets/landspec ]]; then
  command -v specify >/dev/null || die "spec-kit (specify) is required to unregister the extension; install it as /landspec:init says"
  # specify refuses what its registry doesn't know; a half-installed copy is then deleted by hand.
  specify preset remove landspec >/dev/null 2>&1 || rm -rf .specify/presets/landspec
  specify extension remove landspec --force >/dev/null 2>&1 || rm -rf .specify/extensions/landspec
  rm -rf .specify/extensions/.backup/landspec
  gone "spec-kit extension and preset 'landspec' (templates and the implement command restored)"
fi
rm -rf .claude/skills/speckit-landspec-*

# ── Files added to the repo ──────────────────────────────────────────────────
record=.specify/landspec-files.sha256 # "<sha256> <path>" for each file level.sh wrote
ours() { # ours <file>: created by landspec and not taken over by the user
  [[ -f "$1" ]] || return 1
  local want; want="$(awk -v p="$1" '$2 == p { print $1 }' "$record" 2>/dev/null || true)"
  if [[ -n "$want" ]]; then
    if [[ "$(sha256 < "$1")" == "$want" ]]; then return 0; fi
    echo "kept (edited): $1"; return 1
  fi
  # No record (set up before 1.8.0): only a committed, unchanged marked file is known to be landspec's.
  if head -2 "$1" | grep '^# landspec: managed file' >/dev/null; then
    if git ls-files --error-unmatch "$1" >/dev/null 2>&1 && git diff --quiet HEAD -- "$1" 2>/dev/null; then return 0; fi
    echo "kept (edited): $1"; return 1
  fi
  local l ours_shape=false
  for l in lite standard full; do
    if [[ -f "$here/extension/scaffold/$l/$1" ]]; then
      if cmp -s "$1" "$here/extension/scaffold/$l/$1"; then return 0; fi
      [[ "$(head -1 "$1")" == "$(head -1 "$here/extension/scaffold/$l/$1")" ]] && ours_shape=true
    fi
  done
  if [[ "$1" == .github/CODEOWNERS && "$(head -1 "$1")" == "# Every change needs a review from an owner." ]]; then
    local owner line; owner="$(repo_slug)"; owner="${owner%%/*}"; line="$(sed -n 2p "$1")"
    if [[ -z "$(sed -n '3,$p' "$1")" && ( "$line" == "* @OWNER" || ( -n "$owner" && "$line" == "* @$owner" ) ) ]]; then return 0; fi
    ours_shape=true
  fi
  # "{" and a shebang open every such file, so they say nothing about who wrote it.
  if $ours_shape && [[ "$1" != .claude/settings.json && "$1" != .githooks/* ]]; then echo "kept (edited): $1"; fi
  return 1
}
{ (cd "$here/extension/scaffold" && find lite standard full -type f | sed 's#^[a-z]*/##')
  printf '%s\n' .github/workflows/ci.yml .github/workflows/security.yml .github/dependabot.yml .github/CODEOWNERS .mcp.json
} | sort -u | while IFS= read -r f; do
  if ours "$f"; then rm "$f"; gone "$f"; fi
done
# The record outlives a kept file, so the next run still knows it was edited.
if [[ -f "$record" ]] && ! $speckit; then
  while read -r sum f; do if [[ -f "$f" ]]; then echo "$sum $f"; fi; done < "$record" > "$record.tmp"
  if [[ -s "$record.tmp" ]]; then mv "$record.tmp" "$record"; echo "kept: $record (it names the files kept above)"
  else rm -f "$record" "$record.tmp"; fi
fi
rmdir -p .githooks .github/workflows 2>/dev/null || true

# ── Git hooks ────────────────────────────────────────────────────────────────
if [[ "$(git config --get core.hooksPath || true)" == .githooks && ! -e .githooks ]]; then
  git config --unset core.hooksPath; echo "git hooks: core.hooksPath unset"
elif [[ "$(git config --get core.hooksPath || true)" == .githooks ]] && grep -qs '\.specify/extensions/landspec/scripts/' .githooks/pre-commit .githooks/pre-push; then
  echo "kept: .githooks still calls landspec's scripts, which are gone; edit those lines out, or: git config --unset core.hooksPath"
fi
pc=.pre-commit-config.yaml
if [[ -f "$pc" ]] && grep -qE '^ *- +id: landspec-(secrets|prepush) *$' "$pc"; then
  awk '
    function ind(s) { match(s, /^ */); return RLENGTH }
    { L[NR] = $0 }
    END {
      n = 0
      for (i = 1; i <= NR; i++) { # the landspec hook items: the "- id:" line and every line indented deeper
        if (L[i] ~ /^ *- +id: landspec-(secrets|prepush) *$/) {
          d = ind(L[i]); while (i < NR && (L[i+1] ~ /^ *$/ || ind(L[i+1]) > d)) i++
          continue
        }
        M[++n] = L[i]
      }
      for (i = 1; i <= n; i++) { # a "repo: local" left with no hooks
        if (M[i] ~ /^ *- +repo: local *$/ && M[i+1] ~ /^ *hooks: *$/ && !(M[i+2] ~ /^ *- / && ind(M[i+2]) >= ind(M[i+1]))) { i++; continue }
        print M[i]
      }
    }' "$pc" > "$pc.tmp" && mv "$pc.tmp" "$pc"
  echo "git hooks: landspec hooks removed from $pc"
fi
for h in .husky/pre-commit .husky/pre-push; do
  if grep -qs '\.specify/extensions/landspec/scripts/' "$h"; then
    sed -i.bak '/\.specify\/extensions\/landspec\/scripts\//d' "$h" && rm -f "$h.bak"; echo "git hooks: landspec line removed from $h"
  fi
done

# ── Constitution ─────────────────────────────────────────────────────────────
strip_block() { awk '/^<!-- landspec:start/ { skip = 1 } !skip { print } /^<!-- landspec:end -->/ { skip = 0 }' "$1"; }
if [[ -f "$const" ]] && ! $speckit && grep -q '^<!-- landspec:start' "$const"; then
  if [[ "$(strip_block "$const")" == "$(strip_block "$here/preset/templates/constitution-template.md")" ]]; then
    rm "$const"; gone "$const (landspec's template, never filled in)"
  else
    strip_block "$const" > "$const.tmp" && mv "$const.tmp" "$const"
    echo "constitution: landspec block removed from $const (your text kept)"
  fi
fi

if $speckit; then
  lost=""; if [[ -f "$const" ]]; then lost=" the constitution went with it;"; fi
  rm -rf .specify .claude/skills/speckit-*
  rmdir .claude/skills .claude 2>/dev/null || true
  gone "spec-kit (.specify/, .claude/skills/speckit-*);$lost specs/ kept"
fi

edited="files you edited"; if $speckit; then edited="files you edited outside .specify/"; fi
cat <<EOT

Done. Kept on purpose: specs/, your commits, $edited, and:
  branches develop/staging, if created:   git push origin --delete develop staging
  GitHub protections set at init:         repository Settings → Branches, Code security
Reinstall: /landspec:init
EOT
