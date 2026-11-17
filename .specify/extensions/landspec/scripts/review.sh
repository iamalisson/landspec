#!/usr/bin/env bash
# Record and check the independent review (/speckit-landspec-review), so nothing opens without one.
#   review.sh record <report-file>          task review: tied to the branch's exact diff against the base
#   review.sh record --delta <report-file>  fix round: reviews <last reviewed>..HEAD, after any recorded round
#   review.sh record --plan <report-file>   plan review: tied to every file of the feature folder (issue numbers aside);
#                                           keeps the folder it recorded as plan-<feature>.reviewed
#   review.sh record --feature <report-file>  feature review: the whole feature's check copy against its spec,
#                                           one "- met|not met|not verifiable: <item> — <evidence>" line per item
#   review.sh state --plan [<dir>]          print the plan state (of the folder <dir>, or the feature's),
#                                           writing nothing: the reviewer puts it in its report as "Plan state: <hash>"
#   review.sh diff --plan                   print git diff --no-index of the last recorded plan against the folder
#   review.sh check [--plan]                exit 0 when a review that said "ready" matches the current state
#   check, report and record take --branch <b>: that branch, read by name from any HEAD (default: the current one)
#   review.sh report [--plan]               check, then print the recorded facts: the patch id, "Assessment: ready",
#                                           the model, any warning and the risk maps as paths
#                                           (never the report's text: pr.sh puts this in the public PR body)
#   review.sh risk [<from>]                 the diff's risky paths, one "RISK=<category> <path>" line each (RISK=none)
# The report ends with a line "Assessment: ready" or "Assessment: changes needed", and states the
# lines "Model: <id>" and, for a task, "Reviewed: <from>..<head>" (plus "Delta from: <last>" for a delta),
# or, for a plan, "Plan state: <hash>" (the state of the files it read).
# Records live in .git, so they never dirty the tree; a new commit or an edited tasks.md needs a new review.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
start="$PWD" # state --plan <dir> resolves a relative <dir> from where it was called
landspec_cd_root

action="${1:-}"; shift || true
plan=false; delta=false; bopt=""; feat=false
while [[ "${1:-}" == --plan || "${1:-}" == --delta || "${1:-}" == --branch || "${1:-}" == --feature ]]; do
  case "$1" in
    --plan) plan=true ;; --delta) delta=true ;; --feature) feat=true ;;
    --branch) bopt="${2:-}"; [[ -n "$bopt" ]] || die "usage: review.sh <action> --branch <branch> ..."; shift ;;
  esac; shift
done
if $feat && { $plan || $delta || [[ -n "$bopt" || "$action" != record ]]; }; then
  die "a feature review is recorded alone: review.sh record --feature <report-file> (no --plan, --delta or --branch)"
fi
if $plan && [[ -n "$bopt" ]]; then die "a plan review belongs to the feature, not a branch: drop --branch"; fi
if $plan && $delta; then die "a plan review is always full: review.sh record --plan <report-file>"; fi
if $plan && [[ "$action" == risk ]]; then die "risk maps a diff; a plan review has none"; fi
if [[ "$action" == state ]] && ! $plan; then die "usage: review.sh state --plan [<dir>]"; fi
if [[ "$action" == diff ]] && ! $plan; then die "usage: review.sh diff --plan"; fi
# A fix round may change this many lines outside the previous findings' files (tests aside);
# more means the fix is new work, which gets a full review.
DELTA_LINES=20
dir="$(git rev-parse --git-common-dir)/landspec-review"

if $plan; then
  # state --plan <dir>: the copies the reviewer read; no active feature needed.
  if [[ "$action" == state && -n "${1:-}" ]]; then
    fdir="$1"; [[ "$fdir" == /* ]] || fdir="$start/$fdir"
    for f in plan.md tasks.md; do [[ -f "$fdir/$f" ]] || die "no $f in $1"; done
  else fdir="$(feature_dir)"; fi
  name="plan-$(basename "$fdir")"; what="the plan ($fdir)"
  # plan_files: the folder's files, relative and sorted; editor and temp files (issues.sh writes tasks.md.tmp) left out.
  # shortcut: a name list stands in for `git ls-files`, since the reviewer hashes a copy outside any repository.
  plan_files() { (cd "$fdir" && find . -type f ! -name '.*' ! -name '*~' ! -name '*.swp' ! -name '*.tmp') | sed 's|^\./||' | LC_ALL=C sort; }
  # plan_text <file>: its content, tasks.md without the issue numbers issues.sh appends.
  plan_text() { if [[ "$1" == tasks.md ]]; then sed -E 's/ — #[0-9]+[[:space:]]*$//' "$fdir/$1"; else cat "$fdir/$1"; fi; }
  # Each file as path, NUL, byte length, newline, content: no two folders hash alike by moving bytes between files.
  state() {
    local f; plan_files | while IFS= read -r f; do
      printf '%s\0%s\n' "$f" "$(plan_text "$f" | wc -c | tr -d ' ')"; plan_text "$f"
    done | sha256
  }
  # snapshot <dest>: the files state hashes, as it hashes them, under <dest>.
  snapshot() { local f; mkdir -p "$1"; plan_files | while IFS= read -r f; do mkdir -p "$1/$(dirname "$f")"; plan_text "$f" > "$1/$f"; done; }
  # Read-only and before any write: the reviewer runs it in its own copy.
  if [[ "$action" == state ]]; then state; exit 0; fi
  if [[ "$action" == diff ]]; then
    kept="$dir/$name.reviewed"; [[ -d "$kept" ]] || die "no plan review recorded yet for $(basename "$fdir")"
    t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
    cp -R "$kept" "$t/reviewed"; snapshot "$t/current"
    rc=0; (cd "$t" && git diff --no-index -- reviewed current) || rc=$?
    ((rc <= 1)) || die "git diff --no-index failed ($rc)"; exit 0
  fi
elif [[ "$action" != risk ]] && ! $feat; then # risk reads only the diff, and a feature review no branch, so neither needs one
  branch="${bopt:-$(git branch --show-current)}"; [[ -n "$branch" ]] || die "not on a branch (detached HEAD); switch to the task's branch first"
  # --branch <b> reads <b> by name, from any HEAD: its tip, not this checkout, is what is reviewed.
  if [[ -n "$bopt" ]]; then
    git show-ref --verify --quiet "refs/heads/$bopt" || die "no branch '$bopt' in this clone"
    [[ "$bopt" != "$(git branch --show-current)" ]] || bopt=""
  fi
  name="task-${branch//\//__}"; what="this branch's diff"; [[ -z "$bopt" ]] || what="the diff of $bopt"
  state() { local id; id="$(diff_id ${bopt:+"$bopt"})" || exit 1; echo "$id"; }
fi
mkdir -p "$dir"
tip="$(branch_tip ${bopt:+"$bopt"})"
# db: diff_base of the branch this call is about.
db() { diff_base ${bopt:+"$bopt"}; }
record="$dir/${name:-}"

# hdr <key> [file]: the record's header values for <key>. The header ends at the first blank line,
# so nothing in the report below it can add or override a field.
hdr() { K="$1" awk '/^$/ { exit } index($0, ENVIRON["K"] ": ") == 1 { print substr($0, length(ENVIRON["K"]) + 3) }' "${2:-$record}"; }

# field <name>: the value of the report's last exact line "<name>: <value>" (optional bold, also "**<name>:**"), or nothing.
field() { grep -iE "^\**$1\**:\** *[^[:space:]*]+\**$" "$report" | tail -1 | sed -E 's/^[^:]*:\** *//; s/\*+$//' || true; }

# commit <sha>: the full sha of that commit, or nothing.
commit() { git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null || true; }

# risk <from>: one "RISK=<category> <path>" line per risky path of <from>..HEAD, by fixed rules on
# the paths and the added lines; only paths and categories are printed, never a line's content.
risk() {
  { landspec_diff --name-status "$1" "$tip" | awk '{ print "S\t" $0 }'; landspec_diff -U0 "$1" "$tip"; } | SKIP="$TEST_SKIP_RE" awk '
    function flag(c, p) { print "RISK=" c " " p }
    /^S\t/ {
      split($0, f, "\t"); p = f[3]; l = tolower(p)
      if (f[2] == "D") flag("delete", p)
      if (l ~ /(^|\/)(migrations?|migrate|alembic|flyway|liquibase)\// || l ~ /\.sql$/) flag("migration", p)
      if (l ~ /^\.github\/|^\.gitlab-ci\.yml$|^\.circleci\/|jenkinsfile|azure-pipelines|bitbucket-pipelines|^\.githooks\/|^\.husky\/|pre-commit-config/) flag("ci", p)
      if (l ~ /auth([^o]|$)|authori[sz]|login|permission|rbac|(^|[^a-z])acls?([^a-z]|$)|oauth|jwt|passw|crypt/) flag("auth", p)
      if (l ~ /(^|\/)\.env|secret|credential|\.pem$|\.key$|id_rsa/) flag("secrets", p)
      if (l ~ /payment|billing|invoice|checkout|pricing|refund|wallet|ledger/) flag("money", p)
      # What people see: styles and markup templates, read for contrast, focus and accessible names.
      if (l ~ /\.(css|scss|sass|less|styl|html?|vue|svelte|hbs|njk|jinja2?|j2|erb|twig|liquid)$/) flag("ui", p)
      next
    }
    # Added lines count only inside a hunk, so a "+++" line in the content is never a header.
    /^diff --git / { hunk = 0; next }
    !hunk && /^\+\+\+ b\// { path = substr($0, 7); next }
    /^@@/ { hunk = 1; next }
    hunk && /^\+/ {
      l = tolower(substr($0, 2))
      if (l ~ /rm -r|rmtree|unlink\(|drop (table|column|database)|truncate |delete from|os\.remove|fs\.rm/) flag("delete", path)
      if (l ~ /--no-verify|continue-on-error: *true|\|\| *true/ || l ~ ENVIRON["SKIP"]) flag("gate", path)
    }
  ' | sort -u | grep . || echo RISK=none
}

# checked <from>: dies unless every risky path of <from>..HEAD has a "- deep: <path>" line, or a
# "- proven: <path> by <file>:<n>" line naming an existing line of a test file at HEAD
# (never for a gate, delete or test path: those need "- deep:").
checked() {
  local l p f n o cats re pre='^- proven: ([^ ]+) by ([^ ]+):([0-9]+)( .*)?$'
  re="$(test_path_re)" || exit 1
  while IFS= read -r l; do
    if [[ "$l" =~ $pre ]]; then
      p="${BASH_REMATCH[1]}"; f="${BASH_REMATCH[2]}"; n="${BASH_REMATCH[3]}"
      if grep -qE -- "$re" <<<"$f" && git cat-file -e "$tip:$f" 2>/dev/null \
        && ((10#$n >= 1 && 10#$n <= $(git show "$tip:$f" | awk 'END { print NR }'))); then continue; fi
    else
      p="$(sed -E 's/^- proven: ([^ ]*).*/\1/' <<<"$l")"; f="<file>"; n="<n>"
    fi
    die "$p is not proven by $f:$n (not a test file, or no such line): check it deep or name the test"
  done < <(grep -E '^- proven: ' "$report" || true)
  while IFS=$'\t' read -r cats p; do
    # A disabled gate, a deletion or a test itself cannot be proven by a test (a skipped test never fails).
    o=" or '- proven: $p by <test file:line>'"
    if [[ ", $cats," == *", gate,"* || ", $cats," == *", delete,"* ]] || grep -qE -- "$re" <<<"$p"; then o=" (a gate, delete or test path needs a deep read)"; fi
    P="$p" O="$o" awk 'BEGIN { d = "- deep: " ENVIRON["P"]; q = "- proven: " ENVIRON["P"] " by " }
      (index($0, q) == 1 && ENVIRON["O"] ~ /^ or /) || (index($0, d) == 1 && (length($0) == length(d) || substr($0, length(d) + 1, 1) == " ")) { f = 1 }
      END { exit !f }' "$report" \
      || die "the report does not check $p ($cats): add '- deep: $p'$o, and run the review again"
  done < <(risk "$1" | awk '$0 != "RISK=none" { c = substr($1, 6); p = substr($0, length($1) + 2)
      if (!(p in cats)) { order[++n] = p; cats[p] = c } else cats[p] = cats[p] ", " c }
      END { for (i = 1; i <= n; i++) print cats[order[i]] "\t" order[i] }')
}

# outside <last>: the lines the fix changed since <last> outside the previous findings' files
# (the first file:line of each line from "findings" on, claims lines aside) and outside test paths; a binary file
# counts as more than the limit.
outside() {
  local found re a d f n=0
  # Claims lines and their heading are skipped: a claim's stopped-at file is not a finding's file.
  found="$(awk 'NR == 1, /^$/ { next } /^(- (held|broke):|\*\*Claims)/ { next } tolower($0) ~ /findings/ { on = 1 }
    on && match($0, /[A-Za-z0-9_.\/-]+:[0-9]+/) { s = substr($0, RSTART, RLENGTH); sub(/:[0-9]+$/, "", s); print s }' "$record")"
  re="$(test_path_re)" || exit 1
  while IFS=$'\t' read -r a d f; do
    if grep -qxF -- "$f" <<<"$found" || grep -qE -- "$re" <<<"$f"; then continue; fi
    if [[ "$a" == - ]]; then n=$((n + DELTA_LINES + 1)); else n=$((n + a + d)); fi
  done < <(landspec_numstat "$1" "$tip")
  echo "$n"
}

# remove_copy <report> <reviewed commit>: after a record, remove the reviewer's copy its last "Copy:"
# line names, only when it is surely one Claude Code made for this review: an agent-* folder directly
# under <root>/.claude/worktrees (the current or the main worktree), a listed worktree on (or detached
# from) its worktree-agent-* branch, at the reviewed commit, and not this checkout. Anything else is
# left with a line saying why; the record stands either way.
remove_copy() {
  local c p top main parent br head="" on="" wt="" line why=""
  c="$(sed -nE 's/^\**Copy\**: *//p' "$1" | tail -1 | sed 's/[[:space:]]*$//')"
  [[ -n "$c" && "$c" != none* && -d "$c" ]] || return 0
  p="$(cd "$c" && pwd -P)"; top="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
  main="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"; main="$(cd "$main" 2>/dev/null && pwd -P || true)"
  parent="$(dirname "$p")"; br="worktree-$(basename "$p")"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) wt="$(cd "${line#worktree }" 2>/dev/null && pwd -P || echo "${line#worktree }")" ;;
      "HEAD "*) if [[ "$wt" == "$p" ]]; then head="${line#HEAD }"; fi ;;
      "branch "*) if [[ "$wt" == "$p" ]]; then on="${line#branch refs/heads/}"; fi ;;
    esac
  done < <(git worktree list --porcelain)
  if [[ "$p" == "$top" ]]; then why="it is this checkout"
  elif [[ "$(basename "$p")" != agent-* || ( "$parent" != "$top/.claude/worktrees" && "$parent" != "$main/.claude/worktrees" ) ]]; then
    why="not an agent-* folder directly under .claude/worktrees"
  elif [[ -z "$head" ]]; then why="not a worktree of this repository"
  elif ! git show-ref --verify --quiet "refs/heads/$br" || [[ -n "$on" && "$on" != "$br" ]]; then why="not on its $br branch"
  elif [[ "$head" != "$2" ]]; then why="not at the reviewed commit"
  fi
  if [[ -z "$why" ]] && git worktree remove --force "$p" 2>/dev/null; then
    git branch -D "$br" >/dev/null 2>&1 || true
    echo "landspec: removed the reviewer's copy $c" >&2
  else
    echo "landspec: left the reviewer's copy $c (${why:-git refused to remove it})" >&2
  fi
}

# The feature review: one record per feature, for the check copy's merge result (refs/landspec/check/<feature>).
# Its verdict comes from its lines: any "not met" is "changes needed". Only a "ready" after a green run
# resets the whole-feature check's round counter (implement.sh check-copy).
if $feat; then
  report="${1:-}"; [[ -f "$report" ]] || die "usage: review.sh record --feature <report-file>"
  [[ -s "$report" ]] || die "the report file $report is empty: the reviewer named it but did not write it; ask it to write the report there, then record again"
  fdir="$(feature_dir)"; fname="$(basename "$fdir")"
  c="$(git rev-parse --verify --quiet "refs/landspec/check/$fname^{commit}" || true)"
  [[ -n "$c" ]] || die "no check copy for $fname: run implement.sh check-copy first"
  lre='^- (met|not met|not verifiable): '
  grep -qE "$lre" "$report" || die "the report has no '- met: …', '- not met: …' or '- not verifiable: …' line"
  verdict="$(grep -iE '^\**assessment\**: *(ready|changes needed)\**\.?$' "$report" | tail -1 | grep -oiE 'changes needed|ready' | tr '[:upper:]' '[:lower:]' || true)"
  [[ -n "$verdict" ]] || die "the report has no line that is exactly 'Assessment: ready' or 'Assessment: changes needed'"
  if grep -qE '^- not met: ' "$report"; then verdict="changes needed"; fi
  rre='^([0-9a-f]{7,40})[.][.]([0-9a-f]{7,40})$'
  [[ "$(field reviewed)" =~ $rre && "$(commit "${BASH_REMATCH[2]}")" == "$c" ]] \
    || die "the report must state Reviewed: <base>..$c (the check copy's merge result): run the feature review again"
  model="$(field model)"; [[ -n "$model" ]] || die "the report must state Model: <id>: run the feature review again"
  { echo "state: $c"; echo "assessment: $verdict"; echo "model: $model"; echo; cat "$report"; } > "$dir/feature-$fname.tmp"
  mv "$dir/feature-$fname.tmp" "$dir/feature-$fname"
  rf="$dir/feature-$fname-round"
  if [[ "$verdict" == ready && -f "$rf" ]] && grep -qx 'outcome=green' "$rf"; then rm -f "$rf"; fi
  remove_copy "$report" "$c"
  event review round=feature verdict="${verdict// /-}"
  echo "REVIEW=$verdict"; exit 0
fi
case "$action" in
  record)
    report="${1:-}"; [[ -f "$report" ]] || die "usage: review.sh record [--plan|--delta] <report-file>"
    [[ -s "$report" ]] || die "the report file $report is empty: the reviewer named it but did not write it; ask it to write the report there, then record again"
    # Only the exact line counts ("not ready" or "already" in prose never does); the last one decides.
    verdict="$(grep -iE '^\**assessment\**: *(ready|changes needed)\**\.?$' "$report" | tail -1 | grep -oiE 'changes needed|ready' | tr '[:upper:]' '[:lower:]' || true)"
    [[ -n "$verdict" ]] || die "the report has no line that is exactly 'Assessment: ready' or 'Assessment: changes needed'"
    # Untracked files (the report itself, kept outside the repo anyway) cannot be part of the diff.
    if ! $plan && [[ -z "$bopt" && -n "$(git status --porcelain --untracked-files=no)" ]]; then die "commit the work first: the review is recorded for the committed diff"; fi
    st="$(state)"
    want="$(review_model)" || exit 1
    model="$(field model)"; from=""; head=""; carried=""
    if $plan; then
      [[ -n "$model" ]] || die "the report must state Model: <id> for the plan: run the review again"
      # The state the reviewer hashed from the files it read (review.sh state --plan <its copies>).
      [[ "$(field 'plan state')" =~ ^[0-9a-f]{64}$ ]] || die "the report has no Plan state line: run the review again (this landspec version records it)"
      [[ "${BASH_REMATCH[0]}" == "$st" ]] || die "the plan changed since this review: run the review again"
    else
      head="$(git rev-parse "$tip")"; df="$(field 'delta from')"
      rf=""; rh=""; rre='^([0-9a-f]{7,40})[.][.]([0-9a-f]{7,40})$'
      if [[ "$(field reviewed)" =~ $rre ]]; then
        rf="$(commit "${BASH_REMATCH[1]}")"; rh="$(commit "${BASH_REMATCH[2]}")"
      fi
      if $delta; then
        [[ -f "$record" && -n "$(hdr round)" ]] \
          || die "a delta follows a recorded full review of this branch: run a new full review, then record it with review.sh record <report-file>"
        from="$(hdr head)"
        [[ -n "$df" ]] || die "a delta report names its base: Delta from: $from; run the delta review again"
        git merge-base --is-ancestor "$from" "$tip" 2>/dev/null || die "$from is no longer on this branch (rebased?): run a new full review"
        [[ "$head" != "$from" ]] || die "nothing was committed since the last review ($from): commit the fixes, then run the delta review"
        # The specific delta line wins over the generic one when the range is there but wrong.
        if [[ -n "$rf" && ( "$(commit "$df")" != "$from" || "$rf" != "$from" || "$rh" != "$head" ) ]]; then
          die "the delta must review $from..HEAD (Reviewed: $from..$head): run the delta review again from $from"
        fi
        [[ -n "$rf" && -n "$model" ]] \
          || die "the report must state Reviewed: <from>..<head> and Model: <id> for $from..$head: run the review again"
        n="$(outside "$from")" || exit 1
        ((n <= DELTA_LINES)) || die "the delta changes $n lines outside the previous findings (limit $DELTA_LINES): run a new full review"
        carried="$(hdr map-full)"
      else
        [[ -z "$df" ]] || die "this is a delta report: record it with --delta, or run a new full review"
        from="$(db)"
        [[ -n "$model" && "$rf" == "$from" && "$rh" == "$head" ]] \
          || die "the report must state Reviewed: <from>..<head> and Model: <id> for $from..$head: run the review again"
      fi
      checked "$from"
    fi
    # The model the review ran on: a warning, never a refusal (the session may force one model).
    warn=""; fam="$(tr '[:upper:]' '[:lower:]' <<<"$model" | grep -oE 'sonnet|opus|fable|haiku' | head -1 || true)"
    # The id reaches the PR body: anything that is not shaped like a model id stays out of it.
    mre='^[A-Za-z0-9][]A-Za-z0-9.:@_[-]{1,79}$'
    if ! [[ "$model" =~ $mre ]] || ! grep -qiE 'claude|sonnet|opus|fable|haiku' <<<"$model"; then model=unknown; fi
    if [[ -n "${CLAUDE_CODE_SUBAGENT_MODEL_FORCE:-}" ]]; then warn="CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set"
    elif [[ "$fam" != sonnet && "$fam" != opus && "$fam" != fable ]]; then warn="the review ran on $model"
    elif [[ "$fam" != "$want" ]]; then warn="the review ran on $model, not $want"
    fi
    if [[ -n "$warn" ]]; then warn="$warn; the review did not run on the configured model"; echo "landspec: warning: $warn" >&2; fi
    map="$(grep -oE '^- (deep|proven): [^ ]+' "$report" || true)"
    # A task's map reaches the PR body, so only paths of the diff are kept; a plan's never does.
    if ! $plan; then map="$(awk 'NR == FNR { p[$0]; next } $3 in p' <(landspec_diff --name-only "$(db)" "$tip") <(cat <<<"$map"))"; fi
    {
      echo "state: $st"; echo "assessment: $verdict"
      if ! $plan; then echo "head: $head"; if $delta; then echo "round: delta"; else echo "round: full"; fi; fi
      echo "model: $model"
      if [[ -n "$warn" ]]; then echo "warning: $warn"; fi
      # A delta keeps round 1's map, so the PR shows both.
      if $delta; then [[ -z "$carried" ]] || sed 's/^/map-full: /' <<<"$carried"; [[ -z "$map" ]] || sed 's/^/map-fix: /' <<<"$map"
      elif [[ -n "$map" ]]; then sed 's/^/map-full: /' <<<"$map"; fi
      echo; cat "$report"
    } > "$record.tmp" && mv "$record.tmp" "$record"
    # The text this round read (its state matched): the next round is given its diff (review.sh diff --plan).
    if $plan; then rm -rf "$record.reviewed.tmp"; snapshot "$record.reviewed.tmp"; rm -rf "$record.reviewed"; mv "$record.reviewed.tmp" "$record.reviewed"; fi
    remove_copy "$report" "${head:-$(git rev-parse "$tip")}"
    if $plan; then event review round=plan verdict="${verdict// /-}"
    else
      # hm: high + medium from the report's "Findings: <n> high, <n> medium, <n> low" line, when it has one
      hm="$(grep -iE '^findings: *[0-9]+ high, *[0-9]+ medium' "$report" | tail -1 | awk '{ gsub(/[^0-9 ]/, ""); print $1 + $2 }' || true)"
      event review round="$($delta && echo delta || echo full)" verdict="${verdict// /-}" ${hm:+hm=$hm} branch="$branch"; echo "REVIEWED=$head"
    fi
    echo "REVIEW=$verdict" ;;
  check|report)
    st="$(state)"
    [[ -f "$record" ]] || die "no independent review recorded for $what; run /speckit-landspec-review and record its report: review.sh record$($plan && echo ' --plan') <report-file>"
    [[ "$(hdr state)" == "$st" ]] \
      || die "$what changed since the last review; run /speckit-landspec-review again and record it"
    [[ "$(hdr assessment)" == ready ]] \
      || die "the last review said 'changes needed'; fix the findings, then review again and record it"
    if [[ "$action" == check ]]; then echo "REVIEW=ready"; exit 0; fi
    # Only facts checked or stored by record: no reviewer prose can be filtered for findings reliably (F3.1/F4.3).
    echo "Independent review recorded for this diff (patch id $(hdr state | cut -c1-12))"
    echo "Assessment: ready"
    m="$(hdr model)"; [[ -z "$m" ]] || echo "Model: $m"
    hdr warning | sed 's/^/warning: /'
    m="$(hdr map-full)"; [[ -z "$m" ]] || printf 'Risk map (round 1)\n%s\n' "$m"
    m="$(hdr map-fix)"; [[ -z "$m" ]] || printf 'Risk map (fix round)\n%s\n' "$m" ;;
  risk)
    from="${1:-$(db)}"; c="$(commit "$from")"; [[ -n "$c" ]] || die "usage: review.sh risk [<from>] (no commit '$from')"
    risk "$c" ;;
  *) die "usage: review.sh record [--plan|--delta|--feature] <report-file> | review.sh check|report [--plan] | review.sh state --plan [<dir>] | review.sh diff --plan | review.sh risk [<from>]" ;;
esac
