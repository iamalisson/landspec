#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fmt="$SCRIPTS/formatters.sh"
real_pc="$(command -v pre-commit || true)"

# Fake pre-commit: `run --all-files <id>` runs that hook's `entry:` on every tracked file, refusing
# an unstaged config and a missing executable as the real one does (both exit 1).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pre-commit" <<'EOF'
#!/usr/bin/env bash
c=.pre-commit-config.yaml
[[ -f $c ]] || { echo "An error has occurred: InvalidConfigError: $c is not a file"; exit 1; }
if ! git ls-files --error-unmatch "$c" >/dev/null 2>&1 || ! git diff --quiet -- "$c"; then
  echo "[ERROR] Your pre-commit configuration is unstaged."; exit 1
fi
entry="$(awk -v id="$3" '$0 ~ "- id: *" id "$" { f = 1; next } f && /entry:/ { sub(/.*entry: */, ""); print; exit }' "$c")"
before="$(git diff --name-only)"
# shellcheck disable=SC2086  # the entry is a command line
command -v ${entry%% *} >/dev/null || { echo "$3....Failed"; echo; echo "Executable \`${entry%% *}\` not found"; exit 1; }
$entry $(git ls-files) || exit 1
[[ "$(git diff --name-only)" == "$before" ]] || exit 1
EOF
# A hook that rewrites each .py file holding UGLY; one that fails as a hook fetching its repo offline does.
cat > "$TMP/bin/rewrite" <<'EOF'
#!/usr/bin/env bash
for f; do [[ $f == *.py ]] && grep -q UGLY "$f" && sed -i.orig 's/UGLY/pretty/' "$f" && rm -f "$f.orig"; done; exit 0
EOF
cat > "$TMP/bin/offline" <<'EOF'
#!/usr/bin/env bash
echo "An error has occurred: CalledProcessError: fatal: unable to access 'https://example.invalid/': network unreachable"; exit 3
EOF
cat > "$TMP/bin/slow" <<'EOF'
#!/usr/bin/env bash
sleep 2
EOF
chmod +x "$TMP/bin/"*
P="$TMP/bin:$PATH"

hook() { printf '      - id: %s\n        name: %s\n        entry: %s\n        language: system\n' "$1" "$1" "$2"; }
config() { { echo "repos:"; echo "  - repo: local"; echo "    hooks:"; while (($#)); do hook "$1" "$2"; shift 2; done; } > .pre-commit-config.yaml; }

# fixture <dir> <ugly>: 10 .py files, <ugly> of them holding UGLY, plus a .md file, all committed.
fixture() {
  rm -rf "$1"; mkdir -p "$1"; cd "$1"; git init --quiet
  git config user.email t@t; git config user.name t; git config commit.gpgsign false
  for i in $(seq 1 10); do if ((i <= $2)); then echo "x = 'UGLY'" > "f$i.py"; else echo "x = 'ok'" > "f$i.py"; fi; done
  echo "# UGLY" > README.md
  git add -A; git commit --quiet -m init
}
no_leftover() { [[ "$(git worktree list | wc -l)" -eq 1 ]]; }
run() { out="$(PATH="${PCPATH:-$P}" bash "$fmt" 2>&1)"; code=$?; }

fixture "$TMP/r9" 9; config fmt rewrite; git add .pre-commit-config.yaml; git commit --quiet -m cfg
run
check "when a hook rewrites 9 of the 10 .py files, then it prints REWRITES=fmt 9/10 and checked 1 hooks" \
  '[[ $code == 0 ]] && grep -qx "REWRITES=fmt 9/10" <<<"$out" && grep -qx "FORMATTERS=checked 1 hooks" <<<"$out"'
check "then the repository is untouched and no worktree is left" '[[ -z "$(git status --porcelain)" ]] && grep -q UGLY f1.py && no_leftover'

fixture "$TMP/r1" 1; config fmt rewrite; run
check "when it rewrites 1 of 10, then no REWRITES= line" '[[ $code == 0 ]] && ! grep -q "^REWRITES=" <<<"$out" && grep -qx "FORMATTERS=checked 1 hooks" <<<"$out" && no_leftover'
check "then the config, present only in the working tree, is still checked (no UNCHECKED=)" '! grep -q "^UNCHECKED=" <<<"$out"'
fixture "$TMP/r5" 5; config fmt rewrite; run
check "when it rewrites 5 of 10 (half), then no REWRITES= line" '! grep -q "^REWRITES=" <<<"$out" && ! grep -q "^UNCHECKED=" <<<"$out"'
fixture "$TMP/r6" 6; config fmt rewrite; run
check "when it rewrites 6 of 10 (just over half), then REWRITES=fmt 6/10" 'grep -qx "REWRITES=fmt 6/10" <<<"$out"'

fixture "$TMP/r9u" 9; config fmt rewrite; run
check "when the config is untracked, then the hook still runs: REWRITES=fmt 9/10" 'grep -qx "REWRITES=fmt 9/10" <<<"$out" && ! grep -q "^UNCHECKED=" <<<"$out" && no_leftover'

config fmt rewrite noop true; run
check "when a rewriting hook comes before one that changes nothing (untracked config), then REWRITES= for the first only" \
  'grep -qx "REWRITES=fmt 9/10" <<<"$out" && ! grep -q "^REWRITES=noop" <<<"$out" && ! grep -q "^UNCHECKED=" <<<"$out" && grep -qx "FORMATTERS=checked 2 hooks" <<<"$out"'
config fmt rewrite; git add .pre-commit-config.yaml; git commit --quiet -m cfg; config fmt rewrite noop true; run
check "when a tracked config is edited to add the second hook, then REWRITES= for the first only and no UNCHECKED=" \
  'grep -qx "REWRITES=fmt 9/10" <<<"$out" && ! grep -q "^REWRITES=noop" <<<"$out" && ! grep -q "^UNCHECKED=" <<<"$out" && grep -qx "FORMATTERS=checked 2 hooks" <<<"$out"'
check "then the edited config is left as the user had it" '[[ "$(git status --porcelain)" == " M .pre-commit-config.yaml" ]] && grep -q "id: noop" .pre-commit-config.yaml'
config fmt rewrite fmt rewrite; run
check "when an id is listed twice, then it runs once" '[[ "$(grep -c "^REWRITES=fmt" <<<"$out")" == 1 ]] && grep -qx "FORMATTERS=checked 1 hooks" <<<"$out"'

fixture "$TMP/dirty" 9; config fmt rewrite; git add .pre-commit-config.yaml; git commit --quiet -m cfg
echo "x = 'mine'" > f2.py; echo "new" > notes.txt
before="$(git status --porcelain)"; run
check "when run in a checkout with a modified and an untracked file, then both are unchanged" \
  'grep -qx "REWRITES=fmt 9/10" <<<"$out" && [[ "$(git status --porcelain)" == "$before" && "$(cat f2.py)" == "x = '"'mine'"'" && "$(cat notes.txt)" == new ]] && no_leftover'

fixture "$TMP/miss" 9; config gone /nonexistent/fmt; run
check "when a hook's entry does not exist, then UNCHECKED= names pre-commit's not found line" \
  '[[ $code == 0 ]] && grep -qx "UNCHECKED=gone Executable \`/nonexistent/fmt\` not found" <<<"$out" && grep -qx "FORMATTERS=checked 1 hooks" <<<"$out" && no_leftover'
config net offline fmt rewrite; run
check "when a hook fails with network unreachable (exit 3), then UNCHECKED= carries it and the next hook still runs" \
  'grep -q "^UNCHECKED=net An error has occurred.*network unreachable$" <<<"$out" && grep -qx "REWRITES=fmt 9/10" <<<"$out"'
printf '#!/usr/bin/env bash\necho "fmt....Failed"\nexit 2\n' > "$TMP/pc2"; mkdir -p "$TMP/bin2"; mv "$TMP/pc2" "$TMP/bin2/pre-commit"; chmod +x "$TMP/bin2/pre-commit"
PCPATH="$TMP/bin2:$PATH" run
check "when pre-commit exits other than 0 and 1 with no error line, then UNCHECKED= names its first line" 'grep -qx "UNCHECKED=fmt fmt....Failed" <<<"$out"'
printf '#!/usr/bin/env bash\nexit 4\n' > "$TMP/bin2/pre-commit"
PCPATH="$TMP/bin2:$PATH" run
check "when it exits other than 0 and 1 silently, then UNCHECKED= names the exit code" 'grep -qx "UNCHECKED=fmt pre-commit exited 4" <<<"$out"'
printf '#!/usr/bin/env bash\necho "[ERROR] Your pre-commit configuration is unstaged."\nexit 1\n' > "$TMP/bin2/pre-commit"
PCPATH="$TMP/bin2:$PATH" run
check "when pre-commit refuses with an [ERROR] line and exit 1, then UNCHECKED= names it" 'grep -qx "UNCHECKED=fmt \[ERROR\] Your pre-commit configuration is unstaged." <<<"$out"'

rm .pre-commit-config.yaml; run
check "when there is no config, then FORMATTERS=skipped no .pre-commit-config.yaml" '[[ $code == 0 && "$out" == "FORMATTERS=skipped no .pre-commit-config.yaml" ]]'
no_scanners; rm -f "$TMP/none/pre-commit"
config fmt rewrite; PCPATH="$TMP/none" run
check "when pre-commit is not on PATH, then FORMATTERS=skipped pre-commit is not installed" '[[ $code == 0 && "$out" == "FORMATTERS=skipped pre-commit is not installed" ]]'

rm -rf "$TMP/empty"; mkdir "$TMP/empty"; cd "$TMP/empty"; git init --quiet; config fmt rewrite; run
check "when the repository has no commit yet, then skipped with git's error, exit 0, no worktree left" \
  '[[ $code == 0 && $(wc -l <<<"$out") -eq 1 ]] && grep -qE "^FORMATTERS=skipped cannot make a worktree at HEAD: .+" <<<"$out" && no_leftover'

fixture "$TMP/term" 9; config slow slow; PATH="$P" bash "$fmt" >/dev/null 2>&1 & pid=$!
for _ in $(seq 1 50); do [[ "$(git worktree list | wc -l)" -gt 1 ]] && break; sleep 0.1; done
kill -TERM "$pid"; wait "$pid" || true
check "when it is stopped while a hook runs, then the worktree is removed" 'no_leftover'

# The real pre-commit, when installed: a result or its own error text, never a silent pass.
if [[ -n "$real_pc" ]]; then
  fixture "$TMP/real" 9; config fmt "$TMP/bin/rewrite"; PCPATH="$PATH" run
  check "when the real pre-commit runs a rewriting hook (untracked config), then REWRITES= or UNCHECKED= with its error" \
    'grep -qxE "REWRITES=fmt 9/10|UNCHECKED=fmt .+" <<<"$out" && no_leftover'
  config gone /nonexistent/fmt; PCPATH="$PATH" run
  check "when the real pre-commit runs a hook whose entry does not exist, then UNCHECKED= with its not found text" \
    'grep -qE "^UNCHECKED=gone .*not found" <<<"$out"'
else
  echo "skip - pre-commit is not installed: the real pre-commit checks did not run"
fi

exit "$FAIL"
