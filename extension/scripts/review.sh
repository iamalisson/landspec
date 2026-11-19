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
#   review.sh answer --plan <area> <text>   record the developer's answer to a Simplify section, resetting the
#                                           area's count (plan-<feature>.areas)
#   review.sh outside --plan <n>            log the real findings the spec PR's outside reviewers found (OUTSIDE=<n>)
#   review.sh check [--plan]                exit 0 when the recorded review matches the current state and counts
#                                           no high finding (a plan) or no high or medium one (a task)
#   check, report and record take --branch <b>: that branch, read by name from any HEAD (default: the current one)
#   review.sh report [--plan]               check, then print the recorded facts: the patch id, the Assessment line,
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
if [[ "$action" == answer ]] && ! $plan; then die "usage: review.sh answer --plan <area> <text>"; fi
if [[ "$action" == outside ]] && ! $plan; then die "usage: review.sh outside --plan <n>"; fi
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
  # plan_text <file>: its content; tasks.md without the issue numbers issues.sh writes, task ticks read as "- [ ]".
  plan_text() { if [[ "$1" == tasks.md ]]; then plain_tasks "$fdir/$1" | sed -E 's/ — #[0-9]+[[:space:]]*$//'; else cat "$fdir/$1"; fi; }
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
# The plan's area log: "<round> <area>" per finding, and "due|asked|reset <area>" (data-model "Area log").
areas="$record.areas"

# areas_state: one "<area> <findings since its last reset> <due|asked|->" line per area of the log.
areas_state() {
  [[ -f "$areas" ]] || return 0
  awk '$1 ~ /^[0-9]+$/ { if (!($2 in n)) o[++k] = $2; n[$2]++; next }
    $1 == "due" || $1 == "asked" || $1 == "reset" { if (!($2 in n)) { o[++k] = $2; n[$2] = 0 }
      s[$2] = $1; if ($1 == "reset") { n[$2] = 0; s[$2] = "-" } }
    END { for (i = 1; i <= k; i++) print o[i], n[o[i]], (o[i] in s ? s[o[i]] : "-") }' "$areas"
}

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

# The plan review's passes, in order (review.md "Plan review"): each is a "### Pass: <name>" table in the report.
PASSES="size requirements rules claims inputs guards rollout orderings"

# pass_rows: one "<pass>\t<first cell>\t<status>\t<row>" line per table row of the report's pass sections
# (the header, the row just above a |---| line, aside), and one "<pass>\t\t\t" line where each section starts.
pass_rows() {
  awk '
    function cell(s) { gsub(/^[ \t`*]+|[ \t`*]+$/, "", s); return s }
    function flush(  r, n, c) { if (row == "") return; r = row; sub(/[ \t]+$/, "", r); if (r !~ /\|$/) r = r "|"
      n = split(r, c, "|"); print sec "\t" cell(c[2]) "\t" cell(c[n - 1]) "\t" row; row = "" }
    /^#/ { flush(); sec = ""; if ($0 ~ /^### Pass: *[a-z]+ *$/) { sec = $0; sub(/^### Pass: */, "", sec); sub(/ *$/, "", sec) }
      else if ($0 ~ /^### Earlier findings *$/) sec = "earlier"
      if (sec != "") print sec "\t\t\t"; next }
    sec == "" { next }
    /^\|[ \t:|-]*$/ { row = ""; next }
    /^\|/ { flush(); row = $0 }
    END { flush() }' "$report"
}

# findings_hml <file>: "<high> <medium> <low>" of its last "Findings: <n> high, <n> medium, <n> low" line, or nothing.
findings_hml() {
  grep -iE '^\**findings\**:\** *[0-9]+ high, *[0-9]+ medium, *[0-9]+ low\**\.?$' "$1" | tail -1 | awk '{ gsub(/[^0-9]+/, " "); print $1 + 0, $2 + 0, $3 + 0 }' || true
}
# findings_total <file>: high + medium + low of that line, or nothing.
findings_total() { findings_hml "$1" | awk '{ print $1 + $2 + $3 }'; }

# pass_tables: dies, naming the pass and the row, unless every pass has a table of rows whose statuses are its
# own, the Earlier findings table is there when the last round had findings, and the findings are counted and
# tagged; for a "ready", unless every row passes (only when the report counts a high finding: a failing row of a
# report with none is a medium or low one, R13) and every defined FR/SC id of spec.md and task id of tasks.md has its row.
pass_tables() {
  local rows err id total last=0 tags bad nt nf high
  rows="$(pass_rows)"
  # A record with no Findings: line (2.7.0) counts as 0.
  if [[ -f "$record" ]]; then last="$(findings_total "$record")"; fi
  high="$(findings_hml "$report" | cut -d' ' -f1)"
  err="$(P="$PASSES" V="$verdict" H="${high:-0}" E="$((${last:-0} > 0))" awk -F'\t' '
    BEGIN { np = split(ENVIRON["P"], pass, " ")
      split("holds proven SAME TRUE provided handled safe holds", good, " ")
      split("BREAKS: MISSING DIFFERENT: FALSE MISSING MISSING BREAKS: BREAKS:", bad, " ")
      for (i = 1; i <= np; i++) { g[pass[i]] = good[i]; b[pass[i]] = bad[i]; t[pass[i]] = "the " pass[i] " pass" }
      g["earlier"] = "resolved"; b["earlier"] = "open"; t["earlier"] = "the Earlier findings table" }
    function say(m) { if (!e) print m; e = 1 }
    # failcell: a cell between the item and the status starts with a failing status (a status written early).
    function failcell(r,  c, k, n, x) { sub(/[ \t]+$/, "", r); if (r !~ /\|$/) r = r "|"; n = split(r, c, "|")
      for (k = 3; k < n - 1; k++) { x = c[k]; gsub(/^[ \t`*]+/, "", x); if (x ~ /^(DIFFERENT:|MISSING|FALSE|BREAKS:)/) return 1 }
      return 0 }
    $2 == "" && $3 == "" && $4 == "" { seen[$1] = 1
      if (!($1 in g)) say("the report has a ### Pass: " $1 " table, but " $1 " is not a pass of the plan review: name it one of " ENVIRON["P"]); next }
    { n[$1]++; s = $3; bd = b[$1]; list = g[$1] ", " bd (bd ~ /:$/ ? " <why>" : "") ($1 == "earlier" ? "" : " or none: <why>") }
    s ~ /^none: *[^ ]/ && $1 == "earlier" { say("the Earlier findings table has the row " $4 ": it holds one row per earlier finding, resolved or open, never none: <why>"); next }
    s ~ /^none: *[^ ]/ { none[$1] = $4; next }
    ENVIRON["V"] == "ready" && ENVIRON["H"] > 0 && failcell($4) { say(t[$1] " has a failing row, so the plan is not ready: " $4); next }
    s == g[$1] { next }
    bd ~ /:$/ ? index(s, bd " ") == 1 && length(s) > length(bd) + 1 : s == bd {
      nf++; if (ENVIRON["V"] == "ready" && ENVIRON["H"] > 0) say(t[$1] " has a failing row, so the plan is not ready: " $4); next }
    { say(t[$1] " has the row " $4 " whose status \"" s "\" is not one of " list) }
    END { for (i = 1; i <= np; i++) { p = pass[i]
        if (!seen[p]) say("the report has no ### Pass: " p " table: run every pass of the plan review")
        else if (!n[p]) say("the " p " pass has no row: write one row per item, or the one row none: <why>")
        else if (p in none && n[p] > 1) say("the " p " pass has the row " none[p] " beside other rows: none: <why> is a pass'"'"'s only row") }
      if (ENVIRON["E"] == 1 && !n["earlier"]) say("the last recorded round had findings, so the report needs an ### Earlier findings table: one row per earlier finding, resolved (with the line that resolves it) or open")
      print "failing=" nf + 0 }' <<<"$rows")"
  nf="$(tail -1 <<<"$err")"; nf="${nf#failing=}"; err="$(sed '$d' <<<"$err")"
  [[ -z "$err" ]] || die "$err"
  total="$(findings_total "$report")"
  [[ -n "$total" ]] || die "the report has no line 'Findings: <n> high, <n> medium, <n> low': run the review again"
  # Tags in table rows are not counted: a failing row is listed again, tagged, among the findings.
  tags="$(grep -v '^|' "$report" | grep -oE '\[area:[^]]*\]' || true)"
  bad="$(grep -vE '^\[area: *[a-z0-9-]+\]$' <<<"$tags" | grep . | head -1 || true)"
  [[ -z "$bad" ]] || die "the finding tag $bad does not name its area as one word of [a-z0-9-] (such as [area: area-log])"
  ((total >= nf)) || die "the report has $nf failing rows but counts $total findings: each failing row (and each open earlier finding) is also a finding, listed and tagged [area: <name>]"
  nt="$(grep -c . <<<"$tags" || true)"
  ((nt == total)) || die "the report counts $total findings on its Findings: line but tags $nt with [area: <name>]: start each finding's scenario with its [area: <name>]"
  [[ "$verdict" == ready ]] || return 0
  { [[ -f "$fdir/spec.md" ]] && grep -qE '^- \*\*FR-[0-9]+\*\*' "$fdir/spec.md"; } || die "spec.md has no functional requirement: the requirements pass cannot pass"
  for id in $(sed -nE 's/^- \*\*((FR|SC)-[0-9]+)\*\*.*/\1/p' "$fdir/spec.md"); do
    grep -qF "requirements"$'\t'"$id"$'\t' <<<"$rows" || die "the requirements pass has no row for $id (spec.md defines it): add its row"
  done
  for id in $(sed -nE 's/^- \[[ xX]\] (T[0-9]+).*/\1/p' "$fdir/tasks.md"); do
    grep -qF "size"$'\t'"$id"$'\t' <<<"$rows" || die "the size pass has no row for $id (tasks.md lists it): add its row"
  done
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
      pass_tables
      # An open Simplify question: a due area needs its section in this report, an asked one the answer first.
      opn="$(areas_state)"; due="$(awk '$3 == "due" { print $1 }' <<<"$opn")"
      for a in $(awk '$3 == "asked" { print $1 }' <<<"$opn"); do
        die "a Simplify question is open for $a: record the developer's answer first: review.sh answer --plan $a '<text>'"
      done
      for a in $due; do
        grep -qE "^## Simplify: ${a}[[:space:]]*\$" "$report" \
          || die "the report has no ## Simplify: $a section: the round is given simplify: $(paste -sd, - <<<"$due" | sed 's/,/, /g') and opens with one section per area; run the plan review again"
      done
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
    } > "$record.tmp" || die "cannot write the review record"
    # The text this round read (its state matched): the next round is given its diff (review.sh diff --plan).
    if $plan; then rm -rf "$record.reviewed.tmp"; snapshot "$record.reviewed.tmp"; rm -rf "$record.reviewed"; mv "$record.reviewed.tmp" "$record.reviewed"
      # Every finding is logged (table rows aside: a failing row is listed again among the findings).
      # shortcut: the round number is the log's last one plus 1, so a round with no finding takes none; nothing reads it yet.
      n="$(awk '$1 ~ /^[0-9]+$/ && $1 + 0 > m { m = $1 + 0 } END { print m + 1 }' "$areas" 2>/dev/null || echo 1)"
      { for a in $due; do echo "asked $a"; done
        grep -v '^|' "$report" | grep -oE '\[area: *[a-z0-9-]+\]' | sed -E "s/^\[area: *([a-z0-9-]+)\]$/$n \1/" || true; } >> "$areas"
      simplify="$(areas_state | awk '$2 >= 3 && $3 == "-" { print $1 }')"
      for a in $simplify; do echo "due $a" >> "$areas"; done
    fi
    # The record goes last: a run stopped before it leaves the old record, so the same report is recorded again.
    mv "$record.tmp" "$record"
    remove_copy "$report" "${head:-$(git rev-parse "$tip")}"
    if $plan; then
      # h, m, l from the report's last Findings: line, left out when it has none
      hml="$(grep -iE '^\**findings\**:\** *[0-9]+ high, *[0-9]+ medium, *[0-9]+ low\**\.?$' "$report" | tail -1 | awk '{ gsub(/[^0-9]+/, " "); print "h=" $1, "m=" $2, "l=" $3 }' || true)"
      # shellcheck disable=SC2086 # hml is three key=value words, or nothing
      event review round=plan verdict="${verdict// /-}" feature="$(basename "$fdir")" $hml
    else
      # hm: high + medium from the report's "Findings: <n> high, <n> medium, <n> low" line, when it has one
      hm="$(grep -iE '^findings: *[0-9]+ high, *[0-9]+ medium' "$report" | tail -1 | awk '{ gsub(/[^0-9 ]/, ""); print $1 + $2 }' || true)"
      event review round="$($delta && echo delta || echo full)" verdict="${verdict// /-}" ${hm:+hm=$hm} branch="$branch"; echo "REVIEWED=$head"
    fi
    echo "REVIEW=$verdict"
    for a in ${simplify:-}; do echo "SIMPLIFY=$a"; done ;;
  answer)
    a="${1:-}"; text="${*:2}" # an unquoted answer is still the whole answer
    [[ "$a" =~ ^[a-z0-9-]+$ && -n "${text//[[:space:]]/}" ]] || die "usage: review.sh answer --plan <area> <text>"
    [[ "$(areas_state | awk -v a="$a" '$1 == a { print $3 }')" == asked ]] \
      || die "nothing is asked for $a: an area is answered once the report with its ## Simplify: $a section is recorded"
    echo "reset $a $(tr '\n' ' ' <<<"$text" | sed 's/ *$//')" >> "$areas"
    echo "ANSWERED=$a" ;;
  outside)
    n="${1:-}"; [[ "$n" =~ ^[0-9]+$ && $# -eq 1 ]] || die "usage: review.sh outside --plan <n>, <n> the whole number of real findings the outside reviewers found"
    event outside feature="$(basename "$fdir")" n="$n"; echo "OUTSIDE=$n" ;;
  check|report)
    st="$(state)"
    [[ -f "$record" ]] || die "no independent review recorded for $what; run /speckit-landspec-review and record its report: review.sh record$($plan && echo ' --plan') <report-file>"
    [[ "$(hdr state)" == "$st" ]] \
      || die "$what changed since the last review; run /speckit-landspec-review again and record it"
    # The gate is the recorded Findings: count (R13); a record without one (before 2.9) keeps its Assessment line.
    hml="$(findings_hml "$record")"
    if [[ -z "$hml" ]]; then
      [[ "$(hdr assessment)" == ready ]] || die "the last review said 'changes needed'; fix the findings, then review again and record it"
    else
      read -r h m _ <<<"$hml"
      if $plan; then ((h == 0)) || die "the last plan review has $h high finding(s); fix them, then review the plan again and record it"
      else ((h + m == 0)) || die "the last review has $h high and $m medium findings; fix them, then review again and record it"; fi
    fi
    # No issue or spec PR while a Simplify question is open (data-model "Invariant").
    if $plan; then
      while read -r a _ s; do
        if [[ "$s" == due ]]; then die "a Simplify question is open for $a: run the next plan review with simplify: $a"; fi
        if [[ "$s" == asked ]]; then die "a Simplify question is open for $a: record the developer's answer: review.sh answer --plan $a '<text>'"; fi
      done < <(areas_state)
    fi
    if [[ "$action" == check ]]; then echo "REVIEW=ready"; exit 0; fi
    # Only facts checked or stored by record: no reviewer prose can be filtered for findings reliably (F3.1/F4.3).
    echo "Independent review recorded for this diff (patch id $(hdr state | cut -c1-12))"
    echo "Assessment: $(hdr assessment)"
    m="$(hdr model)"; [[ -z "$m" ]] || echo "Model: $m"
    hdr warning | sed 's/^/warning: /'
    m="$(hdr map-full)"; [[ -z "$m" ]] || printf 'Risk map (round 1)\n%s\n' "$m"
    m="$(hdr map-fix)"; [[ -z "$m" ]] || printf 'Risk map (fix round)\n%s\n' "$m" ;;
  risk)
    from="${1:-$(db)}"; c="$(commit "$from")"; [[ -n "$c" ]] || die "usage: review.sh risk [<from>] (no commit '$from')"
    risk "$c" ;;
  *) die "usage: review.sh record [--plan|--delta|--feature] <report-file> | review.sh check|report [--plan] | review.sh state --plan [<dir>] | review.sh diff --plan | review.sh answer --plan <area> <text> | review.sh outside --plan <n> | review.sh risk [<from>]" ;;
esac
