# Test helpers: a throwaway repo with a local bare "origin" and a fake `gh` on PATH.
# shellcheck shell=bash disable=SC2034  # SCRIPTS and FAIL are used by the test files
unset GH_REPO # pr.sh exports it for gh; a test starts from none, as a fresh shell does
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/extension/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
# A session that forces one subagent model would add a warning to every review record.
unset CLAUDE_CODE_SUBAGENT_MODEL_FORCE

# Each check runs in a subshell with set -e: an `exit` inside it can't end the test file, and in
# "a; b" a failing a fails the check (not just b).
# (bash ignores set -e inside an `if` condition, even in a subshell: so run it as a plain command.)
check() { # check "<when..., then...>" <command string>
  local rc
  set +e; (set -e; eval "$2") >/dev/null 2>&1; rc=$?; set -e
  if ((rc == 0)); then echo "ok   - $1"; else echo "FAIL - $1"; FAIL=1; fi
}

# fails_with <text> <cmd...>: the command fails and its output mentions <text>.
fails_with() {
  local text="$1" out; shift
  if out="$("$@" 2>&1)"; then return 1; fi
  grep -qF -- "$text" <<<"$out"
}

# one_refusal <text> <cmd...>: the command fails with exactly one stderr line, which mentions <text>.
one_refusal() {
  local text="$1" err rc=0; shift
  err="$("$@" 2>&1 >/dev/null)" || rc=$?
  ((rc != 0)) && [[ "$err" == *"$text"* && "$(wc -l <<<"$err")" -eq 1 ]]
}

# Fake GitHub CLI: issues and PRs are numbered from a counter; every call is logged.
fake_gh() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
echo "${GH_REPO:-(unset)} $1 $2" >> "$GH_LOG.repo"
case "$1 $2" in
  "api graphql") # next.sh's issue-state query: prints, as its --jq does, the asked numbers in $GH_CLOSED
                 if [[ -n "${GH_FAIL_GRAPHQL:-}" ]]; then echo "gh: Could not resolve to an Issue with the number of $GH_FAIL_GRAPHQL." >&2; exit 1; fi
                 for q in $(grep -oE 'issue\(number: *[0-9]+' <<<"$*" | grep -oE '[0-9]+$'); do
                   if grep -qx "$q" "$GH_CLOSED" 2>/dev/null; then echo "$q"; fi
                 done; exit 0 ;;
  "api repos/"*) # check-tools.sh's release-list lookup: $GH_API is a JSON object of
                 # "<owner>/<repo>": [releases as GitHub's JSON], filtered by the call's own --jq
                 # (real jq); a repo it does not list fails.
                 r="${2#repos/}"; r="${r%%/releases*}"
                 q=""; a=("$@"); for ((i = 0; i < ${#a[@]}; i++)); do if [[ "${a[i]}" == --jq ]]; then q="${a[i+1]:-}"; fi; done
                 if ! l="$(jq -ce --arg r "$r" '.[$r]' <<<"${GH_API:-null}")"; then echo "HTTP 404: Not Found (https://api.github.com/$2)" >&2; exit 1; fi
                 jq -r "$q" <<<"$l"; exit ;;
  "issue create") n=$(( $(cat "$GH_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$GH_N"
                  # GH_FAIL_CREATE_ONCE: the first create reaches GitHub (listed by `issue list`
                  # from then on) but fails on the client, as a dropped connection does.
                  if [[ -n "${GH_FAIL_CREATE_ONCE:-}" && ! -f "$GH_N.failed" ]]; then
                    touch "$GH_N.failed"; t=""; while (($#)); do if [[ "$1" == --title ]]; then t="$2"; fi; shift; done
                    echo "$n $t" >> "$GH_CLOSED"; echo "Post https://api.github.com/graphql: unexpected EOF" >&2; exit 1
                  fi
                  echo "https://github.com/acme/app/issues/$n" ;;
  "label create") exit 0 ;;
  "pr list") if [[ -n "${GH_FAIL_PR_LIST:-}" ]]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
             # GH_PR_JSON: the PRs as GitHub's JSON, filtered by the call's own --jq (real jq)
             if [[ -n "${GH_PR_JSON:-}" ]]; then q=""; a=("$@"); for ((i = 0; i < ${#a[@]}; i++)); do if [[ "${a[i]}" == --jq ]]; then q="${a[i+1]:-}"; fi; done
               jq -r "$q" "$GH_PR_JSON"; exit; fi
             # --head <branch>: only the PR created for that branch (its head is kept in $GH_PR.head)
             h=""; a=("$@"); for ((i = 0; i < ${#a[@]}; i++)); do if [[ "${a[i]}" == --head ]]; then h="${a[i+1]:-}"; fi; done
             if [[ "$*" == *mergeCommit* ]]; then cat "$GH_REL" 2>/dev/null # implement.sh release-plan: "<n>\t<title>\t<head>\t<state>\t<merge sha>\t<merged at>"
             elif [[ "$*" == *headRefName* && "$*" == *"--state all"* ]]; then cat "$GH_ALL" 2>/dev/null # implement.sh restack: every PR, with its state
             elif [[ "$*" == *headRefName* ]]; then cat "$GH_OPEN" 2>/dev/null
             elif [[ -n "$h" ]]; then if [[ -f "$GH_PR" && "$(cat "$GH_PR.head" 2>/dev/null)" == "$h" ]]; then cat "$GH_PR"; fi
             elif [[ -f "$GH_PR" ]]; then cat "$GH_PR"; fi; exit 0 ;;
  "pr create") if [[ -n "${GH_NO_DRAFT:-}" && "$*" == *--draft* ]]; then echo "GraphQL: Draft pull requests are not supported in this repository" >&2; exit 1; fi
               h=""; a=("$@"); for ((i = 0; i < ${#a[@]}; i++)); do if [[ "${a[i]}" == --head ]]; then h="${a[i+1]:-}"; fi; done
               echo "$h" > "$GH_PR.head"; echo "https://github.com/acme/app/pull/99" | tee "$GH_PR" ;;
  "issue list") if [[ -n "${GH_FAIL_ISSUE_LIST:-}" ]]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
                cat "$GH_CLOSED" 2>/dev/null; exit 0 ;;
  "repo view") exit 1 ;;
  "issue view") printf '%s\n%s\n' "${GH_VIEW_STATE:-OPEN}" "${GH_VIEW_BODY:-an older body}"; exit 0 ;; # as --jq '.state + "\n" + .body
  "release view") if grep -qxF "$3" "$GH_RELEASES" 2>/dev/null; then echo "{\"tagName\":\"$3\"}"; else echo "release not found" >&2; exit 1; fi ;;
  "pr view") echo "${GH_PR_DRAFT:-false}"; exit 0 ;; # as --json isDraft --jq .isDraft
  "pr ready") if [[ -n "${GH_FAIL_READY:-}" ]]; then echo "GraphQL: Pull request is in clean status" >&2; exit 1; fi ;;
  "issue edit"|"pr edit") if [[ -n "${GH_FAIL_EDIT:-}" ]]; then echo "GraphQL: Could not resolve to a ProjectV2" >&2; exit 1; fi ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TMP/bin/gh"
  export PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_N="$TMP/gh.n" GH_PR="$TMP/gh.pr" GH_CLOSED="$TMP/gh.closed" GH_OPEN="$TMP/gh.open" GH_ALL="$TMP/gh.all" GH_REL="$TMP/gh.rel" GH_RELEASES="$TMP/gh.releases"
}

# Fake AWS CLI: every call is logged to $TMP/aws.calls; AWS_FAIL=1 fails every call as with no
# credentials, AWS_FAIL=<operation> (e.g. simulate-principal-policy) only that one; `sts get-caller-identity` prints $AWS_IDENTITY_JSON, `iam get-role` $AWS_ROLE_JSON,
# `iam simulate-principal-policy` $AWS_SIM_JSON.
fake_aws() {
  mkdir -p "$TMP/bin"
  { printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$TMP/aws.calls"
    cat <<'EOF'
if [[ -n "${AWS_FAIL:-}" && ("$AWS_FAIL" == 1 || "$AWS_FAIL" == "${2:-}") ]]; then echo "Unable to locate credentials. You can configure credentials by running \"aws configure\"." >&2; exit 255; fi
case "$1 $2" in
  "sts get-caller-identity") printf '%s\n' "${AWS_IDENTITY_JSON:-}" ;;
  "iam get-role") printf '%s\n' "${AWS_ROLE_JSON:-}" ;;
  "iam simulate-principal-policy") printf '%s\n' "${AWS_SIM_JSON:-}" ;;
esac
EOF
  } > "$TMP/bin/aws"
  chmod +x "$TMP/bin/aws"
  export PATH="$TMP/bin:$PATH"
}

# Fake terraform: `show -json <planfile>` prints the file $TF_PLAN_JSON names, `show -no-color
# <planfile>` the file $TF_PLAN_TEXT names; a planfile that is missing or says "corrupt" fails as
# Terraform does. Every call is logged to $TF_LOG.
fake_terraform() {
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/terraform" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TF_LOG"
pf="${*: -1}"
if [[ ! -f "$pf" ]] || grep -q corrupt "$pf"; then echo "Error: Failed to read the given file as a state or plan file" >&2; exit 1; fi
case "$1 $2" in
  "show -json") cat "$TF_PLAN_JSON" ;;
  "show -no-color") cat "$TF_PLAN_TEXT" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$TMP/bin/terraform"
  export PATH="$TMP/bin:$PATH" TF_LOG="$TMP/tf.log"
}

# no_scanners: builds $TMP/none, a PATH with every system tool except the scanners (and the tools
# that could fetch them), so a scan never depends on what this machine has installed, nor on the network.
no_scanners() {
  local f name
  [[ -d "$TMP/none" ]] && return
  mkdir -p "$TMP/none"
  for f in /usr/local/bin/* /usr/bin/* /bin/*; do
    name="${f##*/}"
    case "$name" in gitleaks|osv-scanner|semgrep|zizmor|trivy|uv|uvx|pipx|docker|podman) continue ;; esac
    [[ -e "$TMP/none/$name" || -L "$TMP/none/$name" ]] || ln -s "$f" "$TMP/none/$name"
  done
  ln -sf "$(command -v git)" "$TMP/none/git"; ln -sf "$(command -v bash)" "$TMP/none/bash"
}

# set_cfg <key> <value>: edit a config line in place, as a user would.
set_cfg() { sed -i.bak "s|^$1:.*|$1: $2|" .specify/extensions/landspec/landspec-config.yml; }

# new_repo <level>: repo at $TMP/repo with origin, extension linked, an active feature 001-demo.
new_repo() {
  git init --quiet --bare "$TMP/origin.git"
  git clone --quiet "$TMP/origin.git" "$TMP/repo" 2>/dev/null
  cd "$TMP/repo"
  git config user.email t@t; git config user.name t; git config commit.gpgsign false
  mkdir -p .specify/extensions specs/001-demo
  printf '# Spec\n\n- **FR-001**: the demo MUST search.\n' > specs/001-demo/spec.md # one requirement, for the plan review's tables
  mkdir -p .specify/extensions/landspec && ln -s "$ROOT/extension/scripts" .specify/extensions/landspec/scripts # as spec-kit installs it
  printf 'level: %s\nbase_branch: auto\nbranch_prefix: feat\nissue_labels: "type:task"\nmilestone: ""\nproject: ""\n' "$1" > .specify/extensions/landspec/landspec-config.yml
  echo '{ "feature_directory": "specs/001-demo" }' > .specify/feature.json
  # Local test state stays out of git so config edits never dirty the tree.
  printf '.specify/\n*.bak\n' > .gitignore
  git add -A; git commit --quiet -m init; git branch -M main
  git push --quiet origin main; git remote set-head origin main >/dev/null 2>&1 || git remote set-head origin -a >/dev/null
  git push --quiet origin main:develop
}

# shallow_repo [depth]: pushes the current branch, then enters $TMP/shallow, a real
# --no-single-branch clone at that depth (default 1, where the branch and the base share no history).
shallow_repo() {
  local b; b="$(git branch --show-current)"
  git push --quiet origin "$b"
  rm -rf "$TMP/shallow"
  git clone --quiet --depth "${1:-1}" --no-single-branch "file://$TMP/origin.git" "$TMP/shallow" 2>/dev/null
  cp -R .specify "$TMP/shallow/"
  cd "$TMP/shallow"
  git config user.email t@t; git config user.name t; git config commit.gpgsign false
  git switch --quiet "$b"
}

# plan_tables [<dir>]: every pass of review.sh's PASSES as a passing table: one size row per task id of
# <dir>/tasks.md, one requirements row per FR/SC id <dir>/spec.md defines (default: the active feature's folder).
# shellcheck disable=SC2120 # fx in review.test.sh passes <dir>; ShellCheck reads this file alone
plan_tables() {
  local d="${1:-$(sed -n 's/.*"feature_directory": *"\([^"]*\)".*/\1/p' .specify/feature.json)}" p id
  for p in $(sed -n 's/^PASSES="\(.*\)"$/\1/p' "$SCRIPTS/review.sh"); do
    printf '\n### Pass: %s\n\n| Item | Status |\n|---|---|\n' "$p"
    case "$p" in
      size) for id in $(sed -nE 's/^- \[[ xX]\] (T[0-9]+).*/\1/p' "$d/tasks.md" 2>/dev/null); do echo "| $id | holds |"; done
            grep -qE '^- \[[ xX]\] T[0-9]' "$d/tasks.md" 2>/dev/null || echo '| none: no task yet |' ;;
      requirements) for id in $(sed -nE 's/^- \*\*((FR|SC)-[0-9]+)\*\*.*/\1/p' "$d/spec.md" 2>/dev/null); do echo "| $id | proven |"; done
                    grep -qE '^- \*\*(FR|SC)-[0-9]+\*\*' "$d/spec.md" 2>/dev/null || echo '| none: no requirement |' ;;
      rules) echo '| a rule | SAME |' ;; claims) echo '| a claim | TRUE |' ;; inputs) echo '| an input | provided |' ;;
      guards) echo '| a guard | handled |' ;; rollout) echo '| a write | safe |' ;; orderings) echo '| an ordering | holds |' ;;
    esac
  done
}
# plan_report [<model>]: a ready plan report at $TMP/plan.md, every pass passing, with the current plan's state.
plan_report() {
  printf 'Plan read.\n%s\n\nPlan state: %s\nModel: %s\n\nAssessment: ready\n' "$(plan_tables)" "$("$SCRIPTS/review.sh" state --plan)" "${1:-claude-sonnet-4-7}" > "$TMP/plan.md"
}
# plan_review [<model>]: write that report and record it.
plan_review() { plan_report "$@" && "$SCRIPTS/review.sh" record --plan "$TMP/plan.md"; }

# commit_tasks <content>: write tasks.md, commit it on main and develop.
commit_tasks() {
  printf '%s\n' "$1" > specs/001-demo/tasks.md
  git add -A; git commit --quiet -m tasks; git push --quiet origin main; git push --quiet origin main:develop
}
