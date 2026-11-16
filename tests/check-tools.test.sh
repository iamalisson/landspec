#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# bin/check-tools.sh: the pinned tool versions against each tool's newest release out for three
# weeks (fake gh, whose release lists are filtered by check-tools' own --jq through real jq).
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
# shellcheck source=../extension/scripts/pins.sh
source "$ROOT/extension/scripts/pins.sh"
fake_gh
run() { : > "$GH_LOG"; out="$(GH_API="$1" "$ROOT/bin/check-tools.sh" 2>&1)"; }
creates() { grep -c "^issue create" "$GH_LOG" || true; }
# rel <tag> <days old> [prerelease]: one release as GitHub lists it, published <days> before now
# (relative to the run, so the tests do not rot); "draft" gives a draft's null date.
rel() {
  jq -nc --arg t "$1" --arg d "$2" --argjson p "${3:-false}" \
    '{tag_name: $t, prerelease: $p, published_at: (if $d == "draft" then null else now - ($d | tonumber) * 86400 | todate end)}'
}
# api <release>...: the same release list (newest first, as GitHub orders it) for every tool.
api() {
  local l; l="[$(IFS=,; echo "$*")]"
  jq -nc --argjson l "$l" '{"gitleaks/gitleaks": $l, "google/osv-scanner": $l, "semgrep/semgrep": $l, "aquasecurity/trivy": $l}'
}

newer="$(api "$(rel v99.0.0 30)")"
equal="$(jq -nc --argjson g "[$(rel "v$GITLEAKS_VERSION" 30)]" --argjson o "[$(rel "v$OSV_VERSION" 30)]" \
  --argjson s "[$(rel "v$SEMGREP_VERSION" 30)]" --argjson t "[$(rel "v$TRIVY_VERSION" 30)]" \
  '{"gitleaks/gitleaks": $g, "google/osv-scanner": $o, "semgrep/semgrep": $s, "aquasecurity/trivy": $t}')"

check "when every tool's newest release out for three weeks is newer than its pin, then check-tools prints BEHIND=4 and opens one Tool pins behind issue" \
  'run "$newer"; grep -qx "BEHIND=4" <<<"$out" && [[ "$(creates)" == 1 ]] && grep -q "^issue create .*--title Tool pins behind" "$GH_LOG"'
check "then the issue names SEMGREP_DIGEST beside SEMGREP_VERSION (they move together)" \
  'run "$newer"; grep -q "SEMGREP_VERSION.*SEMGREP_DIGEST" "$GH_LOG"'
check "then the issue body says newest release out for three weeks" \
  'run "$newer"; grep -qF "newest release out for three weeks [v99.0.0]" "$GH_LOG"'
check "when every such release equals its pin, then it prints BEHIND=0 and opens no issue" \
  'run "$equal"; grep -qx "BEHIND=0" <<<"$out" && [[ "$(creates)" == 0 ]]'
check "when the only newer release is 10 days old, then it prints BEHIND=0 and creates no issue" \
  'run "$(api "$(rel v99.0.0 10)" "$(rel "v$TRIVY_VERSION" 40)")"; grep -qx "BEHIND=0" <<<"$out" && [[ "$(creates)" == 0 ]]'
check "when a newer release is 30 days old and a newer one 5 days old, then it reports the 30-day one and opens one issue naming it" \
  'run "$(api "$(rel v100.0.0 5)" "$(rel v99.0.0 30)")"
   grep -qxF "behind: trivy $TRIVY_VERSION, latest v99.0.0" <<<"$out" && grep -qx "BEHIND=4" <<<"$out" && [[ "$(creates)" == 1 ]] \
     && grep -qF "three weeks [v99.0.0](https://github.com/aquasecurity/trivy/releases/tag/v99.0.0)" "$GH_LOG" && ! grep -q "v100.0.0" "$GH_LOG"'
check "when a release is 20 days old, then it does not count; when 22 days old, then it does (both sides of 21 days)" \
  'run "$(api "$(rel v99.0.0 20)")"; grep -qx "BEHIND=0" <<<"$out" && run "$(api "$(rel v99.0.0 22)")" && grep -qx "BEHIND=4" <<<"$out"'
check "when the newest old-enough release is a prerelease, then it is skipped for the next one" \
  'run "$(api "$(rel v100.0.0 30 true)" "$(rel v99.0.0 40)")"
   grep -qxF "behind: trivy $TRIVY_VERSION, latest v99.0.0" <<<"$out" && ! grep -q "v100.0.0" <<<"$out"'
check "when every release is younger than 21 days (an empty result, gh exit 0), then it prints BEHIND=0, does not fail, and opens no issue" \
  'run "$(api "$(rel v99.0.0 5)" "$(rel v98.0.0 10)")" && grep -qx "BEHIND=0" <<<"$out" && [[ "$(creates)" == 0 ]]'
check "when the list holds a draft with a null published_at beside a settled release, then the draft is skipped and no error occurs" \
  'run "$(api "$(rel v100.0.0 draft)" "$(rel v99.0.0 30)")" && grep -qxF "behind: trivy $TRIVY_VERSION, latest v99.0.0" <<<"$out" && grep -qx "BEHIND=4" <<<"$out"'
printf '%s\n' "7 Tool pins behind" > "$GH_CLOSED" # the fake's open issues
check "when a Tool pins behind issue is already open, then it prints BEHIND=4 and opens no second one" \
  'run "$newer"; grep -qx "BEHIND=4" <<<"$out" && [[ "$(creates)" == 0 ]]'
rm -f "$GH_CLOSED"
check "when a release lookup fails, then it exits non-zero, names the tool and its repo, and prints no BEHIND=" \
  'run "$(jq -c "del(.\"aquasecurity/trivy\")" <<<"$newer")" && exit 1; grep -qF "cannot read the latest trivy release from aquasecurity/trivy" <<<"$out" && ! grep -q "^BEHIND=" <<<"$out" && [[ "$(creates)" == 0 ]]'

exit "$FAIL"
