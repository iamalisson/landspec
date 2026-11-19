# Shared helpers for landspec scripts. Sourced, not executed.
# shellcheck shell=bash

LANDSPEC_CONFIG=".specify/extensions/landspec/landspec-config.yml"
# Where this extension's files live (the repo checkout, or .specify/extensions/landspec once installed).
# shellcheck disable=SC2034  # used by the scripts that source this file
LANDSPEC_EXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "landspec: $*" >&2; exit 1; }

# event <name> [key=value...]: append "<epoch> <UTC time> <branch> <name> ..." to the local log
# that stats.sh reads (.git/landspec-events, shared by every worktree; "-" when detached). Never prints, never fails.
# A caller outside its branch (a detached copy) passes branch=<name>, which the reader prefers.
# shortcut: no rotation, about 10 lines per PR; add one if the file passes a few MB
event() {
  { local b; b="$(git branch --show-current)"
    echo "$(date -u '+%s %Y-%m-%dT%H:%MZ') ${b:--} $*" >> "$(git rev-parse --git-common-dir)/landspec-events"; } 2>/dev/null || true
}

# Run every script from the repository root.
# A spec-kit project in a subfolder of a bigger repo is refused, not half-supported: git hooks and
# CI live at the repository root, so landspec's files would land in the wrong place.
landspec_cd_root() {
  local top d s
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
  d="$(pwd -P)" # physical, like git's top level (macOS /tmp is a symlink)
  while [[ "$d" != "$top" && "$d" == "$top"/* ]]; do
    if [[ -d "$d/.specify" ]]; then
      die "spec-kit is set up in ${d#"$top"/}/, a subfolder of the repository; landspec needs it at the repository root ($top)"
    fi
    d="$(dirname "$d")"
  done
  cd "$top" || die "cannot enter $top"
  # gh prefers an upstream or github remote, or a pinned one, while every push goes to origin.
  # shortcut: only a github.com origin is pinned; an Enterprise host or SSH alias keeps gh's own pick, parse those when one needs it
  s="$(origin_slug)"
  if [[ -n "$s" && -z "${GH_REPO:-}" ]]; then export GH_REPO="$s"; fi
}

# cfg <key> <default>: read a flat `key: value` line from the config file. A quoted value is
# taken as is ("Sprint #3" or 'Sprint #3'); an unquoted one ends at a ` #` comment.
cfg() {
  local v=""
  if [[ -f "$LANDSPEC_CONFIG" ]]; then
    v="$(sed -nE "/^$1:/{
      s/^$1:[[:space:]]*//
      /^\"/{ s/^\"([^\"]*)\".*$/\1/; p; q; }
      /^'/{ s/^'([^']*)'.*$/\1/; p; q; }
      s/[[:space:]]+#.*$//; s/[[:space:]]*$//; p; q
    }" "$LANDSPEC_CONFIG")"
  fi
  echo "${v:-$2}"
}

# cfg_set <key> <value>: replace or append a key in the config file.
cfg_set() {
  mkdir -p "$(dirname "$LANDSPEC_CONFIG")"
  touch "$LANDSPEC_CONFIG"
  if grep -qE "^$1:" "$LANDSPEC_CONFIG"; then
    sed -i.bak -E "s|^$1:.*$|$1: $2|" "$LANDSPEC_CONFIG" && rm -f "$LANDSPEC_CONFIG.bak"
  else
    echo "$1: $2" >> "$LANDSPEC_CONFIG"
  fi
}

landspec_level() { cfg level standard; }

# review_model: the model family every review runs on: Opus only, never read from the config.
review_model() { echo opus; }

# Paths that hold tests, across the stacks landspec supports (Django's app/tests.py, SwiftPM's
# Tests/, .NET's X.Tests/, Cypress). Case-sensitive: the PascalCase name is anchored on a lowercase
# letter or digit before it, so Contests.java or Latests.cs stay source. Read it through test_path_re.
TEST_PATH_RE='(^|/)([Tt]ests?|__tests__|spec|e2e|cypress)/|(^|/)[^/]*\.[Tt]ests?/|[._-]([Tt]est|[Ss]pec|cy)\.[a-zA-Z]+$|(^|/)tests?\.py$|(^|/)test_[^/]*\.py$|[a-z0-9]Tests?\.[a-z]+$'

# The skip markers of an added line, matched case-folded: review.sh's gate check and pr.sh's "new
# tests need no explanation" rule. No `|| true` or `exit` here: new tests use both.
# shellcheck disable=SC2034  # read by the scripts that source this file
TEST_SKIP_RE='\.only\(|\.skip\(|xfail|@disabled|@ignore|t\.skip\(|pytest\.mark\.skip'

# The repository's default branch: origin/HEAD when set, otherwise whichever of main/master
# really exists (origin/HEAD is often unset when the remote was added by hand).
default_branch() {
  local b c
  b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$b" ]]; then echo "${b#origin/}"; return; fi
  for c in main master; do
    if git show-ref --verify --quiet "refs/remotes/origin/$c" || git show-ref --verify --quiet "refs/heads/$c"; then echo "$c"; return; fi
  done
  git config init.defaultBranch || echo main
}

# The branch task PRs target: configured, or derived from the level.
base_branch() {
  local b
  b="$(cfg base_branch auto)"
  if [[ "$b" == auto ]]; then
    if [[ "$(landspec_level)" == lite ]]; then default_branch; else echo develop; fi
  else
    echo "$b"
  fi
}

# Long-lived branches that only change through pull requests.
protected_branches() {
  local level c; level="$(landspec_level)"
  echo "$(default_branch) $(base_branch)"
  # main/master are release branches in every landspec flow, whatever the remote calls its default
  # (a repo whose first push was develop has GitHub's default set to develop).
  for c in main master; do
    if git show-ref --verify --quiet "refs/heads/$c" || git show-ref --verify --quiet "refs/remotes/origin/$c"; then echo "$c"; fi
  done
  if [[ "$level" != lite ]]; then echo develop; fi
  if [[ "$level" == full ]]; then echo staging; fi
}
is_protected() { [[ " $(protected_branches | tr '\n' ' ') " == *" $1 "* ]]; }

# branch_feature: on a task branch (<prefix>/NNN-tNNN-...), the specs/ folder of its feature when
# exactly one matches; on a feature branch (<branch_prefix>/NNN-<name>) in a copy with no
# .specify/feature.json of its own (a fresh worktree), specs/NNN-<name> when it exists; otherwise nothing.
# A local feature.json wins over a feature branch: /speckit-specify writes the new feature there
# while still on the branch of the one before.
branch_feature() {
  local b num matches
  b="$(git branch --show-current 2>/dev/null)"
  num="$(sed -nE "s#^[^/]+/($FEATURE_KEY_RE)-t[0-9]{3,}-.*#\\1#p" <<<"$b")"
  if [[ -z "$num" ]]; then
    [[ ! -f .specify/feature.json && "$b" == "$(cfg branch_prefix feat)/"* ]] || return 0
    b="$(sed -nE "s#^[^/]+/(($FEATURE_KEY_RE)-.+)#\\1#p" <<<"$b")"
    if [[ -n "$b" && -d "specs/$b" ]]; then echo "specs/$b"; fi
    return 0
  fi
  matches="$(find specs -mindepth 1 -maxdepth 1 -type d -name "$num-*" 2>/dev/null)"
  if [[ -n "$matches" && "$(wc -l <<<"$matches")" -eq 1 ]]; then echo "$matches"; fi
}

feature_dir() {
  local d="" f=.specify/feature.json
  # On a task branch, the branch says which feature it belongs to. That wins, so a worktree never
  # acts on whatever feature the main checkout moved on to.
  d="$(branch_feature)"
  if [[ -n "$d" ]]; then echo "$d"; return; fi
  # A new worktree has no untracked files: fall back to the main worktree's active feature.
  [[ -f "$f" ]] || f="$(git rev-parse --git-common-dir)/../.specify/feature.json"
  d="$(sed -n 's/.*"feature_directory": *"\([^"]*\)".*/\1/p' "$f" 2>/dev/null)"
  [[ -n "$d" && -d "$d" ]] || die "no active feature (.specify/feature.json); run /speckit-specify first"
  echo "$d"
}

# feature_branch <feature dir>: the feature's one branch, <branch_prefix>/<folder name>.
feature_branch() { echo "$(cfg branch_prefix feat)/$(basename "$1")"; }

# legacy_feature <feature dir>: true when the feature was started under the per-task flow (a
# tasks.md line ends in " — #N").
legacy_feature() { grep -qE ' — #[0-9]+[[:space:]]*$' "$1/tasks.md" 2>/dev/null; }
# refuse_legacy <feature dir>: a legacy feature prints LEGACY=<name> and stops with the one way on (research R11).
refuse_legacy() {
  legacy_feature "$1" || return 0
  echo "LEGACY=$(basename "$1")"
  die "$(basename "$1") was started under the per-task flow: finish its open task PRs as ordinary PRs, then delete the ' — #N' suffix (and close the issue) of each remaining task in $1/tasks.md to continue it"
}

# task_done <feature dir> <Tnnn>: true when the feature branch (local, else origin's) holds the task's
# landing commit: anywhere in its history, a commit whose message has the line "Landspec-Task: <NNN>/<Tnnn>".
# The feature's number is in it because task ids restart at T001 in every feature: however the branch was
# joined (a PR merge, a pull merge, a squash), its own landings are found and never another feature's.
task_done() {
  local b r; b="$(feature_branch "$1")"; r="refs/heads/$b"
  git show-ref --verify --quiet "$r" || r="refs/remotes/origin/$b"
  [[ -n "$(git log -1 --format=%H --grep="^Landspec-Task: $(feature_key "$1")/$2\$" "$r" -- 2>/dev/null)" ]]
}

# plain_tasks <tasks.md> [issue]: its text with every task tick read as "- [ ]" and the "**Issue**: #N"
# line, with the blank line after it, left out (kept when "issue" is given): what landing a task and
# writing the feature's issue never change.
plain_tasks() {
  awk -v keep="${2:-}" 'drop && /^[[:space:]]*$/ { drop = 0; next } { drop = 0 }
    keep == "" && /^\*\*Issue\*\*: #[0-9]+[[:space:]]*$/ { drop = 1; next }
    /^- \[[xX]\] T[0-9][0-9][0-9]/ { sub(/^- \[[xX]\]/, "- [ ]") } { print }' "$1"
}

# carry_switch <dir> <target> <git switch args...>: switch branches with <dir>'s current content
# (uncommitted files too) carried over; nothing else is touched.
carry_switch() {
  CARRY_DIR="$1"; local target="$2" err; shift 2
  CARRY_SAVED="$(mktemp -d)"; cp -R "$CARRY_DIR" "$CARRY_SAVED/"
  # If anything fails before the restore below (a switch refused because of other local
  # changes), the folder comes back as it was, instead of surviving only in a temp dir.
  trap 'carry_restore; echo "landspec: the spec folder was put back as it was" >&2' EXIT
  git checkout --quiet -- "$CARRY_DIR" 2>/dev/null || true; git clean -fdq -- "$CARRY_DIR"
  if ! err="$(git switch --quiet "$@" 2>&1)"; then
    echo "$err" >&2
    die "cannot switch to $target: local changes outside $CARRY_DIR conflict with it. Commit or stash them (git stash push -- <file>), then run again"
  fi
  carry_restore; trap - EXIT
}
carry_restore() { rm -rf "$CARRY_DIR"; mkdir -p "$(dirname "$CARRY_DIR")"; cp -R "$CARRY_SAVED/$(basename "$CARRY_DIR")" "$CARRY_DIR"; rm -rf "$CARRY_SAVED"; }

# base_ref [<branch>]: what <branch> (default: the current one) is diffed against: its parent task
# branch while it is stacked on one (branch.<b>.landspec-parent), else the base branch. The base is
# origin's copy when it exists, else the local one; a parent is the local branch first (the child
# starts from its reviewed head, which may not be pushed yet), else origin's copy.
base_ref() {
  local b="${1-}" p=""
  [[ $# -gt 0 ]] || b="$(git branch --show-current 2>/dev/null || true)"
  [[ -z "$b" ]] || p="$(git config --get "branch.$b.landspec-parent" 2>/dev/null || true)"
  if [[ -n "$p" ]] && git show-ref --verify --quiet "refs/heads/$p"; then echo "$p"; return; fi
  [[ -n "$p" ]] || p="$(base_branch)"
  if git rev-parse --verify --quiet "origin/$p" >/dev/null; then echo "origin/$p"; else echo "$p"; fi
}

# branch_tip [<branch>]: the commit a diff of <branch> ends at: HEAD without a branch.
branch_tip() { if [[ -n "${1-}" ]]; then echo "refs/heads/$1"; else echo HEAD; fi; }

# diff_base [<branch>]: the commit where the branch left what it is diffed against (its tip itself
# when they share no history).
diff_base() { local t; t="$(branch_tip "$@")"; git merge-base "$t" "$(base_ref "$@")" 2>/dev/null || git rev-parse "$t"; }

# Every diff whose bytes decide a record: the same text whatever the user's git config says.
LANDSPEC_DIFF_FLAGS=(--no-color --no-ext-diff --no-textconv --ignore-submodules=none --submodule=short -U3 --inter-hunk-context=0 --no-renames --diff-algorithm=myers --src-prefix=a/ --dst-prefix=b/)
# landspec_diff <git diff args>: git diff with those flags, plus the two settings that have no flag.
landspec_diff() { git -c core.quotePath=false -c diff.suppressBlankEmpty=false diff "${LANDSPEC_DIFF_FLAGS[@]}" "$@"; }
# landspec_numstat <git diff args>: only the --numstat lines: -U3 adds the patch after a blank line, and
# --no-patch would also drop the numstat on older git.
landspec_numstat() { landspec_diff --numstat "$@" | sed '/^$/,$d'; }

# diff_id: the patch id of the branch against the base (empty for an empty diff). Merging the base
# in keeps it, any edit changes it. --verbatim keeps whitespace, so a re-indent (Python, YAML,
# Makefiles) counts. Dies when an empty id would not mean an empty diff: callers read it in a plain
# assignment, `|| exit 1`.
# shellcheck disable=SC2120 # review.sh --branch passes the branch
diff_id() {
  local from id ref t opt=--verbatim; from="$(diff_base "$@")"; ref="$(base_ref "$@")"; t="$(branch_tip "$@")"
  git patch-id --verbatim </dev/null >/dev/null 2>&1 || opt=--stable # git < 2.39: whitespace-only edits slip
  id="$(landspec_diff "$from" "$t" | git patch-id "$opt" | cut -d' ' -f1)"
  if ! git merge-base "$t" "$ref" >/dev/null 2>&1; then
    if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
      die "this shallow clone has no merge base with $ref; run git fetch --unshallow"
    fi
    die "this branch shares no history with $ref, so it has no diff to review"
  fi
  [[ -n "$id" ]] || landspec_diff --quiet "$from" "$t" || die "git patch-id gave no id for this diff against $ref"
  echo "$id"
}

# diff_record <kind>: the file that holds this diff's <kind> record (landspec-mutants, landspec-security),
# under .git so it never dirties the tree; its folder is created. Any commit makes it a new file.
diff_record() {
  local d id; d="$(git rev-parse --git-common-dir)/$1"; id="$(diff_id)" || exit 1
  mkdir -p "$d"; echo "$d/${id:-empty}"
}

# run_tests: run the constitution's test command (none: return 0, the caller says so), logged under
# .git/landspec-test, one log per branch. A green run on a clean tree is recorded by copy, tree and
# command, and that triple is not run again; any edit, commit or other command runs it again. Red
# records nothing. Ignored files (deps, .env) and the environment are not part of the key.
run_tests() {
  local cmd d key log clean=false; cmd="$(constitution_cmd test)"; [[ -n "$cmd" ]] || return 0
  d="$(git rev-parse --git-common-dir)/landspec-test"; mkdir -p "$d"
  key="$(printf '%s %s %s' "$(git rev-parse --show-toplevel)" "$(git rev-parse 'HEAD^{tree}')" "$cmd" | sha256)"
  [[ -z "$(git status --porcelain -- . ':(exclude).claude/worktrees')" ]] && clean=true
  if $clean && [[ -f "$d/$key" ]]; then echo "landspec: tests already green for this tree ($cmd)"; return 0; fi
  log="$(git branch --show-current)"; log="${log:-$key}" # a detached copy logs by key
  log="$d/${log//\//__}.log"
  if ! bash -c "$cmd" </dev/null >"$log" 2>&1; then tail -n 20 "$log" >&2; return 1; fi
  if $clean; then : >"$d/$key"; fi
}

# resolve_feature <NNN | folder name>: the specs/ folder of a feature named by number or folder.
resolve_feature() {
  local m
  if [[ -d "specs/$1" ]]; then echo "specs/$1"; return; fi
  m="$(find specs -mindepth 1 -maxdepth 1 -type d -name "$1-*" 2>/dev/null)"
  [[ -n "$m" && "$(wc -l <<<"$m")" -eq 1 ]] || die "no single feature matches '$1' in specs/"
  echo "$m"
}

# constitution_markers <file>: refuse a damaged landspec block before anything is changed. Only a marker
# at the start of a line counts: one mentioned in prose is plain text, and so is a file with none.
constitution_markers() {
  [[ -f "$1" ]] || return 0
  local s e first_s first_e
  read -r s e first_s first_e < <(awk '/^<!-- landspec:start/ { s++; if (!a) a = NR } /^<!-- landspec:end -->/ { e++; if (!b) b = NR }
    END { print s + 0, e + 0, a + 0, b + 0 }' "$1")
  if ((s == 0 && e == 0)) || ((s == 1 && e == 1 && first_s < first_e)); then return 0; fi
  if ((s == 1 && e == 0)); then die "$1 has '<!-- landspec:start' but no '<!-- landspec:end -->'; restore the end marker, then run again"; fi
  die "$1's landspec block is damaged: it needs one '<!-- landspec:start' line followed by one '<!-- landspec:end -->' line; fix the markers, then run again"
}

# constitution_cmd <build|test|lint|mutate>: that command from the constitution's **Commands**
# line ("build `x` · test `y` · ..."); empty when unset, still a [PLACEHOLDER], or none, n/a or -
# (a project with no such step: as a command, it would fail every CI run).
constitution_cmd() {
  local c
  c="$(sed -nE "s/.*\*\*Commands\*\*.*$1 \`([^\`]+)\`.*/\1/p" .specify/memory/constitution.md 2>/dev/null | head -1)"
  case "$(tr '[:upper:]' '[:lower:]' <<<"$c")" in ""|\[*|none|n/a|-) ;; *) echo "$c" ;; esac
}

# test_path_re: TEST_PATH_RE, plus the constitution's optional `tests: <regex>` line (grep -E) for
# any other layout. Dies on an invalid one: callers read it in a plain assignment, `|| exit 1`.
test_path_re() {
  local extra err rc=0
  extra="$(sed -nE 's/^tests:[[:space:]]*//p' .specify/memory/constitution.md 2>/dev/null | head -1)"
  extra="${extra%"${extra##*[![:space:]]}"}"
  if [[ -z "$extra" ]]; then echo "$TEST_PATH_RE"; return; fi
  # One input line: busybox grep compiles the pattern only when it reads a line. Exit > 1, or any
  # message, means the regex does not compile (GNU and BSD exit 2; busybox prints "bad regex").
  err="$(echo x | grep -E -- "$extra" 2>&1 >/dev/null)" || rc=$?
  ((rc <= 1)) && [[ -z "$err" ]] || die "the constitution's tests: regex is invalid: $extra"
  echo "$TEST_PATH_RE|$extra"
}

# version_newer <a> <b>: true when both are dotted numbers (optional leading v) and a > b; a missing
# part counts as 0 (v2 = v2.0.0). Anything else (a branch name) is never newer. No `sort -V` (BSD).
version_newer() {
  local a="${1#v}" b="${2#v}" x y re='^[0-9]+(\.[0-9]+)*$'
  [[ "$a" =~ $re && "$b" =~ $re ]] || return 1
  while [[ -n "$a$b" ]]; do
    x="${a%%.*}"; y="${b%%.*}"
    if ((10#${x:-0} > 10#${y:-0})); then return 0; fi
    if ((10#${x:-0} < 10#${y:-0})); then return 1; fi
    if [[ "$a" == *.* ]]; then a="${a#*.}"; else a=""; fi
    if [[ "$b" == *.* ]]; then b="${b#*.}"; else b=""; fi
  done
  return 1
}

# The task line for an ID, e.g. "- [ ] T003 [P] [US1] Do x in src/x.py — #12".
task_line() { grep -m1 -E "^- \[.\] $2 " "$1/tasks.md" || true; }

# The issue number linked on a task line ("— #12" at the end), or empty.
task_issue() { sed -nE 's/.* — #([0-9]+)[[:space:]]*$/\1/p' <<<"$1"; }

# Task description without checkbox, ID, [P]/[USn] markers or the issue link.
task_desc() {
  sed -E 's/^- \[.\] T[0-9]{3,} //; s/^(\[P\] )?(\[US[0-9]+\] )?//; s/ — #[0-9]+[[:space:]]*$//' <<<"$1"
}

# "Completed when:" sub-bullet of a task, if the task has one.
# infra_files: tracked and new (not ignored) Dockerfiles and Terraform files, one per line.
# The single answer to "does this project have infrastructure?", for CI, Dependabot and scans.
infra_files() {
  git ls-files --cached --others --exclude-standard 2>/dev/null | grep -E '(^|/)(Dockerfile[^/]*|[^/]+\.tf)$' || true
}

# task_summary <task line>: the description without its file list, for titles and branch names.
# Drops a trailing "(depends on …)" (any case; BSD sed has no I flag), then cuts at " in `path`"
# or at " in some/path…" (spec-kit writes the paths either way).
task_summary() {
  task_desc "$1" | sed -E 's/[[:space:]]*\([Dd][Ee][Pp][Ee][Nn][Dd][Ss] [Oo][Nn][^)]*\)[[:space:]]*$//; s/ in `.*//; s/ in [^ ]*[/][^ ]*.*//'
}

# feature_key <feature dir or name>: its number, as spec-kit names features: a sequential prefix
# of 3+ digits (001-search -> 001) or a timestamp (20261104-153000-search -> 20261104-153000).
FEATURE_KEY_RE='[0-9]{8}-[0-9]{6}|[0-9]{3,}'
feature_key() { basename "$1" | sed -nE "s/^($FEATURE_KEY_RE)-.*/\1/p"; }

# task_field <feature dir> <Tnnn> <Field>: the "  - <Field>:" sub-bullet of a task, with every line
# indented under it (nested lists, blank lines between them) up to the next sibling field or task.
# Newlines are kept and the field's 4-space indent removed, so a nested list stays markdown.
task_field() {
  awk -v id="$2" -v key="$3" '
    $0 ~ "^- \\[.\\] " id " " { inside = 1; next }
    inside && /^- \[/ { exit }
    found && /^[[:space:]]*$/ { blanks = blanks "\n"; next }
    found && /^    / { sub(/^    /, ""); value = value blanks "\n" $0; blanks = ""; next }
    found { exit }
    inside && index($0, "  - " key ":") == 1 { sub("^  - " key ":[[:space:]]*", ""); value = $0; found = 1 }
    END { if (found) print value }
  ' "$1/tasks.md"
}

sha256() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

# origin_slug: owner/name of origin when it is on github.com, else empty. Never fails.
origin_slug() {
  git remote get-url origin 2>/dev/null | sed -nE 's#\.git$##; s#^(.*[@/])?github\.com[:/]([^/]+/[^/]+)$#\2#p' || true
}

# owner/name of the GitHub repo: origin's, else from gh, else empty. Never fails. Origin first:
# `gh repo view` ignores GH_REPO and can name another remote.
repo_slug() {
  local s
  s="$(origin_slug)"
  [[ -n "$s" ]] || s="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  echo "$s"
}

# add_meta <issue|pr> <url>: assign the user, and set the configured milestone and project.
# Runs after creation, one edit per item, and only warns: optional metadata never stops a run
# halfway (a bot token that can't be assigned, a closed milestone, a token without project scope).
add_meta() {
  local kind="$1" url="$2" m p err i
  m="$(cfg milestone "")"; p="$(cfg project "")"
  local a=(--add-assignee @me)
  [[ -n "$m" ]] && a+=(--milestone "$m")
  [[ -n "$p" ]] && a+=(--add-project "$p")
  for ((i = 0; i < ${#a[@]}; i += 2)); do
    if ! err="$(gh "$kind" edit "$url" "${a[i]}" "${a[i+1]}" 2>&1 >/dev/null)"; then
      echo "landspec: warning: could not set ${a[i]#--} '${a[i+1]}' on $url: ${err:-unknown error}" >&2
      if [[ "${a[i]}" == --add-project ]]; then echo "landspec: (project access needs: gh auth refresh -s project)" >&2; fi
    fi
  done
}

# pr_branches <workflow>: the patterns of on.pull_request.branches, one per line; none = every branch.
# shortcut: branches-ignore and a one-line `pull_request: {branches: [...]}` are not read, so those workflows get no warning; read them when a repo needs it
pr_branches() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    { sub(/[[:space:]]+#.*/, ""); match($0, /^ */); i = RLENGTH }
    !pr { if (/^ *pull_request:/) { pr = 1; top = i }; next }
    i <= top { exit }
    list && i >= key && /^ *- / { sub(/^ *- */, ""); print; next }
    { list = 0 }
    /^ *branches:/ { key = i; sub(/^ *branches: */, ""); if ($0 == "") list = 1; gsub(/[][]/, ""); gsub(/, */, "\n"); if ($0 != "") print }
  ' "$1" | tr -d "\"' "
}
pr_skips_base() { # pr_skips_base <workflow> [<branch>]: its pull_request filter has no pattern for <branch> (default: the base)
  local p b list; b="${2:-$(base_branch)}"; list="$(pr_branches "$1")"
  [[ -n "$list" ]] || return 1
  while IFS= read -r p; do
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    if [[ "$b" == $p ]]; then return 1; fi
  done <<<"$list"
}

# closed_issues <feature dir>: " n1 n2 " the closed issues among its tasks' (fails with gh's error).
# One API call per feature, by issue number, so a renamed issue still counts. None when no task
# has an issue (an empty repository { } is an invalid query).
# shortcut: one query per feature, fine for hundreds of tasks; split into batches of ~100 if a feature ever nears GitHub's 10 s timeout
closed_issues() {
  local nums q="" i out
  nums="$(sed -nE '/^- \[.\] T[0-9]{3,} /s/.* — #([0-9]+)[[:space:]]*$/\1/p' "$1/tasks.md" | sort -u)"
  [[ -n "$nums" ]] || { echo " "; return 0; }
  for i in $nums; do q+="i$i: issue(number: $i) { number state } "; done
  out="$(gh api graphql -F owner='{owner}' -F name='{repo}' \
    -f query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { $q} }" \
    --jq '.data.repository[] | select(.state == "CLOSED") | .number')" || return 1
  echo " $(tr '\n' ' ' <<<"$out") "
}
