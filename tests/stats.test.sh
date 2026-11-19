#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
s="$SCRIPTS/stats.sh"

new_repo standard
check "when no event was logged yet, then stats refuses and says to open a PR first" \
  'one_refusal "no landspec-events yet: open a PR first" "$s"'

# Two task PRs (one with a fix round recorded from a detached copy, grouped by its branch=, and a later pr.sh run
# that found its open PR), a spec PR, and one branch with no PR.
cat > "$(git rev-parse --git-common-dir)/landspec-events" <<'EOF'
1000 1970-01-01T00:16Z feat/001-t001-a start task=T001
1600 1970-01-01T00:26Z feat/001-t001-a review round=full verdict=changes-needed hm=2 branch=feat/001-t001-a
1700 1970-01-01T00:28Z - mark task=T001 phase=changes round=1 branch=feat/001-t001-a
1900 1970-01-01T00:31Z - review round=delta verdict=ready hm=0 branch=feat/001-t001-a
1950 1970-01-01T00:32Z feat/001-t001-a tests secs=40 ok=0
2000 1970-01-01T00:33Z feat/001-t001-a tests secs=50 ok=1
2200 1970-01-01T00:36Z feat/001-t001-a pr mode=task url=https://github.com/acme/app/pull/1
3000 1970-01-01T00:50Z feat/001-t002-b start task=T002
3300 1970-01-01T00:55Z feat/001-t002-b review round=full verdict=ready branch=feat/001-t002-b
3600 1970-01-01T01:00Z feat/001-t002-b pr mode=task url=https://github.com/acme/app/pull/2
4000 1970-01-01T01:06Z feat/001-t003-c start task=T003
4100 1970-01-01T01:08Z - review round=plan verdict=ready
5000 1970-01-01T01:23Z feat/001-spec pr mode=spec url=https://github.com/acme/app/pull/3
9200 1970-01-01T02:33Z feat/001-t001-a pr mode=task url=https://github.com/acme/app/pull/1
EOF
out="$("$s")"
check "when two branches opened a task PR (one twice) and one a spec PR, then each task branch gets one row, timed to its first PR, with start->pr minutes, rounds, first verdict, test time and the high and medium findings (? when no report counted them)" \
  '[[ "$(grep -c "start->pr" <<<"$out")" == 2 ]] \
   && grep -qxF "feat/001-t001-a start->pr 20m | reviews 1 full + 1 delta | first changes-needed | tests 90s x2 | H+M 2" <<<"$out" \
   && grep -qxF "feat/001-t002-b start->pr 10m | reviews 1 full + 0 delta | first ready | tests 0s x0 | H+M ?" <<<"$out"'
check "then the totals give the PR count, the median start->pr, the mean rounds and the share ready on the first review" \
  '[[ "$(tail -1 <<<"$out")" == "PRS=2 MEDIAN_START_TO_PR=15m MEAN_ROUNDS=1.5 READY_FIRST=1/2" ]]'
check "when a plan event names no feature (2.7.0) and was logged from a detached copy, then it gets a PLAN line under ?, before the totals" \
  '[[ "$(tail -2 <<<"$out" | head -1)" == "PLAN ? rounds 1 (1 ready) | findings ? | outside 0" ]]'

# US5: four plan rounds of 007-x (one with no count line), an issues event of the per-task flow, two outside counts.
ev="$(git rev-parse --git-common-dir)/landspec-events"
cat > "$ev" <<'EOF'
10000 1970-01-01T02:46Z main review round=plan verdict=changes-needed feature=007-x h=1 m=2 l=0
10600 1970-01-01T02:56Z main review round=plan verdict=changes-needed feature=007-x h=0 m=1 l=3
11200 1970-01-01T03:06Z main review round=plan verdict=ready feature=007-x h=0 m=0 l=1
14000 1970-01-01T03:53Z - review round=plan verdict=ready feature=007-x
15400 1970-01-01T04:16Z main issues feature=007-x created=2
15500 1970-01-01T04:18Z feat/007-spec pr mode=spec url=https://github.com/acme/app/pull/4
16000 1970-01-01T04:26Z main outside feature=007-x n=1
16100 1970-01-01T04:28Z main outside feature=007-x n=2
EOF
p7="PLAN 007-x rounds 4 (2 ready) | findings 1/2/0 0/1/3 0/0/1 ? | outside 3"
out="$("$s")"
check "when a feature has plan rounds, an issues run and outside counts, then its PLAN line gives the rounds, the ready ones, each round's findings (? with no count) and the outside sum, with no first->issues" \
  '[[ "$out" == "$(printf "%s\n" "$p7" "PRS=0 MEDIAN_START_TO_PR=?m MEAN_ROUNDS=? READY_FIRST=0/0")" ]]'
echo "17200 1970-01-01T04:46Z main issues feature=007-x created=1" >> "$ev"
check "when issues.sh of the per-task flow runs again, then the PLAN line still has no first->issues" '"$s" | grep -qxF "$p7"'
echo "18000 1970-01-01T05:00Z main review round=plan verdict=ready feature=008-y h=0 m=0 l=0" >> "$ev"
check "when a second feature has a plan round, then it gets its own line, after the first" \
  'out="$("$s")"; [[ "$(grep "^PLAN " <<<"$out")" == "$(printf "%s\n" "$p7" "PLAN 008-y rounds 1 (1 ready) | findings 0/0/0 | outside 0")" ]]'
cat > "$ev" <<'EOF'
1000 1970-01-01T00:16Z feat/001-t001-a start task=T001
2200 1970-01-01T00:36Z feat/001-t001-a pr mode=task url=https://github.com/acme/app/pull/1
2300 1970-01-01T00:38Z main issues feature=001-a created=1
2400 1970-01-01T00:40Z main outside feature=001-a n=2
EOF
check "when the log has no plan events (an issues or outside event alone makes none), then no PLAN line is printed" \
  'out="$("$s")"; ! grep -q "^PLAN" <<<"$out" && [[ "$(wc -l <<<"$out")" -eq 2 ]]'

# Spec 008 T010: one line per feature PR, counting its tasks' refs (reviewed from detached copies), opened as a draft
# then marked ready; a fix PR keeps its own line; another feature's task ref, with no feature PR, makes none.
cat > "$ev" <<'EOF'
1000 1970-01-01T00:16Z - review round=full verdict=changes-needed hm=1 branch=landspec/008-t001-task
1100 1970-01-01T00:18Z - mark task=T001 phase=changes round=1 branch=landspec/008-t001-task
1200 1970-01-01T00:20Z - review round=delta verdict=ready hm=0 branch=landspec/008-t001-task
1300 1970-01-01T00:21Z - review round=full verdict=ready branch=landspec/008-t002-task
1400 1970-01-01T00:23Z - review round=full verdict=ready hm=4 branch=landspec/009-t001-task
1500 1970-01-01T00:25Z feat/008-one-pr tests secs=30 ok=1
1600 1970-01-01T00:26Z feat/008-one-pr pr mode=feature url=https://github.com/acme/app/pull/5
2000 1970-01-01T00:33Z fix/typo start task=
2300 1970-01-01T00:38Z fix/typo review round=full verdict=ready hm=0 branch=fix/typo
2600 1970-01-01T00:43Z fix/typo pr mode=fix url=https://github.com/acme/app/pull/6
3000 1970-01-01T00:50Z feat/008-one-pr pr mode=feature url=https://github.com/acme/app/pull/5
EOF
out="$("$s")"
check "when a feature PR was opened and marked ready, then it gets one line with its tasks' reviews and its tests, a fix PR its own, and no task ref a line" \
  '[[ "$out" == "$(printf "%s\n" "feat/008-one-pr start->pr ?m | reviews 2 full + 1 delta | first changes-needed | tests 30s x1 | H+M 1" \
     "fix/typo start->pr 10m | reviews 1 full + 0 delta | first ready | tests 0s x0 | H+M 0" "PRS=2 MEDIAN_START_TO_PR=10m MEAN_ROUNDS=2.0 READY_FIRST=1/2")" ]]'

exit "$FAIL"
