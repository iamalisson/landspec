#!/usr/bin/env bash
# Push the current work and open (or reuse) its pull request.
#   pr.sh feature "feat(api): price search" <body-file>
#       On the feature's branch: the gates of a fix PR on the whole diff from the base, except the
#       review record and "## Review" (each landed task carries its own review). Refuses a task ticked
#       [X] with no landing commit, and needs no scan or mutants record (the draft opens after the
#       first landing; they run once on the whole diff). Adds a "## Tasks" table, "## Low findings" (the
#       landing commits' Low: lines) and "## End check" from the feature's end-check record when there
#       is one. Opens a draft PR (or replaces the open one's body) and prints PR=<url> READY=no.
#   pr.sh feature "feat(api): price search" <body-file> --ready
#       Also refuses a task not done, a failing review.sh check --feature, and no scan or (with a mutate
#       command) mutants record of the whole feature diff; a "findings high" scan line refuses; other
#       findings, missing scanners and unavailable mutants are listed. Then gh pr ready; PR=<url> READY=yes.
#   pr.sh fix "fix(api): handle empty cart" <body-file>
#       Any other PR (a small fix, a dependency bump, landspec's setup), from its own branch. Every level
#       requires a "## Review" section in the body and a recorded independent review that said "ready"
#       for this exact diff (review.sh), whose recorded facts it adds to the body, folded: patch id,
#       Assessment line, model, any warning and the risk maps as paths; "full" also requires "## Evidence".
#       Runs the constitution's test command before the push and refuses when it fails.
#       On an open PR, replaces its body from body-file.
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
fdir=""; [[ "${1:-}" != feature ]] || fdir="$(feature_dir)" # a fix PR, or any PR's state, belongs to no feature
base="$(base_branch)"
mode="${1:-}"

# With a body file (whose body must describe the new diff), an open PR's body is replaced.
open_pr() { # open_pr <title> <body> [body-file]
  local url err
  url="$(gh pr list --head "$(git branch --show-current)" --state open --json url,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)][0].url // empty')" \
    || die "could not check for an open PR"
  if [[ -z "$url" ]]; then
    # The feature PR opens as a draft: GitHub cannot merge a draft before pr.sh feature --ready.
    if [[ "${draft:-}" == true ]]; then
      local ef; ef="$(mktemp)"
      if ! url="$(gh pr create --draft --base "$base" --head "$(git branch --show-current)" --title "$1" --body "$2" 2>"$ef")"; then
        grep -qi draft "$ef" || { cat "$ef" >&2; die "could not open the PR"; }
        echo "landspec: warning: drafts are not available: $nodraft" >&2
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
  if [[ "${ready:-}" == yes ]]; then gh pr ready "$url" >/dev/null || die "could not mark $url ready for review"; fi
  event pr mode="$mode" url="$url"
  echo "PR=$url${ready:+ READY=$ready}"
}

# feature_sections: the feature PR's generated "## Tasks" table and "## End check" (data-model
# "Feature PR"), into $extra; dies on a task ticked with no landing commit.
feature_sections() {
  local line t c rv st sum fr hd n v h r l lows=""
  record_field() { awk -v k="$1: " 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$fr"; }
  extra=$'\n\n## Tasks\n\n| Task | Summary | State | Landing commit | Review |\n|---|---|---|---|---|'
  while IFS= read -r line; do
    t="$(sed -E 's/^- \[.\] (T[0-9]{3,}) .*/\1/' <<<"$line")"
    c="$(git log -1 --format=%h --grep="^Landspec-Task: $(feature_key "$fdir")/$t\$" HEAD --)" # as task_done reads it, with the commit
    rv=""; st=pending
    if [[ -n "$c" ]]; then
      st=done; rv="$(git log -1 --format=%B "$c" | sed -nE 's/^Landspec-Review: ([a-z ]*[a-z]) ([0-9a-f]{12}).*/\1 (patch id \2)/p')"
      lows+="$(git log -1 --format=%B "$c" | sed -nE "s/^Low: (.*)/- $t: \1/p")"$'\n' # implement.sh land writes one per low finding
    elif grep -qE '^- \[[xX]\]' <<<"$line"; then die "$t is ticked but was never landed: untick it or run /landspec:implement"
    elif grep -q '^failed=.' "$(git rev-parse --git-common-dir)/landspec-run/$(basename "$fdir")/$t" 2>/dev/null; then st=failed
    fi
    [[ "$st" == done || "$ready" != yes ]] || die "$t is $st: every task is done before pr.sh feature --ready"
    sum="$(task_summary "$line" | sed 's/|/\\|/g')"
    extra+=$'\n'"| $t | $sum | $st | ${c:--} | ${rv:--} |"
  done < <(grep -E '^- \[.\] T[0-9]{3,} ' "$fdir/tasks.md" || true)
  lows="$(grep . <<<"$lows" || true)"
  [[ -z "$lows" ]] || extra+=$'\n\n## Low findings\n\n'"$lows"
  # The end-check record (data-model "End check"): "<field>: <value>" lines, then the review's lines.
  fr="$(git rev-parse --git-common-dir)/landspec-review/feature-$(basename "$fdir")"
  [[ -f "$fr" ]] || return 0
  hd="$(record_field head)"; [[ -n "$hd" ]] || return 0
  n="$(record_field heads | wc -w | tr -d ' ')" # one word per head checked: the round is their count
  extra+=$'\n\n## End check\n\n'"Head: $hd (round $n), tests: $(record_field tests)"
  v="$(record_field verdict)"
  extra+=$'\n'"Assessment: ${v:-not reviewed yet}"$'\n'
  while IFS= read -r l; do extra+=$'\n'"$l"; done < <(grep -E '^- (met|not met|not verifiable): ' "$fr" || true)
  h="$(git rev-parse HEAD)"; r="$(record_field reviewed)"; r="${r:-$hd}"
  [[ "$r" == "$h" ]] || extra+=$'\n\n'"checked at $r; the branch is now at $h"
}

case "$mode" in
  feature|fix) # guard.sh knows a pr.sh with pr.sh fix by the text "|fix)"
    # fix: any PR that is not the feature's (a small fix, a dependency bump, landspec's own setup) gets
    # the same gate, so no PR opens without a recorded review at any level.
    branch="$(git branch --show-current)"
    # What feature mode changes, set here once: no branch-wide review (research R9), a draft, the generated sections.
    need_review=true; need_scan=true; draft=false; nodraft=""; ready=""; extra=""
    if [[ "$mode" == feature ]]; then
      title="${2:-}"; body_file="${3:-}"
      [[ -n "$title" && -n "$body_file" && "${4:---ready}" == --ready ]] || die 'usage: pr.sh feature "type(scope): summary" <body-file> [--ready]'
      refuse_merged "$fdir" # after the squash merge, a push would bring the deleted branch back and open a second PR
      [[ "$branch" == "$(feature_branch "$fdir")" ]] \
        || die "not on the feature's branch $(feature_branch "$fdir") (on '${branch:-a detached HEAD}'); run branch.sh $(basename "$fdir")"
      need_review=false; need_scan=false; draft=true; ready=no; nodraft="do not merge this PR before pr.sh feature --ready"
      # --ready: every task done, the end check passed for this head, one scan and mutation run of the whole diff (research R15).
      if [[ -n "${4:-}" ]]; then ready=yes; need_scan=true; fi
      feature_sections
      [[ "$ready" != yes ]] || bash "$LANDSPEC_EXT_DIR/scripts/review.sh" check --feature >/dev/null
    else
      title="${2:-}"; body_file="${3:-}"
      [[ -n "$title" && -n "$body_file" ]] || die 'usage: pr.sh fix "type(scope): summary" <body-file>'
      [[ -n "$branch" ]] && ! is_protected "$branch" \
        || die "on '${branch:-a detached HEAD}': a PR comes from its own branch (git switch -c fix/<slug>), never a base branch"
    fi
    # A reviewer's copy (Claude Code puts it under .claude/worktrees) is not the author's work.
    dirty="$(git status --porcelain -- . ':(exclude).claude/worktrees' | awk 'NR <= 5 { printf "%s ", substr($0, 4) }')" # awk reads it all: head would SIGPIPE git under pipefail
    [[ -z "$dirty" ]] || die "uncommitted changes; commit the work first (or git-ignore what the tests create): $dirty"
    git fetch --quiet origin "$base" 2>/dev/null || true
    [[ -n "$(git log --oneline "$(base_ref)..HEAD" 2>/dev/null || git log --oneline -1)" ]] || die "no commits ahead of $base"

    body="$(cat "$body_file")"
    if [[ "$(landspec_level)" == full ]] && ! grep -qE '^## Evidence' <<<"$body"; then
      die "level 'full' requires an '## Evidence' section in the PR body (test output, screenshots, run links)"
    fi
    ! $need_review || grep -qE '^## Review' <<<"$body" \
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
    review=""; if $need_review; then review="$(bash "$LANDSPEC_EXT_DIR/scripts/review.sh" report)"; fi
    # Mutation testing too, when the project has a mutate command: mutants.sh records it per diff.
    if ! $need_scan; then : # the draft: scan and mutants run once on the whole feature diff (research R15)
    elif [[ -n "$(constitution_cmd mutate)" ]]; then
      mutants="$(diff_record landspec-mutants)"
      [[ -f "$mutants" ]] || die "no mutants.sh result for this diff; run bash .specify/extensions/landspec/scripts/mutants.sh after the last commit"
      if ! grep -q '^mutants unavailable' "$mutants"; then :
      elif [[ "$mode" == feature ]]; then body+=$'\n\n'"Mutation testing: unavailable (the mutate command could not run: $(constitution_cmd mutate))"
      else die "the mutate command could not run ($(constitution_cmd mutate)); install it or fix it in the constitution, then run mutants.sh again"
      fi
      evidence="$(sed -n '/^## Evidence/,/^## /p' <<<"$body")"
      if grep -q '^mutants survivors' "$mutants" && ! grep -qi surviv <<<"$evidence"; then
        die "mutants.sh found surviving mutants; say in '## Evidence' why each changes nothing, or add the test that kills it"
      fi
    else
      body+=$'\n\n'"Mutation testing: not run (no mutate command in the constitution)"
    fi
    # And the scanners on the changed files: a finding is for the body to say; one that did not run, the body names here.
    scan="$(diff_record landspec-security)"
    ! $need_scan || [[ -f "$scan" ]] \
      || die "no security-scan.sh --changed result for this diff; run bash .specify/extensions/landspec/scripts/security-scan.sh --changed after the last commit"
    gaps=""; ! $need_scan || gaps="$(awk '$2=="missing"||$2=="failed"{printf "%s%s (%s)", s, $1, $2; s=", "}' "$scan")"
    [[ -z "$gaps" ]] || body+=$'\n\n'"Scanners not run: $gaps"
    if [[ "$mode" == feature ]] && $need_scan; then # --ready: a high finding stops it; any other is listed
      high="$(awk '$2=="findings" && $3=="high" {printf "%s%s", s, $1; s=", "}' "$scan")"
      [[ -z "$high" ]] || die "$high reported a high finding on the feature diff; fix it, then run security-scan.sh --changed again"
      found="$(awk '$2=="findings" {printf "%s%s", s, $1; s=", "}' "$scan")"
      [[ -z "$found" ]] || body+=$'\n\n'"Scanner findings (not high): $found"
    fi
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
    if $need_review; then body+=$'\n\n<details><summary>Independent review</summary>\n\n'"$review"$'\n\n</details>'; fi
    body+="$extra"
    [[ "$mode" != feature ]] || refuse_merged "$fdir" # again: the feature PR may have merged during the test run
    git push --quiet -u origin "$branch"
    open_pr "$title" "$body" "$body_file"
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
  *) die "usage: pr.sh feature \"type(scope): summary\" <body-file> [--ready] | pr.sh fix \"type(scope): summary\" <body-file> | pr.sh state <pr> [--reply <thread id> [<file>]]" ;;
esac
