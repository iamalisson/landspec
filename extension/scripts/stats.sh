#!/usr/bin/env bash
# Per-PR numbers from the local event log (.git/landspec-events, written by lib.sh event()).
#   stats.sh
# Prints one line per branch that opened a task or fix PR (timed to its first pr event; spec PRs are left out):
#   <branch> start->pr <m>m | reviews <f> full + <d> delta | first <verdict> | tests <s>s x<n> | H+M <n>
# H+M: high and medium findings over the branch's reviews, "?" when no report carried the count line.
# then one line per feature with plan events (2.7.0's, which name no feature, under "?"):
#   PLAN <feature> rounds <n> (<r> ready) | findings <h>/<m>/<l> ... | first->issues <m>m | outside <n>
# findings: one per plan round, "?" when its report had no count line; first->issues: from the first plan round to
# the first issues event ("?" when none); outside: the real findings the spec PR's outside reviewers found.
# then: PRS=<n> MEDIAN_START_TO_PR=<m>m MEAN_ROUNDS=<x> READY_FIRST=<k>/<n>
# Nothing leaves .git: the log is never pushed and never reaches a PR body.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

landspec_cd_root
log="$(git rev-parse --git-common-dir)/landspec-events"
[[ -f "$log" ]] || die "no landspec-events yet: open a PR first"

# shortcut: events are grouped by branch name, so a reused name merges its PRs; split on start lines if reuse is common
awk '
  {
    br = $3; delete f
    for (i = 5; i <= NF; i++) { k = $i; sub(/=.*/, "", k); v = $i; sub(/^[^=]*=/, "", v); f[k] = v }
    if (f["branch"] != "") br = f["branch"]
    ft = (f["feature"] != "") ? f["feature"] : "?"
  }
  # Plan events belong to a feature, not a branch, so they are read before the detached ones are skipped.
  $4 == "review" && f["round"] == "plan" {
    if (!(ft in pn)) { pf[++np] = ft; p0[ft] = $1 }
    pn[ft]++; if (f["verdict"] == "ready") pr[ft]++
    pc[ft] = pc[ft] " " ((f["h"] != "") ? f["h"] "/" f["m"] "/" f["l"] : "?")
  }
  $4 == "issues" && !(ft in it) { it[ft] = $1 }
  $4 == "outside" { po[ft] += f["n"] }
  br == "-" { next }
  $4 == "start" && !(br in st) { st[br] = $1 }
  $4 == "review" && (f["round"] == "full" || f["round"] == "delta") {
    rounds[br, f["round"]]++
    if (!(br in first)) first[br] = f["verdict"]
    if (f["hm"] != "") { hm[br] += f["hm"]; hk[br] = 1 }
  }
  $4 == "tests" { secs[br] += f["secs"]; runs[br]++ }
  $4 == "pr" && f["mode"] != "spec" && !(br in prt) { order[++n] = br; prt[br] = $1 }
  END {
    m = 0; rsum = 0; ready = 0
    for (i = 1; i <= n; i++) {
      b = order[i]; full = rounds[b, "full"] + 0; dl = rounds[b, "delta"] + 0
      mins = "?"; if (b in st) { mins = int((prt[b] - st[b]) / 60); d[++m] = mins }
      v = (b in first) ? first[b] : "-"
      rsum += full + dl; if (v == "ready") ready++
      printf "%s start->pr %sm | reviews %d full + %d delta | first %s | tests %ds x%d | H+M %s\n", b, mins, full, dl, v, secs[b], runs[b], (b in hk) ? hm[b] : "?"
    }
    for (i = 1; i <= np; i++) {
      p = pf[i]
      printf "PLAN %s rounds %d (%d ready) | findings%s | first->issues %s | outside %d\n", p, pn[p], pr[p], pc[p], (p in it) ? int((it[p] - p0[p]) / 60) "m" : "?", po[p]
    }
    for (i = 2; i <= m; i++) { x = d[i]; for (j = i - 1; j >= 1 && d[j] > x; j--) d[j + 1] = d[j]; d[j + 1] = x }
    med = "?"; if (m) med = (m % 2) ? d[(m + 1) / 2] : int((d[m / 2] + d[m / 2 + 1]) / 2)
    printf "PRS=%d MEDIAN_START_TO_PR=%sm MEAN_ROUNDS=%s READY_FIRST=%d/%d\n", n, med, n ? sprintf("%.1f", rsum / n) : "?", ready, n
  }
' "$log"
