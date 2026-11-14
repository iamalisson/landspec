#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
scan="$SCRIPTS/security-scan.sh"

# Fake scanners: each logs its arguments; FAKE_FIND=<tool> makes that tool report findings.
mkdir -p "$TMP/tools"
for t in gitleaks osv-scanner semgrep zizmor; do
  cat > "$TMP/tools/$t" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/$t.log"
[[ " \${FAKE_FIND:-} " == *" $t "* ]] && exit 1
[[ " \${FAKE_CRASH:-} " == *" $t "* ]] && { echo "$t-core exited with -11!" >&2; exit 2; }
exit 0
EOF
  chmod +x "$TMP/tools/$t"
done
no_scanners

new_repo standard
mkdir -p .github/workflows; echo "on: push" > .github/workflows/ci.yml
git add -A; git commit --quiet -m wf

out="$(PATH="$TMP/none" bash "$scan")"
check "when no scanner is installed, then each is reported missing with how to install it" \
  'grep -q "^gitleaks *missing *install:" <<<"$out" && grep -q "^semgrep *missing" <<<"$out" && grep -q "^zizmor *missing" <<<"$out"'
check "then the report directory lives inside .git, never in the working tree" \
  'dir="$(sed -n "s/^REPORT_DIR=//p" <<<"$out")"; [[ "$dir" == .git/landspec-security/* || "$dir" == */.git/landspec-security/* ]] && [[ -z "$(git status --porcelain)" ]]'

out="$(PATH="$TMP/tools:$PATH" bash "$scan")"
check "when the scanners are installed and clean, then each reports ok" \
  'grep -q "^gitleaks *ok" <<<"$out" && grep -q "^osv-scanner *ok" <<<"$out" && grep -q "^semgrep *ok" <<<"$out" && grep -q "^zizmor *ok" <<<"$out"'
check "then semgrep runs the default and OWASP rule sets without telemetry" 'grep -q -- "--config p/default --config p/owasp-top-ten" "$TMP/semgrep.log" && grep -q -- "--metrics off" "$TMP/semgrep.log"'
check "then trivy is skipped when there is no infrastructure code" 'grep -q "^trivy *skipped" <<<"$out"'

out="$(FAKE_FIND="semgrep gitleaks" PATH="$TMP/tools:$PATH" bash "$scan")"
check "when a scanner finds something, then it reports findings with the report path" \
  'grep -q "^semgrep *findings .*semgrep.json" <<<"$out" && grep -q "^gitleaks *findings" <<<"$out"'

out="$(FAKE_CRASH=semgrep PATH="$TMP/tools:$PATH" bash "$scan")"
check "when semgrep exits with an error (not findings), then it is reported failed, never findings" \
  'grep -q "^semgrep *failed *exit 2 .*code patterns not scanned" <<<"$out" && ! grep -q "^semgrep *findings" <<<"$out"'
check "then its stderr is kept in semgrep.log, which the failed line names" \
  'dir="$(sed -n "s/^REPORT_DIR=//p" <<<"$out")"; grep -qxF "semgrep-core exited with -11!" "$dir/semgrep.log" && grep -qF "see $dir/semgrep.log" <<<"$out"'

# Every worktree shares .git/landspec-security: two runs in the same second get their own folder.
mkdir -p "$TMP/clock"; printf '#!/usr/bin/env bash\necho 20260101-000000\n' > "$TMP/clock/date"; chmod +x "$TMP/clock/date"
one="$(PATH="$TMP/clock:$TMP/none" bash "$scan" | sed -n 's/^REPORT_DIR=//p')"
two="$(PATH="$TMP/clock:$TMP/none" bash "$scan" | sed -n 's/^REPORT_DIR=//p')"
check "when two scans start in the same second, then each gets its own report folder" \
  '[[ -n "$one" && "$one" != "$two" && -s "$one/summary.txt" && -s "$two/summary.txt" ]]'

# Every worktree shares .git/landspec-security: two runs in the same second get their own folder.
mkdir -p "$TMP/clock"; printf '#!/usr/bin/env bash\necho 20260101-000000\n' > "$TMP/clock/date"; chmod +x "$TMP/clock/date"
one="$(PATH="$TMP/clock:$TMP/none" bash "$scan" | sed -n 's/^REPORT_DIR=//p')"
two="$(PATH="$TMP/clock:$TMP/none" bash "$scan" | sed -n 's/^REPORT_DIR=//p')"
check "when two scans start in the same second, then each gets its own report folder" \
  '[[ -n "$one" && "$one" != "$two" && -s "$one/summary.txt" && -s "$two/summary.txt" ]]'

git switch --quiet -c feat/x; echo "x = 1" > app.py; git add app.py; git commit --quiet -m app
: > "$TMP/semgrep.log"
PATH="$TMP/tools:$PATH" bash "$scan" --changed >/dev/null
check "when --changed, then semgrep only scans the files this branch changed" 'grep -q " app.py$" "$TMP/semgrep.log" && ! grep -q " \.$" "$TMP/semgrep.log"'
# Spec 004 T003: a branch stacked on feat/x (branch.sh --from sets the parent) scans only its own files.
git switch --quiet -c feat/y; git config branch.feat/y.landspec-parent feat/x
echo "y = 1" > other.py; git add other.py; git commit --quiet -m other
: > "$TMP/semgrep.log"
PATH="$TMP/tools:$PATH" bash "$scan" --changed >/dev/null
check "when --changed on a stacked branch, then semgrep scans only its own files, not its parent's" \
  'grep -q " other.py$" "$TMP/semgrep.log" && ! grep -q "app.py" "$TMP/semgrep.log"'
git switch --quiet feat/x

out="$(PATH="$TMP/none" bash "$scan" --changed)"
check "when --changed, then its summary lines are recorded for this diff (what pr.sh task requires)" \
  'rec="$(source "$SCRIPTS/lib.sh" && diff_record landspec-security)"; [[ "$(cat "$rec")" == "$(grep -v "^REPORT_DIR=" <<<"$out")" ]] && grep -q "^gitleaks *missing" "$rec"'
git switch --quiet -c feat/empty origin/develop
PATH="$TMP/none" bash "$scan" --changed >/dev/null
check "when --changed finds no changed file, then that result is recorded for the empty diff too" \
  '[[ "$(cat .git/landspec-security/empty)" == "all skipped no changed files" ]]'

git switch --quiet feat/x; shallow_repo
check "on a --depth 1 clone with no merge base, then --changed prints one refusal naming git fetch --unshallow and writes no record" \
  'one_refusal "git fetch --unshallow" env PATH="$TMP/none" bash "$scan" --changed && [[ -z "$(find .git/landspec-security -maxdepth 1 -type f 2>/dev/null)" ]]'

exit "$FAIL"
