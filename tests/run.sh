#!/usr/bin/env bash
# Run every test file; exit non-zero if any check failed.
# The files run in batches of LANDSPEC_TEST_JOBS at once (default: the machine's cores; 1 runs them
# one after another). Each file has its own temp repo, so they share nothing; output is printed in
# file order once a batch is done.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
status=0
jobs="${LANDSPEC_TEST_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "FAIL - LANDSPEC_TEST_JOBS must be a whole number above 0"; exit 1; }
logs="$(mktemp -d)"; trap 'rm -rf "$logs"' EXIT
# report <file>: its output, then the checks that hold whatever its own exit says.
report() {
  local t="$1" rc; rc="$(cat "$logs/$t.rc" 2>/dev/null || echo 1)"
  echo "== $t"; cat "$logs/$t.log"
  # A file that stops early (a failing setup step under set -e) would otherwise show no FAIL line.
  if ((rc != 0)); then echo "FAIL - $t stopped with exit $rc (a failing check, or a setup step that failed before the end)"; status=1; fi
  # A file that lost its last line exits 0 whatever its checks said.
  if grep -q '^FAIL' "$logs/$t.log"; then status=1; fi
  if [[ "$(tail -n 1 "$t")" != 'exit "$FAIL"' ]]; then echo "FAIL - $t does not end in: exit \"\$FAIL\""; status=1; fi
}
batch=()
flush() { local t; wait; for t in ${batch[@]+"${batch[@]}"}; do report "$t"; done; batch=(); }
for t in *.test.sh; do
  ( bash "$t" > "$logs/$t.log" 2>&1; echo "$?" > "$logs/$t.rc" ) &
  batch+=("$t")
  ((${#batch[@]} < jobs)) || flush
done
flush
exit "$status"
