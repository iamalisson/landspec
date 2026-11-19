#!/usr/bin/env bash
# Set the project's complexity level and apply its defaults.
# Usage: level.sh <lite|standard|full> [--no-branches]
#   - stores the level in .specify/extensions/landspec/landspec-config.yml
#   - creates the level's long-lived branches (develop, staging) if missing (skip with --no-branches)
#   - rewrites the landspec block of .specify/memory/constitution.md (nothing outside it is touched)
#   - adds the level's scaffold files that do not exist yet, and re-creates those that still carry
#     the managed-file marker (commit edits first, or delete the marker); other files are kept
# Safe to re-run; going down a level never deletes files.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
shopt -u patsub_replacement 2>/dev/null || true

level="${1:-}"; branches=true
[[ "${2:-}" == --no-branches ]] && branches=false
case "$level" in lite|standard|full) ;; *) die "usage: level.sh <lite|standard|full> [--no-branches]" ;; esac
landspec_cd_root

# Never guess where a damaged block ends: replacing from landspec:start to EOF would delete the user's
# text. Checked first, before anything is changed.
const=".specify/memory/constitution.md"
constitution_markers "$const"

previous="$(cfg level none)"
cfg_set level "$level"
grep -qE '^base_branch:' "$LANDSPEC_CONFIG" || cfg_set base_branch auto
grep -qE '^branch_prefix:' "$LANDSPEC_CONFIG" || cfg_set branch_prefix feat
echo "level: $previous → $level"

case "$level" in
  lite) levels=(lite); flow="feat/* → $(default_branch)" ;;
  standard) levels=(lite standard); flow="feat/* → develop → $(default_branch)" ;;
  full) levels=(lite standard full); flow="feat/* → develop → staging → $(default_branch)" ;;
esac

# ── Branch flow ──────────────────────────────────────────────────────────────
if $branches; then
  need=()
  if [[ "$level" != lite ]]; then need+=(develop); fi
  if [[ "$level" == full ]]; then need+=(staging); fi
  has_origin=false; git remote get-url origin >/dev/null 2>&1 && has_origin=true
  if $has_origin && ((${#need[@]})) && git rev-parse --verify --quiet HEAD >/dev/null; then git fetch --quiet origin 2>/dev/null || true; fi
  for b in ${need[@]+"${need[@]}"}; do
    if ! git rev-parse --verify --quiet HEAD >/dev/null; then
      echo "branch: $b not created yet (no commits); run /landspec:level again after the first commit"
    elif $has_origin; then
      if ! git show-ref --verify --quiet "refs/remotes/origin/$b"; then
        if git show-ref --verify --quiet "refs/remotes/origin/$(default_branch)"; then
          # --no-verify is safe only here: this names a commit that is already on origin, so
          # nothing new (and nothing unscanned) leaves the machine.
          git push --quiet --no-verify origin "refs/remotes/origin/$(default_branch):refs/heads/$b"
          echo "branch: created origin/$b from origin/$(default_branch)"
          if [[ "$b" == "$(base_branch)" ]]; then
            echo "branch: task branches start from $b, which has no landspec files yet: open its PR with --base $b ($(default_branch) gets it at the next promotion)"
          fi
        else
          echo "branch: origin/$b not created yet ($(default_branch) isn't on origin); push $(default_branch) first, then run /landspec:level again"
        fi
      fi
    elif ! git show-ref --verify --quiet "refs/heads/$b"; then
      git branch "$b"; echo "branch: created $b"
    fi
  done
fi

# ── Stack facts ──────────────────────────────────────────────────────────────
stacks=(); while IFS= read -r s; do stacks+=("$s"); done < <(bash "$LANDSPEC_EXT_DIR/scripts/detect-stack.sh")
idioms=""; tests=()
for s in ${stacks[@]+"${stacks[@]}"}; do
  case "$s" in
    rust) idioms+=$'- Rust: `cargo fmt` and `cargo clippy -- -D warnings` clean; `Result` with `?`, no `unwrap` outside tests and startup.\n'
          tests+=("cargo test --all") ;;
    node:*) pm="${s#node:}"
          idioms+="- TypeScript/JavaScript: strict type checking, lint clean (\`$pm run lint\`), no \`any\` without a comment saying why."$'\n'
          tests+=("$pm test") ;;
    python:*) run=""; [[ "$s" == python:uv ]] && run="uv run "
          idioms+=$'- Python: `ruff` clean, type hints on public functions, a type checker in CI where configured.\n'
          tests+=("${run}pytest") ;;
    go) idioms+=$'- Go: `gofmt` and `go vet` clean; wrap errors with context, no panics in library code.\n'
          tests+=("go test ./...") ;;
  esac
done
[[ -n "$idioms" ]] || idioms=$'- [STACK_IDIOMS: formatter, linter and idioms for this stack; run /landspec:adopt]\n'
test_cmd="[TEST_COMMAND]"
if ((${#tests[@]})); then test_cmd="$(printf '%s && ' "${tests[@]}")"; test_cmd="${test_cmd% && }"; fi

# The constitution's Commands line ("build `x` · test `y` · lint `z`"), filled by /landspec:adopt,
# wins over the stack defaults in the landspec block and in the generated CI. A [PLACEHOLDER] is unset.
build_c="$(constitution_cmd build)"; test_c="$(constitution_cmd test)"; lint_c="$(constitution_cmd lint)"
[[ -z "$test_c" ]] || test_cmd="$test_c"

# ── Constitution block ───────────────────────────────────────────────────────
render() {
  local t; t="$(cat "$1")"
  t="${t//\{\{LEVEL\}\}/$level}"; t="${t//\{\{BRANCH_FLOW\}\}/$flow}"
  t="${t//\{\{TEST_COMMAND\}\}/$test_cmd}"; t="${t//\{\{STACK_IDIOMS\}\}/${idioms%$'\n'}}"
  printf '%s\n' "$t"
}
block="<!-- landspec:start (managed by /landspec:level; edit outside this block) -->"$'\n'
block+="## Defaults (landspec, level: $level)"$'\n'
aws_on=false; [[ "$(cfg aws off)" == on ]] && aws_on=true
for l in "${levels[@]}"; do
  block+=$'\n'"$(render "$LANDSPEC_EXT_DIR/levels/$l.md")"$'\n'
  if $aws_on; then block+=$'\n'"$(render "$LANDSPEC_EXT_DIR/levels/aws/$l.md")"$'\n'; fi
done
block+="<!-- landspec:end -->"

const=".specify/memory/constitution.md"
mkdir -p "$(dirname "$const")"; touch "$const"
B="$block" awk '
  /^<!-- landspec:start/ { print ENVIRON["B"]; skip = 1; done = 1; next }
  /^<!-- landspec:end -->/ { skip = 0; next }
  skip { next }
  !done && /^## Governance/ { print ENVIRON["B"]; print ""; done = 1 }
  { print }
  END { if (!done) { print ""; print ENVIRON["B"] } }
' "$const" > "$const.tmp" && mv "$const.tmp" "$const"
echo "constitution: landspec block set to '$level' in $const"

# ── Scaffold ─────────────────────────────────────────────────────────────────
# shellcheck source=pins.sh
source "$LANDSPEC_EXT_DIR/scripts/pins.sh"

MARKER="# landspec: managed file. /landspec:level re-creates it while this line stays; delete the line to keep your own edits."
OLD_MARKER="# jit-speckit: managed file. /jit-speckit:level re-creates it while this line stays; delete the line to keep your own edits." # the name before 2.0.0
# Files releases before the marker (1.0.0-1.3.1) wrote byte for byte: "<sha256> <path> <versions> <replace|name>".
OLD_FILES="$LANDSPEC_EXT_DIR/scripts/old-files.sha256"; old_hook=""
put() { # put <dest> [generated] (content on stdin): write only if missing, ours (the marker in its first lines) or an old release's hook
  if [[ -e "$1" ]] && ! head -2 "$1" | grep -qxF -e "$MARKER" -e "$OLD_MARKER"; then
    local old; old="$(awk -v h="$(sha256 < "$1")" -v p="$1" '$1 == h && $2 == p { print $3, $4 }' "$OLD_FILES")"
    if [[ "$old" == *" replace" ]]; then old_hook="${old% *}" # an old hook: rewritten below, now marked
    else
      cat >/dev/null
      if [[ -n "$old" ]]; then echo "kept (written by landspec ${old% *}, no marker): $1 — delete it to get the current one"
      elif [[ -n "${2:-}" && -n "$old_hook" ]]; then echo "kept (written by landspec $old_hook or older, no marker): $1 — delete it to get the current one"
      elif [[ "$1" == .github/workflows/security.yml ]]; then echo "kept (no marker): $1 — delete it to get the current one"
      else echo "kept:    $1"; fi
      return
    fi
  fi
  local verb=created; [[ -e "$1" ]] && verb=updated
  mkdir -p "$(dirname "$1")"; cat > "$1.tmp"
  if [[ $verb == updated ]]; then keep_pins "$1" "$1.tmp"; fi
  mv "$1.tmp" "$1"; echo "$verb: $1"
  # What landspec wrote, so remove.sh can tell an edited file from an untouched one.
  { if [[ -f "$RECORD" ]]; then awk -v p="$1" '$2 != p' "$RECORD"; fi; echo "$(sha256 < "$1") $1"; } > "$RECORD.tmp" && mv "$RECORD.tmp" "$RECORD"
}
RECORD=.specify/landspec-files.sha256
# keep_pins <old file> <new file>: a "uses: <action>@<sha> # <version>" pin in the old file that is
# newer than the new file's (Dependabot bumped it) is kept. A container.image digest is not a pin here.
keep_pins() {
  local line a v o ov msgs="" said=" " re='uses: ([^@ ]+)@[0-9a-f]+ # ([^ ]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $re ]]; then
      a="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"; ov=""
      o="$(grep -m1 -F "uses: $a@" "$1" || true)"
      if [[ "$o" =~ $re ]]; then ov="${BASH_REMATCH[2]}"; fi
      if [[ -n "$ov" ]] && version_newer "$ov" "$v"; then
        if [[ "$said" != *" $a "* ]]; then msgs+="kept newer pin: $a $ov"$'\n'; said+="$a "; fi
        line="${line%%uses: *}uses: ${o#*uses: }"
      fi
    fi
    printf '%s\n' "$line"
  done < "$2" > "$2.pins"
  mv "$2.pins" "$2"; printf '%s' "$msgs"
}
# Workflows that already check pull requests and are not ours: then no second CI is generated.
pr_gate() {
  local f
  for f in .github/workflows/*.y*ml; do
    [[ -f "$f" ]] || continue
    if head -2 "$f" | grep -qxF -e "$MARKER" -e "$OLD_MARKER"; then continue; fi
    if grep -qE '^[[:space:]]*pull_request:' "$f"; then echo "$f"; fi
  done
  return 0
}
run_steps() { local v; for v in "$@"; do if [[ -n "$v" ]]; then printf '      - run: %s\n' "$v"; fi; done; }

branch_list() { # the long-lived branches workflows run on
  printf '%s' "$(default_branch)"
  if [[ $level != lite ]]; then printf ', develop'; fi
  if [[ $level == full ]]; then printf ', staging'; fi
}

checkout_step() { printf '      - uses: %s\n        with:\n          persist-credentials: false\n' "$PIN_CHECKOUT"; }

ci_yaml() {
  printf '%s\n# Commands come from the constitution (**Commands** line); stack defaults fill the gaps.\n' "$MARKER"
  printf 'name: CI\n\non:\n  push:\n    branches: [%s]\n  pull_request:\n\npermissions:\n  contents: read\n\njobs:\n' "$(branch_list)"
  ((${#stacks[@]})) || printf '  checks:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          echo "landspec: no stack detected. Replace this job with your lint, test and build commands." && exit 1\n'
  for s in ${stacks[@]+"${stacks[@]}"}; do
    case "$s" in
      rust)
        printf '  rust:\n    runs-on: ubuntu-latest\n    steps:\n'; checkout_step
        printf '      - uses: %s\n        with:\n          toolchain: stable\n          components: rustfmt, clippy\n' "$PIN_RUST_TOOLCHAIN"
        printf '      - uses: %s\n' "$PIN_RUST_CACHE"
        run_steps "${lint_c:-cargo fmt --all -- --check && cargo clippy --all-targets -- -D warnings}" "${test_c:-cargo test --all}" "$build_c" ;;
      node:*) pm="${s#node:}"
        printf '  node:\n    runs-on: ubuntu-latest\n    steps:\n'; checkout_step
        if [[ "$pm" == pnpm ]]; then
          printf '      - uses: %s\n' "$PIN_PNPM"
          # The action fails with no version at all, and refuses one next to a pnpm packageManager field.
          if ! grep -qE '"packageManager" *: *"pnpm@' package.json; then printf '        with:\n          version: latest\n'; fi
        fi
        # The project's pinned Node, else the current LTS (never a hard-coded major that goes EOL).
        nv="node-version: lts/*"; for f in .node-version .nvmrc; do if [[ -f $f ]]; then nv="node-version-file: $f"; break; fi; done
        printf '      - uses: %s\n        with:\n          %s\n' "$PIN_SETUP_NODE" "$nv"
        # Yarn 2+: setup-node's cache step runs the runner's Yarn 1, which refuses the project, and
        # current Node ships no corepack.
        if [[ "$pm" == yarn ]] && grep -qE '"packageManager" *: *"yarn@([2-9]|[1-9][0-9])' package.json; then
          printf '      - run: npm install -g corepack && corepack enable\n      - run: yarn install --immutable\n'
        else
          # setup-node's cache step fails the run when the lockfile it hashes is missing.
          lock=package-lock.json; case "$pm" in pnpm) lock=pnpm-lock.yaml ;; yarn) lock=yarn.lock ;; esac
          # setup-node v5+ also caches npm by itself when packageManager names npm, so say no to that too.
          if [[ -f "$lock" ]]; then printf '          cache: %s\n' "$pm"; else printf '          package-manager-cache: false\n'; fi
          case "$pm" in pnpm) printf '      - run: pnpm install --frozen-lockfile\n' ;;
                        yarn) printf '      - run: yarn install --frozen-lockfile\n' ;;
                        npm) if [[ -f package-lock.json ]]; then printf '      - run: npm ci\n'; else printf '      - run: npm install\n'; fi ;; esac
        fi
        nl=""; nb=""
        for script in lint typecheck; do if grep -qE "\"$script\" *:" package.json; then nl+="$pm run $script && "; fi; done
        if grep -qE '"build" *:' package.json; then nb="$pm run build"; fi
        run_steps "${lint_c:-${nl% && }}" "${test_c:-$pm test}" "${build_c:-$nb}" ;;
      python:uv)
        printf '  python:\n    runs-on: ubuntu-latest\n    steps:\n'; checkout_step
        printf '      - uses: %s\n      - run: uv sync --all-extras\n' "$PIN_SETUP_UV"
        run_steps "${lint_c:-uv run ruff check .}" "${test_c:-uv run pytest}" "$build_c" ;;
      python:pip)
        printf '  python:\n    runs-on: ubuntu-latest\n    steps:\n'; checkout_step
        # The project's pinned Python, else the current 3.x (never a hard-coded minor that goes EOL).
        pv='python-version: "3.x"'; [[ -f .python-version ]] && pv="python-version-file: .python-version"
        printf '      - uses: %s\n        with:\n          %s\n' "$PIN_SETUP_PYTHON" "$pv"
        printf '      - run: pip install -e ".[dev]" || pip install -r requirements.txt\n'
        run_steps "${lint_c:-pip install ruff && ruff check .}" "${test_c:-pip install pytest && pytest}" "$build_c" ;;
      go)
        printf '  go:\n    runs-on: ubuntu-latest\n    steps:\n'; checkout_step
        printf '      - uses: %s\n        with:\n          go-version-file: go.mod\n' "$PIN_SETUP_GO"
        run_steps "${lint_c:-go vet ./...}" "${test_c:-go test ./...}" "$build_c" ;;
    esac
  done
}

security_yaml() {
  cat <<EOF
$MARKER
# Security gate: runs on every pull request, on pushes to long-lived branches, and weekly
# (new CVEs land in dependencies nobody touched). Tools are pinned and checksum-verified;
# Semgrep's rule sets (full level) are fetched from the Semgrep registry at run time.
name: Security

on:
  pull_request:
  push:
    branches: [$(branch_list)]
  schedule:
    - cron: "17 6 * * 1"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  secrets:
    name: Secrets (gitleaks, full history)
    runs-on: ubuntu-latest
    steps:
      - uses: $PIN_CHECKOUT
        with:
          fetch-depth: 0
          persist-credentials: false
      - name: Install gitleaks $GITLEAKS_VERSION (checksum-verified)
        run: |
          curl -sSfL -o gitleaks.tgz https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz
          echo "$GITLEAKS_SHA256  gitleaks.tgz" | sha256sum -c -
          tar -xzf gitleaks.tgz gitleaks
      - run: ./gitleaks git --redact --verbose --no-banner .

  dependencies:
    name: Dependencies (osv-scanner)
    runs-on: ubuntu-latest
    steps:
$(checkout_step)
      - name: Install osv-scanner $OSV_VERSION (checksum-verified)
        run: |
          curl -sSfL -o osv-scanner https://github.com/google/osv-scanner/releases/download/v$OSV_VERSION/osv-scanner_linux_amd64
          echo "$OSV_SHA256  osv-scanner" | sha256sum -c -
          chmod +x osv-scanner
      - name: Scan every lockfile (exit 128 = no lockfiles)
        run: ./osv-scanner scan source -r . || { s=\$?; [ "\$s" = 128 ] || exit "\$s"; }

  workflows:
    name: Workflows (zizmor)
    runs-on: ubuntu-latest
    steps:
$(checkout_step)
      - uses: $PIN_ZIZMOR
        with:
          advanced-security: false
EOF
  if [[ -n "$(infra_files)" ]]; then
    cat <<EOF

  infra:
    name: Dockerfiles and Terraform (trivy config)
    runs-on: ubuntu-latest
    steps:
$(checkout_step)
      - name: Install trivy $TRIVY_VERSION (checksum-verified)
        run: |
          curl -sSfL -o trivy.tgz https://github.com/aquasecurity/trivy/releases/download/v$TRIVY_VERSION/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz
          echo "$TRIVY_SHA256  trivy.tgz" | sha256sum -c -
          tar -xzf trivy.tgz trivy
      - run: ./trivy config --exit-code 1 --severity HIGH,CRITICAL .
EOF
  fi
  if [[ $level == full ]]; then
    cat <<EOF

  code:
    name: Code (semgrep, OWASP rules)
    runs-on: ubuntu-latest
    # The image is verified by its digest; the rule sets come from the Semgrep registry at run time.
    container:
      image: semgrep/semgrep@sha256:$SEMGREP_DIGEST # $SEMGREP_VERSION
    steps:
$(checkout_step)
      - run: semgrep scan --config p/default --config p/owasp-top-ten --error --metrics off
EOF
  fi
}

# infra_dirs <ecosystem> <regex>: one Dependabot entry per folder holding matching infra files.
infra_dirs() {
  local dir
  while IFS= read -r dir; do
    [[ -n "$dir" ]] || continue
    dir="${dir#.}"; dir="${dir#/}"
    printf '  - package-ecosystem: %s\n    directory: "/%s"\n    schedule:\n      interval: weekly\n    cooldown:\n      default-days: 7\n    target-branch: %s\n' "$1" "$dir" "$(base_branch)"
  done < <(infra_files | grep -E "$2" | sed -E 's#^#./#; s#/[^/]*$##' | sort -u)
}

# Kept out of $( ... ): bash 3.2 (macOS) misparses a case pattern's ")" inside a command substitution.
ecosystems() {
  echo github-actions
  for s in ${stacks[@]+"${stacks[@]}"}; do
    case "$s" in
      rust) echo cargo ;;
      node:*) echo npm ;;
      python:uv) echo uv ;;
      python:pip) echo pip ;;
      go) echo gomod ;;
    esac
  done
}

dependabot_yaml() {
  printf '%s\nversion: 2\nupdates:\n' "$MARKER"
  local eco
  local dir
  for eco in $(ecosystems); do
    dir=/
    # cooldown: a release must be a week old before Dependabot proposes it (time for a malicious
    # upload to be found and pulled); zizmor's dependabot-cooldown audit requires it.
    printf '  - package-ecosystem: %s\n    directory: "%s"\n    schedule:\n      interval: weekly\n    cooldown:\n      default-days: 7\n    target-branch: %s\n    open-pull-requests-limit: 5\n    groups:\n      minor-and-patch:\n        update-types: [minor, patch]\n' "$eco" "$dir" "$(base_branch)"
  done
  # Base images and Terraform providers, in every folder that has them.
  infra_dirs docker '(^|/)Dockerfile[^/]*$'
  infra_dirs terraform '\.tf$'
}

# The AWS MCP server, run as the dev agent profile. JSON has no comments, so no marker: written once.
mcp_json() {
  cat <<EOF
{
  "mcpServers": {
    "aws-mcp": {
      "command": "uvx",
      "args": [
        "mcp-proxy-for-aws==$MCP_PROXY_VERSION",
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--metadata",
        "AWS_REGION=us-east-1"
      ],
      "env": {
        "AWS_PROFILE": "landspec-agent-dev"
      }
    }
  }
}
EOF
}

for l in "${levels[@]}"; do
  src="$LANDSPEC_EXT_DIR/scaffold/$l"
  [[ -d "$src" ]] || continue
  while IFS= read -r f; do
    put "${f#"$src"/}" < "$f"
  done < <(find "$src" -type f | sort)
  case "$l" in
    lite) chmod +x .githooks/* ;;
    standard) gate="$(pr_gate)"
              if [[ -n "$gate" ]]; then
                echo "kept:    $(tr '\n' ' ' <<<"$gate")(already checks pull requests; no ci.yml generated)"
                while IFS= read -r w; do
                  if pr_skips_base "$w"; then echo "warning: $w never runs on the feature PR into $(base_branch): add $(base_branch) to its pull_request branches"; fi
                done <<<"$gate"
              else ci_yaml | put .github/workflows/ci.yml generated; fi
              security_yaml | put .github/workflows/security.yml generated
              dependabot_yaml | put .github/dependabot.yml generated ;;
    full) owner="$(repo_slug)"; owner="${owner%%/*}"
          printf '# Every change needs a review from an owner.\n* @%s\n' "${owner:-OWNER}" | put .github/CODEOWNERS generated ;;
  esac
done
# No "generated" flag: no older release wrote .mcp.json, so its "kept (written by landspec …)" line would be wrong.
if $aws_on; then mcp_json | put .mcp.json; fi

# ── Git hooks ────────────────────────────────────────────────────────────────
# core.hooksPath is per clone: every teammate's /landspec:init (or this script) sets it.
# A repo that already runs its hooks through the pre-commit framework or husky gets landspec's two
# checks added there, so they really run instead of being left as lines to paste.
hooks_path="$(git config --get core.hooksPath || true)"
local_path="$(git config --local --get core.hooksPath || true)"
pc_cfg=.pre-commit-config.yaml
pc_hook() { # pc_hook <indent of "- "> <id> <name> <entry> <stage>
  local pad; pad="$(printf '%*s' "${#1}" '')"
  printf '%s%sid: %s\n%s%sname: %s\n%s%sentry: %s\n%s%slanguage: system\n%s%spass_filenames: false\n%s%salways_run: true\n%s%sstages: [%s]\n' \
    "$pad" "$1" "$2" "$pad" "$pad" "$3" "$pad" "$pad" "$4" "$pad" "$pad" "$pad" "$pad" "$pad" "$pad" "$pad" "$pad" "$5"
}
hook_calls() { grep -qsE "^[^#]*$2" "$1"; } # hook_calls <file> <regex>: outside a comment
# Where git really runs hooks from says "enabled" only when both files run; else what to add.
hook_status() { # hook_status [<what is wrong>]
  local dir; dir="$(git rev-parse --git-path hooks)"
  if [[ -x "$dir/pre-commit" && -x "$dir/pre-push" ]] && hook_calls "$dir/pre-commit" 'secrets\.sh' && hook_calls "$dir/pre-push" 'prepush\.sh'; then
    echo "git hooks: enabled ($dir: secret check on commit, secret + branch check on push)"
  else
    echo "git hooks: ${1:-this repo already has its own} ($dir); add these lines to it:"
    echo "  pre-commit: bash .specify/extensions/landspec/scripts/secrets.sh staged"
    echo "  pre-push:   bash .specify/extensions/landspec/scripts/prepush.sh \"\$@\""
  fi
}
husky_add() { # husky_add <file> <regex> <line>
  hook_calls "$1" "$2" && return
  [[ ! -s "$1" || -z "$(tail -c1 "$1")" ]] || echo >> "$1"
  echo "$3" >> "$1"
}
if [[ "$local_path" == .githooks ]]; then
  hook_status
elif [[ -f "$pc_cfg" ]]; then
  if grep -q 'scripts/secrets.sh' "$pc_cfg" && grep -q 'scripts/prepush.sh' "$pc_cfg"; then
    echo "git hooks: already in $pc_cfg"
  else
    # The same list indentation as the file's own items, so the appended item stays valid YAML.
    ind="$(sed -nE 's/^( *- +)repo:.*/\1/p' "$pc_cfg" | head -1)"; [[ -n "$ind" ]] || ind="-   "
    pad="$(printf '%*s' "${#ind}" '')"
    item="$(echo "${ind}repo: local"; echo "${pad}hooks:"
      grep -q 'scripts/secrets.sh' "$pc_cfg" || pc_hook "$ind" landspec-secrets "landspec secrets (staged)" "bash .specify/extensions/landspec/scripts/secrets.sh staged" pre-commit
      grep -q 'scripts/prepush.sh' "$pc_cfg" || pc_hook "$ind" landspec-prepush "landspec push check (secrets in every pushed commit, protected branches)" "bash .specify/extensions/landspec/scripts/prepush.sh" pre-push
    )"
    # After the list's last item, before any top-level key and the comments above it: at the end
    # of the file, a key such as ci: would leave the item outside the list.
    { cat "$pc_cfg"; grep -q '^repos:' "$pc_cfg" || printf '\nrepos:\n'; } | B="$item" awk '
      repos && /^[^[:space:]#-]/ { print ENVIRON["B"]; repos = 0 }
      repos && /^[[:space:]]*(#|$)/ { held = held $0 "\n"; next }
      { printf "%s", held; held = ""; print }
      /^repos:/ { repos = 1 }
      END { if (repos) print ENVIRON["B"]; printf "%s", held }
    ' > "$pc_cfg.tmp"
    # A list written inline (repos: []) takes no item below it.
    if grep -qE '^repos:[[:space:]]*[^[:space:]#]' "$pc_cfg" || { command -v pre-commit >/dev/null && ! pre-commit validate-config "$pc_cfg.tmp" >/dev/null 2>&1; }; then
      rm -f "$pc_cfg.tmp"
      echo "git hooks: $pc_cfg would not stay valid, so it was left as it is; add these lines to it:"
      echo "$item"
    else
      mv "$pc_cfg.tmp" "$pc_cfg"
      echo "git hooks: added to $pc_cfg (pre-commit framework)"
    fi
  fi
  [[ -f "$(git rev-parse --git-path hooks)/pre-push" ]] \
    || echo "git hooks: not active in this clone yet; run: pre-commit install --hook-type pre-commit --hook-type pre-push"
elif [[ -d .husky ]]; then
  # husky runs these files as shell scripts, so git's arguments and stdin reach prepush.sh.
  husky_add .husky/pre-commit 'scripts/secrets\.sh' 'bash .specify/extensions/landspec/scripts/secrets.sh staged'
  husky_add .husky/pre-push 'scripts/prepush\.sh' 'bash .specify/extensions/landspec/scripts/prepush.sh "$@"'
  chmod +x .husky/pre-commit .husky/pre-push
  echo "git hooks: added to .husky/pre-commit and .husky/pre-push"
  # Compared as real paths: husky 9 uses .husky/_, older ones .husky, and either can be absolute.
  real_hooks="$(cd "$(git rev-parse --git-path hooks)" 2>/dev/null && pwd -P || true)"
  case "$real_hooks/" in
    "$(cd .husky && pwd -P)"/*) ;;
    *) echo "git hooks: not active in this clone yet; run: npx husky (or: git config core.hooksPath .husky)" ;;
  esac
elif [[ -n "$hooks_path" && -z "$local_path" ]]; then
  echo "git hooks: core.hooksPath is machine-wide ($hooks_path), so it stays in charge here"
  hook_status "those hooks do not run landspec's checks"
elif [[ -n "$hooks_path" || -n "$(find "$(git rev-parse --git-path hooks)" -mindepth 1 -maxdepth 1 ! -type d ! -name '*.sample' 2>/dev/null)" ]]; then
  hook_status
else
  git config core.hooksPath .githooks
  hook_status
fi

if [[ "$previous" == full && "$level" != full ]] || [[ "$previous" == standard && "$level" == lite ]]; then
  echo "note: files added by the higher level were kept; delete any you no longer want"
fi
