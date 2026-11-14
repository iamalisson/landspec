#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
s="$SCRIPTS/stats.sh"

new_repo standard
check "when no event was logged yet, then stats refuses and says to open a PR first" \
  'one_refusal "no landspec-events yet: open a PR first" "$s"'

# Two task PRs (one with a fix round recorded from a detached copy, grouped by its branch=), one branch with no PR.
cat > "$(git rev-parse --git-common-dir)/landspec-events" <<'EOF'
1000 1970-01-01T00:16Z feat/001-t001-a start task=T001
1600 1970-01-01T00:26Z feat/001-t001-a review round=full verdict=changes-needed branch=feat/001-t001-a
1700 1970-01-01T00:28Z - mark task=T001 phase=changes round=1 branch=feat/001-t001-a
1900 1970-01-01T00:31Z - review round=delta verdict=ready branch=feat/001-t001-a
1950 1970-01-01T00:32Z feat/001-t001-a tests secs=40 ok=0
2000 1970-01-01T00:33Z feat/001-t001-a tests secs=50 ok=1
2200 1970-01-01T00:36Z feat/001-t001-a pr mode=task url=https://github.com/acme/app/pull/1
3000 1970-01-01T00:50Z feat/001-t002-b start task=T002
3300 1970-01-01T00:55Z feat/001-t002-b review round=full verdict=ready branch=feat/001-t002-b
3600 1970-01-01T01:00Z feat/001-t002-b pr mode=task url=https://github.com/acme/app/pull/2
4000 1970-01-01T01:06Z feat/001-t003-c start task=T003
4100 1970-01-01T01:08Z - review round=plan verdict=ready
EOF
out="$("$s")"
check "when two branches opened a PR, then each gets one row with start->pr minutes, rounds, first verdict and test time" \
  '[[ "$(grep -c "start->pr" <<<"$out")" == 2 ]] \
   && grep -qxF "feat/001-t001-a start->pr 20m | reviews 1 full + 1 delta | first changes-needed | tests 90s x2" <<<"$out" \
   && grep -qxF "feat/001-t002-b start->pr 10m | reviews 1 full + 0 delta | first ready | tests 0s x0" <<<"$out"'
check "then the totals give the PR count, the median start->pr, the mean rounds and the share ready on the first review" \
  '[[ "$(tail -1 <<<"$out")" == "PRS=2 MEDIAN_START_TO_PR=15m MEAN_ROUNDS=1.5 READY_FIRST=1/2" ]]'

exit "$FAIL"
