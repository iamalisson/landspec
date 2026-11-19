#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
scan="$SCRIPTS/security-scan.sh"

# Fake scanners: each logs its arguments; FAKE_FIND=<tool> makes that tool report findings.
mkdir -p "$TMP/tools"
# With findings, the tool writes \$FAKE_OUT as its report (to --output/--report-path, and stdout for zizmor).
for t in gitleaks osv-scanner semgrep zizmor trivy; do
  cat > "$TMP/tools/$t" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/$t.log"
if [[ " \${FAKE_FIND:-} " == *" $t "* ]]; then
  printf '%s' "\${FAKE_OUT:-}"
  while (( \$# )); do [[ \$1 == --output || \$1 == --report-path ]] && printf '%s' "\${FAKE_OUT:-}" > "\$2"; shift; done
  exit 1
fi
[[ " \${FAKE_CRASH:-} " == *" $t "* ]] && { echo "$t-core exited with -11!" >&2; exit 2; }
# FAKE_SILENT=<tool>: exits 2 with nothing on stderr, writing \$FAKE_JSON (may be empty) to --output.
if [[ " \${FAKE_SILENT:-} " == *" $t "* ]]; then
  while (( \$# )); do [[ \$1 == --output ]] && printf '%s' "\${FAKE_JSON:-}" > "\$2"; shift; done
  exit 2
fi
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

# Spec 008 T021: a high or critical finding, read from the tool's own severity field, is marked high.
line() { FAKE_FIND="$1" FAKE_OUT="$2" PATH="$TMP/tools:$PATH" bash "$scan" | grep "^$1 "; }
out="$(line gitleaks '[]')"
check "when gitleaks finds anything, then its line is findings high" 'grep -qE "^gitleaks +findings +high .*gitleaks.json$" <<<"$out"'
out="$(line semgrep '{"results":[{"check_id":"r","extra":{"severity":"ERROR","message":"m"}}],"errors":[]}')"
check "when semgrep reports an ERROR-severity result, then its line is findings high" 'grep -qE "^semgrep +findings +high .*semgrep.json$" <<<"$out"'
out="$(line semgrep '{"results":[{"check_id":"r","extra":{"severity":"INFO","message":"m"}}],"errors":[]}')"
check "when semgrep reports only INFO results, then its line is findings without high" 'grep -qE "^semgrep +findings +[^h ].*semgrep.json$" <<<"$out"'
out="$(line osv-scanner '{"results":[{"packages":[{"groups":[{"ids":["GHSA-a"],"max_severity":"9.8"}]}]}]}')"
check "when osv-scanner reports a group with max_severity 9.8, then its line is findings high" 'grep -qE "^osv-scanner +findings +high .*osv.json$" <<<"$out"'
out="$(line osv-scanner '{"results":[{"packages":[{"groups":[{"max_severity":""}],"vulnerabilities":[{"id":"GHSA-a","database_specific":{"severity":"CRITICAL"}}]}]}]}')"
check "when osv-scanner reports an advisory labelled CRITICAL with no score, then its line is findings high" 'grep -qE "^osv-scanner +findings +high " <<<"$out"'
out="$(line osv-scanner '{"results":[{"packages":[{"groups":[{"max_severity":"5.3"}],"vulnerabilities":[{"database_specific":{"severity":"MODERATE"}}]}]}]}')"
check "when osv-scanner reports only a 5.3 MODERATE vulnerability, then its line is findings without high" 'grep -qE "^osv-scanner +findings +[^h ].*osv.json$" <<<"$out"'
out="$(line zizmor '[{"ident":"template-injection","determinations":{"confidence":"Low","severity":"High","persona":"regular"}}]')"
check "when zizmor reports a High-severity finding, then its line is findings high" 'grep -qE "^zizmor +findings +high .*zizmor.json$" <<<"$out"'
out="$(line zizmor '[{"ident":"artipacked","determinations":{"confidence":"High","severity":"Low","persona":"regular"}}]')"
check "when zizmor reports a Low-severity finding with High confidence, then its line is findings without high" 'grep -qE "^zizmor +findings +[^h ].*zizmor.json$" <<<"$out"'
echo "FROM scratch" > Dockerfile
out="$(line trivy '{"Results":[{"Misconfigurations":[{"ID":"DS002","Severity":"HIGH"}]}]}')"
check "when trivy reports a HIGH misconfiguration, then its line is findings high" 'grep -qE "^trivy +findings +high .*trivy.json$" <<<"$out"'
out="$(line trivy '{"Results":[{"Misconfigurations":[{"ID":"DS026","Severity":"LOW"}]}]}')"
check "when trivy reports only a LOW misconfiguration, then its line is findings without high" 'grep -qE "^trivy +findings +[^h ].*trivy.json$" <<<"$out"'
rm Dockerfile
mkdir -p "$TMP/only"; cp "$TMP/tools/semgrep" "$TMP/only/"
out="$(FAKE_FIND=semgrep FAKE_OUT='{"results":[{"extra":{"severity":"ERROR"}}]}' PATH="$TMP/only:$TMP/none" bash "$scan")"
check "when one scanner has a high finding, then a scanner not installed stays missing" \
  'grep -q "^semgrep *findings *high" <<<"$out" && grep -q "^gitleaks *missing *install:" <<<"$out" && grep -q "^zizmor *missing" <<<"$out"'

out="$(FAKE_CRASH=semgrep PATH="$TMP/tools:$PATH" bash "$scan")"
check "when semgrep exits with an error (not findings), then it is reported failed, never findings" \
  'grep -q "^semgrep *failed *exit 2 .*code patterns not scanned" <<<"$out" && ! grep -q "^semgrep *findings" <<<"$out"'
check "then its stderr is kept in semgrep.log, which the failed line names" \
  'dir="$(sed -n "s/^REPORT_DIR=//p" <<<"$out")"; grep -qxF "semgrep-core exited with -11!" "$dir/semgrep.log" && grep -qF "see $dir/semgrep.log" <<<"$out"'

# Spec 007 T007 (#217): semgrep with --json --output writes its error to the JSON, not the log.
semgrep_line() { FAKE_SILENT=semgrep FAKE_JSON="$1" PATH="$TMP/tools:$PATH" bash "$scan" | grep "^semgrep "; }
killed="You are seeing this because the engine was killed."
out="$(FAKE_SILENT=semgrep FAKE_JSON='{"results": [], "errors": [{"code": 2, "level": "error", "message": "'"$killed"'"}], "paths": {}}' PATH="$TMP/tools:$PATH" bash "$scan")"
check "when semgrep fails with an empty log and an error in its JSON, then the failed line gives that message and names semgrep.json" \
  'dir="$(sed -n "s/^REPORT_DIR=//p" <<<"$out")"; grep -qxF "semgrep      failed    exit 2: $killed; see $dir/semgrep.json" <<<"$out"'
# The shape semgrep 1.185 really writes: the reason is on the line after "Error while running rules:".
out="$(semgrep_line '{"version":"1.185.0","results":[],"errors":[{"code":2,"level":"error","type":"SemgrepError","message":"Error while running rules: \n                    '"$killed"'\n\n                    The most common reason this happens is because it used too much memory.\n"}],"paths":{"scanned":[]}}')"
check "when semgrep's first message line ends in a colon, then the next line with text is joined to it" \
  'grep -qF "exit 2: Error while running rules: $killed; see " <<<"$out"'
out="$(semgrep_line '')"
check "when semgrep fails with both its log and its JSON empty, then the line says it wrote no error and names both" \
  'grep -qE "^semgrep +failed +exit 2: semgrep wrote no error \(.*/semgrep.log and .*/semgrep.json are empty\)$" <<<"$out"'
out="$(semgrep_line '{"results": [], "errors": [], "paths": {}}')"
check "when semgrep's JSON holds no error message, then the line says it wrote no error" 'grep -q "semgrep wrote no error" <<<"$out"'
long="$(printf 'a%.0s' {1..199})bc$(printf 'x%.0s' {1..99})"
out="$(semgrep_line '{"errors": [{"message": "'"$long"'"}]}')"
check "when the error message is 300 characters, then it is cut to its first 200" \
  'grep -qE "exit 2: a{199}b; see " <<<"$out"'
out="$(semgrep_line '{"errors": [{"message": "'"${long:0:200}"'"}]}')"
check "when the error message is exactly 200 characters, then it is kept whole" \
  'grep -qE "exit 2: a{199}b; see " <<<"$out"'
out="$(semgrep_line '{"results": [{"check_id": "x", "extra": {"message": "a finding"}}], "errors": [{"message": "the error"}, {"message": "a second error"}]}')"
check "when a finding with its own message comes before the error, then the line gives the first error's message, not the finding's" \
  'grep -q "exit 2: the error; see " <<<"$out"'
out="$(semgrep_line '{"errors": [{"message": "line one\nline two"}]}')"
check "when the error message spans lines, then only its first line is given" 'grep -q "exit 2: line one; see " <<<"$out"'
out="$(semgrep_line '{"errors": [{"message": "bad \"rule\" id"}]}')"
check "when the error message has escaped quotes, then they are kept as quotes" "grep -qF 'exit 2: bad \"rule\" id; see ' <<<\"\$out\""
out="$(semgrep_line '{
  "results": [],
  "errors": [
    {
      "message": "pretty printed"
    }
  ]
}')"
check "when semgrep's JSON is spread over lines, then its error message is still found" 'grep -q "exit 2: pretty printed; see " <<<"$out"'

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
check "when --changed, then its summary lines are recorded for this diff (what pr.sh feature --ready requires)" \
  'rec="$(source "$SCRIPTS/lib.sh" && diff_record landspec-security)"; [[ "$(cat "$rec")" == "$(grep -v "^REPORT_DIR=" <<<"$out")" ]] && grep -q "^gitleaks *missing" "$rec"'
FAKE_FIND=semgrep FAKE_OUT='{"results":[{"extra":{"severity":"ERROR"}}]}' PATH="$TMP/tools:$PATH" bash "$scan" --changed >/dev/null
check "when --changed and semgrep has a high finding, then the record keeps the findings high line (what pr.sh feature --ready reads)" \
  'rec="$(source "$SCRIPTS/lib.sh" && diff_record landspec-security)"; grep -qE "^semgrep +findings +high " "$rec"'
git switch --quiet -c feat/empty origin/develop
PATH="$TMP/none" bash "$scan" --changed >/dev/null
check "when --changed finds no changed file, then that result is recorded for the empty diff too" \
  '[[ "$(cat .git/landspec-security/empty)" == "all skipped no changed files" ]]'

git switch --quiet feat/x; shallow_repo
check "on a --depth 1 clone with no merge base, then --changed prints one refusal naming git fetch --unshallow and writes no record" \
  'one_refusal "git fetch --unshallow" env PATH="$TMP/none" bash "$scan" --changed && [[ -z "$(find .git/landspec-security -maxdepth 1 -type f 2>/dev/null)" ]]'

exit "$FAIL"
