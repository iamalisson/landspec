#!/usr/bin/env bash
# Push the current work and open (or reuse) its pull request.
#   pr.sh task T003 "feat(api): add price search" [body-file]
#       On the task's branch, with the work already committed. Adds "Closes #N".
#       Every level requires a "## Review" section in the body and a recorded independent review
#       that said "ready" for this exact diff (review.sh), whose recorded facts it adds to the
#       body, folded: patch id, Assessment line, model, any warning and the risk maps as paths;
#       "full" also requires "## Evidence".
#       Runs the constitution's test command before the push and refuses when it fails.
#       On an open PR, replaces its body from body-file.
#   pr.sh fix "fix(api): handle empty cart" <body-file>
#       Any other PR (a small fix, a dependency bump, landspec's setup), from its own branch: the same
#       review, mutants, scan and test gate as a task, without an issue.
#   pr.sh spec ["<title>"]
#       Stops without a current plan review. Commits the active feature's spec folder on
#       spec/<feature> and opens a docs PR, or updates the open one (its generated body too, so a
#       new task issue shows). The title, in the project's language, names the commit and a new PR;
#       without one, the commit says "add" on a new spec PR and "update" on an open one.
#   pr.sh state <pr>
#       Reads the PR (no feature needed, nothing requested, nothing waited for) and prints
#       CONFLICT=no|yes|unknown, CI=pass|pending|fail <name> (<conclusion>),…|none and
#       COPILOT=pending|comments <n> REPORT=<file> [RESOLVE=<id>,…]|unavailable <reason>|clean|none.
#       The report lists Copilot's unanswered threads under "## Findings".
#   pr.sh state <pr> --reply <thread id> [<file>]
#       Posts <file> as the reply to Copilot's unanswered thread and resolves it (REPLIED=<id>), or
#       only resolves one already replied to (RESOLVED=<id>).
# Prints: PR=<url>
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

landspec_cd_root
command -v gh >/dev/null || die "the GitHub CLI (gh) is required: https://cli.github.com"
fdir=""; [[ "${1:-}" == fix || "${1:-}" == state ]] || fdir="$(feature_dir)" # a fix PR, or any PR's state, belongs to no feature
base="$(base_branch)"
mode="${1:-}"

# With a body file (a task PR, whose body must describe the new diff), an open PR's body is replaced.
open_pr() { # open_pr <title> <body> [body-file]
  local url err
  url="$(gh pr list --head "$(git branch --show-current)" --state open --json url,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)][0].url // empty')" \
    || die "could not check for an open PR"
  if [[ -z "$url" ]]; then
    # A stacked PR opens as a draft: GitHub cannot merge a draft, so it never lands in its parent.
    if [[ -n "${parent:-}" ]]; then
      local ef; ef="$(mktemp)"
      if ! url="$(gh pr create --draft --base "$base" --head "$(git branch --show-current)" --title "$1" --body "$2" 2>"$ef")"; then
        grep -qi draft "$ef" || { cat "$ef" >&2; die "could not open the PR"; }
        echo "landspec: warning: drafts are not available: merge #$parent_pr first, and only after this PR's review is current" >&2
        url="$(gh pr create --base "$base" --head "$(git branch --show-current)" --title "$1" --body "$2")"
      fi
      rm -f "$ef"
    else url="$(gh pr create --base "$base" --head "$(git branch --show-current)" --title "$1" --body "$2")"
    fi
    add_meta pr "$url"
  elif [[ -n "${3:-}" ]]; then
    err="$(gh pr edit "$url" --body "$2" 2>&1 >/dev/null)" || die "could not update the body of $url: ${err%%$'\n'*}"
    echo "PR body replaced from $3; edits made on GitHub are gone"
  fi
  event pr mode="$mode" url="$url"
  echo "PR=$url"
}

case "$mode" in
  task|fix)
    # fix: any PR that is not a task (a small fix, a dependency bump, landspec's own setup) gets the
    # same gate, so no PR opens without a recorded review at any level; only "Closes #N" is task-only.
    branch="$(git branch --show-current)"; issue=""
    if [[ "$mode" == task ]]; then
      task="${2:-}"; title="${3:-}"; body_file="${4:-}"
      [[ "$task" =~ ^T[0-9]{3,}$ && -n "$title" ]] || die 'usage: pr.sh task T003 "type(scope): summary" [body-file]'
      line="$(task_line "$fdir" "$task")"
      issue="$(task_issue "$line")"
      [[ -n "$issue" ]] || die "$task has no issue"
      num="$(feature_key "$fdir")"
      [[ "$branch" == */"$num-$(tr '[:upper:]' '[:lower:]' <<<"$task")-"* ]] \
        || die "not on $task's branch for feature $num (on '$branch'); run /speckit-implement $task"
    else
      title="${2:-}"; body_file="${3:-}"
      [[ -n "$title" && -n "$body_file" ]] || die 'usage: pr.sh fix "type(scope): summary" <body-file>'
      [[ -n "$branch" ]] && ! is_protected "$branch" \
        || die "on '${branch:-a detached HEAD}': a PR comes from its own branch (git switch -c fix/<slug>), never a base branch"
    fi
    # A reviewer's copy (Claude Code puts it under .claude/worktrees) is not the author's work.
    dirty="$(git status --porcelain -- . ':(exclude).claude/worktrees' | awk 'NR <= 5 { printf "%s ", substr($0, 4) }')" # awk reads it all: head would SIGPIPE git under pipefail
    [[ -z "$dirty" ]] || die "uncommitted changes; commit the work first (or git-ignore what the tests create): $dirty"
    # A task stacked on another task's branch (branch.sh --from) opens its PR into that branch.
    parent=""; parent_pr=""
    if [[ "$mode" == task ]]; then parent="$(git config --get "branch.$branch.landspec-parent" || true)"; fi
    if [[ -n "$parent" ]]; then
      parent_pr="$(gh pr list --head "$parent" --state all --json url,state,isCrossRepository --jq '[.[] | select(.state != "CLOSED") | select(.isCrossRepository | not)][0].url // empty')" \
        || die "could not look up the PR of $parent"
      [[ -n "$parent_pr" ]] || die "open the PR of $parent first"
      parent_pr="${parent_pr##*/}"; base="$parent"
      for w in .github/workflows/*.y*ml; do
        [[ -f "$w" ]] && grep -qE '^[[:space:]]*pull_request:' "$w" || continue
        if pr_skips_base "$w" "$parent"; then echo "landspec: warning: $w never runs on a PR into $parent: its pull_request branches filter it out" >&2; fi
      done
    fi
    git fetch --quiet origin "$base" 2>/dev/null || true
    [[ -n "$(git log --oneline "$(base_ref)..HEAD" 2>/dev/null || git log --oneline -1)" ]] || die "no commits ahead of $base"

    body=""; [[ -n "$body_file" ]] && body="$(cat "$body_file")"
    if [[ "$(landspec_level)" == full ]] && ! grep -qE '^## Evidence' <<<"$body"; then
      die "level 'full' requires an '## Evidence' section in the PR body (test output, screenshots, run links)"
    fi
    grep -qE '^## Review' <<<"$body" \
      || die "the PR body needs a '## Review' section: the independent review's findings and what was done about them (/speckit-landspec-review)"
    # A test that changes to fit the code proves nothing: editing, renaming, skipping or deleting
    # an existing test needs a reason a reviewer can check. Lines only added need none; position
    # cannot decide, as a new test usually lands above a file's closing line.
    # --no-renames: a test moved out of a test folder counts as deleted, not as a new file.
    ref="$(base_ref)"
    git rev-parse --verify --quiet "$ref" >/dev/null || die "base branch '$base' not found locally or on origin"
    diff_id >/dev/null # no merge base: "$ref...HEAD" below would read as no changed tests
    re="$(test_path_re)" || exit 1
    changed_tests=""
    while IFS=$'\t' read -r added deleted f; do
      grep -qE -- "$re" <<<"$f" || continue
      new="$(landspec_diff -U0 "$ref...HEAD" -- "$f" | sed -n '/^@@/,$p' | grep '^+' || true)"
      # A binary file shows "-" and a mode-only change adds nothing: neither is lines only added.
      if ! [[ "$added" =~ ^[1-9] && "$deleted" == 0 ]] || grep -qiE -- "$TEST_SKIP_RE" <<<"$new"; then changed_tests+="$f"$'\n'; fi
    done < <(landspec_numstat --diff-filter=MD "$ref...HEAD")
    if [[ -n "$changed_tests" ]] && ! grep -qE '^## Test changes' <<<"$body"; then
      die "existing tests were changed: $(tr '\n' ' ' <<<"$changed_tests")
add a '## Test changes' section to the PR body saying why (spec changed, test was wrong). Never weaken a test to make it pass."
    fi
    # The review has to have happened, on this diff, and said ready: a heading alone proves nothing.
    # Only that recorded fact and its Assessment go in the body; the report's text never does (the agent's ## Review
    # carries them, a security finding as one line), so nothing private reaches a public PR here.
    review="$(bash "$LANDSPEC_EXT_DIR/scripts/review.sh" report)"
    # Mutation testing too, when the project has a mutate command: mutants.sh records it per diff.
    if [[ -n "$(constitution_cmd mutate)" ]]; then
      mutants="$(diff_record landspec-mutants)"
      [[ -f "$mutants" ]] || die "no mutants.sh result for this diff; run bash .specify/extensions/landspec/scripts/mutants.sh after the last commit"
      grep -q '^mutants unavailable' "$mutants" \
        && die "the mutate command could not run ($(constitution_cmd mutate)); install it or fix it in the constitution, then run mutants.sh again"
      evidence="$(sed -n '/^## Evidence/,/^## /p' <<<"$body")"
      if grep -q '^mutants survivors' "$mutants" && ! grep -qi surviv <<<"$evidence"; then
        die "mutants.sh found surviving mutants; say in '## Evidence' why each changes nothing, or add the test that kills it"
      fi
    else
      body+=$'\n\n'"Mutation testing: not run (no mutate command in the constitution)"
    fi
    # And the scanners on the changed files: a finding is for the body to say; one that did not run, the body names here.
    scan="$(diff_record landspec-security)"
    [[ -f "$scan" ]] \
      || die "no security-scan.sh --changed result for this diff; run bash .specify/extensions/landspec/scripts/security-scan.sh --changed after the last commit"
    gaps="$(awk '$2=="missing"||$2=="failed"{printf "%s%s (%s)", s, $1, $2; s=", "}' "$scan")"
    [[ -z "$gaps" ]] || body+=$'\n\n'"Scanners not run: $gaps"
    # With aws: on, an infrastructure diff needs its Terraform plan recorded (tfplan.sh), which the body shows.
    tfplan="$(bash "$LANDSPEC_EXT_DIR/scripts/tfplan.sh" gate)" || exit 1
    [[ -z "$tfplan" ]] || body+=$'\n\n'"$tfplan"
    # Never open a PR on red checks; a tree already green with this command is not run again (lib.sh run_tests).
    test_cmd="$(constitution_cmd test)"
    if [[ -n "$test_cmd" ]]; then
      t0="$(date +%s)"
      run_tests || { event tests secs=$(( $(date +%s) - t0 )) ok=0; die "the test command failed ($test_cmd); fix it before opening the PR"; }
      event tests secs=$(( $(date +%s) - t0 )) ok=1
    else
      echo "landspec: tests not run before the PR (no test command in the constitution)" >&2
    fi
    body+=$'\n\n<details><summary>Independent review</summary>\n\n'"$review"$'\n\n</details>'
    if [[ -n "$parent_pr" ]]; then body+=$'\n\n'"Stacked on #$parent_pr (merge it first)"; fi
    if [[ -n "$issue" ]] && ! grep -qiE "(close[sd]?|fix(e[sd])?|resolve[sd]?) #$issue([^0-9]|$)" <<<"$body"; then body+=$'\n\n'"Closes #$issue"; fi
    git push --quiet -u origin "$branch"
    open_pr "$title" "$body" "$body_file"
    ;;
  spec)
    bash "$LANDSPEC_EXT_DIR/scripts/review.sh" check --plan >/dev/null
    # A file tasks.md names that is only untracked here never reaches the base: whoever starts the
    # task from a clean clone has nothing to read.
    missing=""
    while IFS= read -r f; do
      [[ -n "$f" && "$f" != "$fdir"/* ]] || continue
      if grep -qF -- "\`$f\`" "$fdir/tasks.md"; then missing+=" $f"; fi # a path the tasks name, in backticks
    done < <(git ls-files --others --exclude-standard)
    [[ -z "$missing" ]] || die "tasks.md names files that are not in git:$missing. Move each into $fdir/ (it lands with the spec) or write what the task needs into the task, then run again"
    feature="$(basename "$fdir")"
    branch="spec/$feature"
    # An open spec PR is updated in place. Otherwise (first time, or a later run such as after
    # /speckit-converge, when the old spec PR may have been squash-merged) the branch starts
    # fresh from the base, so the new PR shows only what changed. A failed lookup stops here: taken
    # for "none open", the fresh start would overwrite the open PR's branch, teammates' commits too.
    open="$(gh pr list --head "$branch" --state open --json url,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)][0].url // empty')" \
      || die "could not check for an open spec PR"
    fresh=false
    if [[ "$(git branch --show-current)" != "$branch" || -z "$open" ]]; then
      ref="$(base_ref "")" # the base itself, never a parent task branch: a spec PR carries no task code
      # The spec folder's current content travels with us; nothing else is touched.
      if [[ -n "$open" ]]; then carry_switch "$fdir" "$branch" "$branch"; else carry_switch "$fdir" "$branch" --no-track -C "$branch" "$ref"; fresh=true; fi
    fi
    git add -- "$fdir"
    # "update" once the spec exists anywhere: an open PR, or a squash-merged one already on the base.
    title="${2:-}"; verb=add
    if [[ -n "$open" ]] || git cat-file -e "$(base_ref):$fdir" 2>/dev/null; then verb=update; fi
    git diff --cached --quiet || git commit --quiet -m "${title:-docs(specs): $verb $feature spec, plan and tasks}"
    # A fresh branch may replace a stale one left by a merged PR (no PR is open on it); the lease
    # still refuses if someone pushed to it since we last fetched.
    if $fresh; then git push --quiet --force-with-lease -u origin "$branch"; else git push --quiet -u origin "$branch"; fi
    issues="$(grep -oE ' — #[0-9]+$' "$fdir/tasks.md" | grep -oE '#[0-9]+' | tr '\n' ' ')"
    # The plan review's model warning, from its record (issues.sh refuses a missing or stale one).
    warn="$(bash "$LANDSPEC_EXT_DIR/scripts/review.sh" report --plan 2>/dev/null | sed -n 's/^warning: /**Plan review:** /p' || true)"
    [[ -z "$warn" ]] || warn=$'\n\n'"$warn"
    # The body is generated, so an open spec PR gets it again: the third argument says to replace it.
    open_pr "${title:-docs(specs): $feature}" "Spec, plan and tasks for \`$feature\`.

**Task issues:** ${issues:-none yet}$warn

Merge this before starting tasks: \`/speckit-implement Tnnn\` branches from \`$base\`, so it needs \`tasks.md\` there.

<details>
<summary>Why is the spec its own PR?</summary>

- Every task branch starts from \`$base\` and reads its issue from \`tasks.md\` there.
- Each task PR then stays small, independent and closes exactly one issue.
- The design gets reviewed before any code is written, while changing it is still cheap.

</details>" "the generated spec body"
    ;;
  state)
    # One read of the PR, shaped by gh's own --jq (no jq binary). Copilot is any login matching "copilot".
    # shortcut: 100 checks, threads and reviews, 30 comments per query (a real PR had 44 threads); page them if a PR ever passes that
    usage='usage: pr.sh state <pr> [--reply <thread id> [<file>]]'
    pr="${2:-}"; pr="${pr##*/pull/}"
    [[ "$pr" =~ ^[0-9]+$ ]] || die "$usage"
    q='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) {
      headRefOid mergeable
      commits(last: 1) { nodes { commit { oid statusCheckRollup { contexts(first: 100) { nodes { __typename
        ... on CheckRun { name status conclusion } ... on StatusContext { context state } } } } } } }
      reviewRequests(first: 20) { nodes { requestedReviewer { ... on Bot { login } ... on User { login } } } }
      reviews(last: 100) { nodes { author { login } commit { oid } body submittedAt } }
      comments(last: 30) { nodes { author { login } body createdAt } }
      reviewThreads(first: 100) { nodes { id isResolved isOutdated path line originalLine
        comments(first: 100) { nodes { author { login } databaseId body } } } } } } }'
    cp='def cp: (. // "") | test("copilot"; "i"); .data.repository.pullRequest as $p | '
    read_pr() { gh api graphql -F owner='{owner}' -F name='{repo}' -F pr="$pr" -f query="$q" --jq "$cp$1" || die "could not read PR #$pr"; }
    if [[ -z "${3:-}" ]]; then
      # A thread is Copilot's when Copilot wrote its first comment, and unanswered while Copilot wrote its last.
      out="$(read_pr '[$p.reviewThreads.nodes[] | select((.isResolved | not) and (.comments.nodes[0].author.login | cp))] as $open
        | [$open[] | select(.comments.nodes[-1].author.login | cp)] as $un
        | [$open[] | select(.comments.nodes[-1].author.login | cp | not) | .id] as $rs
        | [$p.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?] as $c
        | ([($p.reviews.nodes[] | select(.author.login | cp) | {t: .submittedAt, b: .body}),
            ($p.comments.nodes[] | select(.author.login | cp) | {t: .createdAt, b: .body})] | sort_by(.t) | last | .b // "") as $new
        | "CONFLICT=" + ({MERGEABLE: "no", CONFLICTING: "yes"}[$p.mergeable // ""] // "unknown"),
          "CI=" + (if ($c | length) == 0 then "none"
            elif any($c[]; if .__typename == "CheckRun" then .status != "COMPLETED" else .state == "PENDING" or .state == "EXPECTED" end) then "pending"
            else [$c[] | if .__typename == "CheckRun"
                then select(.conclusion | IN("FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE")) | "\(.name) (\(.conclusion))"
                else select(.state == "FAILURE" or .state == "ERROR") | "\(.context) (\(.state | ascii_downcase))" end]
              | if length > 0 then "fail " + join(",") else "pass" end end),
          "COPILOT=" + (if any($p.reviewRequests.nodes[]; .requestedReviewer.login | cp) then "pending"
            elif ($un | length) > 0 or ($rs | length) > 0 then "comments \($un | length) REPORT=@" + (if ($rs | length) > 0 then " RESOLVE=" + ($rs | join(",")) else "" end)
            elif ($new | test("unable to review"; "i")) then "unavailable " + ($new | sub("^\\s+"; "") | split("\n")[0] | (capture("^(?<s>.*?[.!?])(\\s|$)").s // .))
            elif any($p.reviews.nodes[]; .author.login | cp) then "clean" else "none" end),
          ($un[] | (.comments.nodes[0].body // "") as $b
            | "- \(.path):\(.line // .originalLine // 1) thread=\(.id)\(if .isOutdated then " (outdated)" else "" end) \($b | split("\n")[0])",
              ($b | split("\n") | map("  " + .) | join("\n")))')" || exit 1
      head -n 2 <<<"$out"
      copilot="$(sed -n 3p <<<"$out")"
      if [[ "$copilot" == *REPORT=@* ]]; then
        report="$(git rev-parse --git-common-dir)/landspec-review/copilot-$pr"; mkdir -p "${report%/*}"
        { echo "## Findings"; tail -n +4 <<<"$out"; } > "$report"
        copilot="${copilot/REPORT=@/REPORT=$report}"
      fi
      echo "$copilot"
    elif [[ "$3" == --reply ]]; then
      id="${4:-}"; file="${5:-}"
      [[ "$id" =~ ^[A-Za-z0-9_=-]+$ ]] || die "$usage" # a GraphQL node id; it goes into the --jq program below
      t="$(read_pr '$p.reviewThreads.nodes[] | select(.id == "'"$id"'")
        | "\(.comments.nodes[0].author.login | cp) \(.isResolved) \(.comments.nodes[-1].author.login | cp | not) \(.comments.nodes[0].databaseId)"')" || exit 1
      [[ -n "$t" ]] || die "thread $id is not on PR #$pr; nothing posted"
      read -r copilots resolved replied cid <<<"$t"
      [[ "$copilots" == true ]] || die "thread $id was not opened by Copilot; nothing posted"
      [[ "$resolved" == false ]] || die "thread $id is already resolved; nothing posted"
      if [[ "$replied" == false ]]; then
        grep -q '[^[:space:]]' "${file:-/dev/null}" 2>/dev/null || die "thread $id has no reply yet: give the reply as a non-empty file; nothing posted"
        gh api "repos/{owner}/{repo}/pulls/$pr/comments/$cid/replies" -F body=@"$file" >/dev/null \
          || die "could not post the reply to thread $id; nothing resolved"
        echo "REPLIED=$id"
      fi
      gh api graphql -F id="$id" -f query='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }' >/dev/null \
        || die "could not resolve thread $id; the next pr.sh state lists it in RESOLVE="
      [[ "$replied" == false ]] || echo "RESOLVED=$id"
    else die "$usage"
    fi
    ;;
  *) die "usage: pr.sh task T003 \"type(scope): summary\" [body-file] | pr.sh fix \"type(scope): summary\" <body-file> | pr.sh spec [\"<title>\"] | pr.sh state <pr> [--reply <thread id> [<file>]]" ;;
esac
