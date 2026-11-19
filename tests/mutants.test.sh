#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh # branch.sh looks up the feature PR before it makes or pushes the branch
m="$SCRIPTS/mutants.sh"

new_repo standard
mkdir -p .specify/memory
check "when the constitution has no mutate command, then it says so and does not fail" \
  'out="$("$m")" && grep -q "^mutants missing" <<<"$out" && grep -q "landspec:adopt" <<<"$out"'

# A fake mutation tool: records what it was given, exits as told.
cat > "$TMP/mutate.sh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$LANDSPEC_CHANGED_FILES" > "$TMP/seen.files"; cp "$LANDSPEC_DIFF_FILE" "$TMP/seen.diff"
exit "$(cat "$TMP/mutate.rc")"
FAKE
chmod +x "$TMP/mutate.sh"; export TMP
printf '**Commands**: build `[BUILD_COMMAND]` · test `npm test` · lint `[LINT_COMMAND]` · mutate `%s`\n' "$TMP/mutate.sh" > .specify/memory/constitution.md

commit_tasks '- [ ] T001 Add search in `src/search.ts`'
"$SCRIPTS/branch.sh" 001 >/dev/null
check "when nothing changed on the branch, then it is skipped" 'out="$("$m")" && grep -q "^mutants skipped" <<<"$out"'

mkdir -p src tests; echo 'export const search = 1' > src/search.ts; echo 'test' > tests/search.test.ts
git add src tests; git commit --quiet -m "feat: search"
echo 'tests: ([' >> .specify/memory/constitution.md; echo 0 > "$TMP/mutate.rc"
bad=0; out="$("$m" 2>&1)" || bad=$?
check "when the constitution's tests: regex is invalid, then it refuses and records nothing (no skipped result)" \
  '((bad != 0)) && grep -qxF "landspec: the constitution'"'"'s tests: regex is invalid: ([" <<<"$out" && ! grep -q "^mutants" <<<"$out" \
   && [[ ! -e "$(source "$SCRIPTS/lib.sh" && diff_record landspec-mutants)" ]]'
sed -i.bak '/^tests:/d' .specify/memory/constitution.md
echo 0 > "$TMP/mutate.rc"
check "when every mutant is caught, then it reports ok and the command saw the changed sources without the tests" \
  'out="$("$m")" && grep -q "^mutants ok" <<<"$out" && [[ "$(cat "$TMP/seen.files")" == "src/search.ts" ]] && grep -q "^+export const search" "$TMP/seen.diff"'
echo 2 > "$TMP/mutate.rc"
check "when a mutant survives, then it reports survivors and where the log is" \
  'out="$("$m")" && grep -q "^mutants survivors" <<<"$out" && grep -q "mutants.log" <<<"$out"'
check "then the report lives under .git, never in the tree" '[[ -z "$(git status --porcelain)" ]]'
# Every worktree shares .git/landspec-mutants: two runs in the same second get their own folder.
mkdir -p "$TMP/clock"; printf '#!/usr/bin/env bash\necho 20260101-000000\n' > "$TMP/clock/date"; chmod +x "$TMP/clock/date"
one="$(PATH="$TMP/clock:$PATH" "$m" | sed -n 's/^REPORT_DIR=//p')"; two="$(PATH="$TMP/clock:$PATH" "$m" | sed -n 's/^REPORT_DIR=//p')"
check "when two runs start in the same second, then each gets its own report folder" \
  '[[ -n "$one" && "$one" != "$two" && -s "$one/changes.diff" && -s "$two/changes.diff" ]]'
sed -i.bak 's/mutate `[^`]*`/mutate `no-such-mutator --run`/' .specify/memory/constitution.md
check "when the mutate command is not installed (exit 127), then it reports unavailable, names it, and records that" \
  'out="$("$m")" && grep -q "^mutants unavailable .*no-such-mutator --run" <<<"$out" && ! grep -q survivors <<<"$out" \
   && grep -q "^mutants unavailable" "$(source "$SCRIPTS/lib.sh" && diff_record landspec-mutants)"'
touch "$TMP/noexec"; sed -i.bak "s|mutate \`[^\`]*\`|mutate \`$TMP/noexec\`|" .specify/memory/constitution.md
check "when the mutate command cannot be executed (exit 126), then it reports unavailable" 'out="$("$m")" && grep -q "^mutants unavailable" <<<"$out"'
printf '**Commands**: build `[BUILD_COMMAND]` · test `npm test` · lint `[LINT_COMMAND]` · mutate `%s`\n' "$TMP/mutate.sh" > .specify/memory/constitution.md

shallow_repo
check "on a --depth 1 clone with no merge base, then it prints one refusal naming git fetch --unshallow and writes no record" \
  'one_refusal "git fetch --unshallow" "$m" && [[ -z "$(find .git/landspec-mutants -maxdepth 1 -type f 2>/dev/null)" ]]'

exit "$FAIL"
