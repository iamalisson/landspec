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
check "when issues.sh of the per-task flow runs again, then the PLAN line still has no first->issues" '"$s" | gq -xF "$p7"'
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

# A feature built on one branch: T001 (its start logged) landed after one review, T002 (no start: timed from its first review) after a delta, a landing conflict and its
# round, T003 has not landed; two end checks. Another feature's T001 keeps its own numbers.
cat > "$ev" <<'EOF'
400 1970-01-01T00:06Z landspec/010-t001-task start task=T001
1000 1970-01-01T00:16Z - mark task=T001 phase=implemented round=0 branch=landspec/010-t001-task
1300 1970-01-01T00:21Z - review round=full verdict=ready hm=0 branch=landspec/010-t001-task
1360 1970-01-01T00:22Z - mark task=T001 phase=ready round=0 branch=landspec/010-t001-task
1600 1970-01-01T00:26Z feat/010-timed land task=T001 commit=aaa
1900 1970-01-01T00:31Z - review round=full verdict=changes-needed hm=1 branch=landspec/010-t002-task
2000 1970-01-01T00:33Z - mark task=T002 phase=changes round=1 branch=landspec/010-t002-task
2100 1970-01-01T00:35Z - review round=full verdict=ready branch=landspec/011-t001-task
2500 1970-01-01T00:41Z - review round=delta verdict=ready hm=0 branch=landspec/010-t002-task
2600 1970-01-01T00:43Z feat/010-timed conflict task=T002 files=a.txt
3000 1970-01-01T00:50Z - review round=delta verdict=ready hm=0 branch=landspec/010-t002-task
3700 1970-01-01T01:01Z feat/010-timed land task=T002 commit=bbb
3800 1970-01-01T01:03Z feat/010-timed check feature=010-timed round=1
3900 1970-01-01T01:05Z feat/010-timed check feature=010-timed round=2
4000 1970-01-01T01:06Z - mark task=T003 phase=implemented round=0 branch=landspec/010-t003-task
4100 1970-01-01T01:08Z feat/010-timed pr mode=feature url=https://github.com/acme/app/pull/7
4200 1970-01-01T01:10Z feat/011-other land task=T001 commit=ccc
EOF
out="$("$s")"
check "when a feature's tasks landed on its one branch, then each landed task gets a line with the minutes from its first event to its landing, its review rounds and whether it had a conflict round, and a task not landed gets none" \
  'grep -qxF "TASK 010/T001 first->land 20m | reviews 1 full + 0 delta | conflict no" <<<"$out" \
   && grep -qxF "TASK 010/T002 first->land 30m | reviews 1 full + 2 delta | conflict yes" <<<"$out" \
   && grep -qxF "TASK 011/T001 first->land 35m | reviews 1 full + 0 delta | conflict no" <<<"$out" \
   && [[ "$(grep -c "^TASK " <<<"$out")" == 3 ]]'
check "then the feature gets a line, after its tasks, with the minutes from its first task event to its last landing, the tasks landed and the end-check rounds" \
  '[[ "$(grep -n "^FEATURE \|^TASK 010/T002" <<<"$out" | head -2 | tail -1)" == *"FEATURE feat/010-timed first->land 55m | tasks 2 | checks 2" ]] \
   && grep -qxF "FEATURE feat/011-other first->land 35m | tasks 1 | checks 0" <<<"$out"'
check "then the feature PR's own line and the totals print as before, a task's start not timing the PR" \
  '[[ "$(head -1 <<<"$out")" == "feat/010-timed start->pr ?m | reviews 2 full + 2 delta | first ready | tests 0s x0 | H+M 1" ]] \
   && [[ "$(tail -1 <<<"$out")" == "PRS=1 MEDIAN_START_TO_PR=?m MEAN_ROUNDS=4.0 READY_FIRST=1/1" ]]'

# A feature numbered by timestamp, and one whose branch_prefix has a "/": the landing, logged on the feature
# branch, is keyed like the task's ref, by the feature's whole key.
cat > "$ev" <<'EOF'
400 1970-01-01T00:06Z landspec/20261104-153000-t001-task start task=T001
1300 1970-01-01T00:21Z - review round=full verdict=ready hm=0 branch=landspec/20261104-153000-t001-task
1600 1970-01-01T00:26Z feat/20261104-153000-search land task=T001 commit=aaa
1700 1970-01-01T00:28Z feat/20261104-153000-search check feature=20261104-153000-search round=1
2000 1970-01-01T00:33Z landspec/010-t001-task start task=T001
2300 1970-01-01T00:38Z - review round=full verdict=changes-needed hm=1 branch=landspec/010-t001-task
2600 1970-01-01T00:43Z - review round=delta verdict=ready hm=0 branch=landspec/010-t001-task
2700 1970-01-01T00:45Z team/feat/010-x conflict task=T001 files=a.txt
3200 1970-01-01T00:53Z team/feat/010-x land task=T001 commit=bbb
3300 1970-01-01T00:55Z team/feat/010-x pr mode=feature url=https://github.com/acme/app/pull/8
EOF
out="$("$s")"
check "when a feature is numbered by timestamp, then its task and feature lines use its whole key, with the ref's minutes and rounds and its end check" \
  'grep -qxF "TASK 20261104-153000/T001 first->land 20m | reviews 1 full + 0 delta | conflict no" <<<"$out" \
   && grep -qxF "FEATURE feat/20261104-153000-search first->land 20m | tasks 1 | checks 1" <<<"$out"'
check "when the branch prefix has a /, then the landing and the conflict still meet the task ref, and the feature PR line counts its reviews" \
  'grep -qxF "TASK 010/T001 first->land 20m | reviews 1 full + 1 delta | conflict yes" <<<"$out" \
   && grep -qxF "FEATURE team/feat/010-x first->land 20m | tasks 1 | checks 0" <<<"$out" \
   && grep -qxF "team/feat/010-x start->pr ?m | reviews 1 full + 1 delta | first changes-needed | tests 0s x0 | H+M 1" <<<"$out"'

exit "$FAIL"
