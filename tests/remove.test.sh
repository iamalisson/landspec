#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# remove.sh keeps what the user changed. A stub `specify` is enough: remove.sh only needs the command
# to exist, so this runs on every CI job (bash 3.2 and BSD included).
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/specify"; chmod +x "$TMP/bin/specify"
rm_out() { "$ROOT/bin/remove.sh" . 2>&1 || true; }

new_repo standard
"$SCRIPTS/level.sh" standard --no-branches >/dev/null
git add .github/workflows/security.yml; git commit --quiet -m security
echo "# my step" >> .github/workflows/security.yml
echo "# mine" >> .github/dependabot.yml
out="$(rm_out)"
check "when a managed workflow (committed alone) is edited and not committed, then remove.sh keeps it and prints kept (edited)" \
  '[[ -f .github/workflows/security.yml ]] && grep -qxF "kept (edited): .github/workflows/security.yml" <<<"$out"'
check "when an untracked managed file differs from its recorded SHA-256, then it is kept" \
  '[[ -f .github/dependabot.yml ]] && grep -qxF "kept (edited): .github/dependabot.yml" <<<"$out"'
check "when a managed file is unchanged, then it is still removed" \
  '[[ ! -e .github/workflows/ci.yml ]] && grep -qxF "removed: .github/workflows/ci.yml" <<<"$out"'
check "then the record names only the kept files, and says so" \
  '[[ "$(awk "{ print \$2 }" .specify/landspec-files.sha256 | sort | tr "\n" " ")" == ".github/dependabot.yml .github/workflows/security.yml " ]] && grep -q "^kept: .specify/landspec-files.sha256" <<<"$out"'

# A project set up before the record existed: only a tracked, unchanged marked file is removed.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo standard
"$SCRIPTS/level.sh" standard --no-branches >/dev/null
rm -f .specify/landspec-files.sha256
git add .github/workflows/security.yml .github/workflows/ci.yml; git commit --quiet -m workflows
echo "# my step" >> .github/workflows/ci.yml
out="$(rm_out)"
check "when there is no record, then a tracked unchanged marked file is removed and an untracked one is kept" \
  '[[ ! -e .github/workflows/security.yml && -f .github/dependabot.yml ]] && grep -qxF "kept (edited): .github/dependabot.yml" <<<"$out"'
check "when there is no record and a tracked marked file is edited and not committed, then it is kept and prints kept (edited)" \
  '[[ -f .github/workflows/ci.yml ]] && grep -qxF "kept (edited): .github/workflows/ci.yml" <<<"$out"'

# A second run must not delete what the first kept, once the edit is committed.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo standard
"$SCRIPTS/level.sh" standard --no-branches >/dev/null
echo "# my step" >> .github/workflows/security.yml
git add .github/workflows/security.yml; git commit --quiet -m "my step"
rm_out >/dev/null
out="$(rm_out)"
check "when remove runs twice, then the file the first run kept is kept again, its edit committed in between" \
  '[[ -f .github/workflows/security.yml ]] && grep -qxF "kept (edited): .github/workflows/security.yml" <<<"$out"'

# Nothing kept: nothing of landspec's stays behind, a deleted file's line included.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo standard
"$SCRIPTS/level.sh" standard --no-branches >/dev/null
rm .github/dependabot.yml
rm_out >/dev/null
check "when nothing is kept, then no record remains, even with a line for a file the user deleted" '[[ ! -e .specify/landspec-files.sha256 ]]'

# CODEOWNERS and SECURITY.md carry no marker: the record decides, or their shape when there is none.
full_repo() { rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo full; "$SCRIPTS/level.sh" full --no-branches >/dev/null; }
full_repo
sed -i.bak '2s/.*/* @acme\/platform-team/' .github/CODEOWNERS; echo "my policy" >> SECURITY.md; rm -f .github/CODEOWNERS.bak
out="$(rm_out)"
check "when CODEOWNERS and SECURITY.md are edited and the record names them, then both are kept and named" \
  'grep -q "acme" .github/CODEOWNERS && grep -q "my policy" SECURITY.md && grep -qxF "kept (edited): .github/CODEOWNERS" <<<"$out" && grep -qxF "kept (edited): SECURITY.md" <<<"$out"'

full_repo
sed -i.bak '2s/.*/* @acme\/platform-team/' .github/CODEOWNERS; echo "my policy" >> SECURITY.md; rm -f .github/CODEOWNERS.bak
rm -f .specify/landspec-files.sha256
out="$(rm_out)"
check "when they are edited and no record exists (set up before 1.8.0), then both are kept and named" \
  'grep -q "acme" .github/CODEOWNERS && grep -q "my policy" SECURITY.md && grep -qxF "kept (edited): .github/CODEOWNERS" <<<"$out" && grep -qxF "kept (edited): SECURITY.md" <<<"$out"'

full_repo
rm -f .specify/landspec-files.sha256
out="$(rm_out)"
check "when CODEOWNERS is untouched and no record exists, then it is still removed" '[[ ! -e .github/CODEOWNERS ]] && grep -qxF "removed: .github/CODEOWNERS" <<<"$out"'

full_repo
rm -f .specify/landspec-files.sha256
echo "* @me/extra" >> .github/CODEOWNERS
out="$(rm_out)"
check "when CODEOWNERS has the user's own third line and no record exists, then it is kept and named" \
  'grep -q "me/extra" .github/CODEOWNERS && grep -qxF "kept (edited): .github/CODEOWNERS" <<<"$out"'

full_repo
rm -f .specify/landspec-files.sha256
printf '* @me/extra' >> .github/CODEOWNERS
out="$(rm_out)"
check "when that third line has no trailing newline, then CODEOWNERS is still kept and named" \
  'grep -q "me/extra" .github/CODEOWNERS && grep -qxF "kept (edited): .github/CODEOWNERS" <<<"$out"'

full_repo
rm -f .specify/landspec-files.sha256
printf '# Our policy\nmine\n' > SECURITY.md
out="$(rm_out)"
check "when the user's own SECURITY.md has another first line and no record exists, then it is kept and not called edited" \
  'grep -q mine SECURITY.md && ! grep -q "kept (edited): SECURITY.md" <<<"$out"'

full_repo
rm -f .specify/landspec-files.sha256
git remote set-url origin https://github.com/octo/app.git
sed -i.bak '2s/.*/* @octo/' .github/CODEOWNERS; rm -f .github/CODEOWNERS.bak
out="$(rm_out)"
check "when CODEOWNERS names the repository's owner and no record exists, then it is removed" '[[ ! -e .github/CODEOWNERS ]] && grep -qxF "removed: .github/CODEOWNERS" <<<"$out"'

rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
mkdir -p .claude; printf '{ "mine": true }\n' > .claude/settings.json
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
out="$(rm_out)"
check "when the user's own .claude/settings.json was there first, then it is kept and not called edited" \
  'grep -q mine .claude/settings.json && ! grep -q "kept (edited): .claude/settings.json" <<<"$out"'

# "{" and a shebang open every such file, so with no record they say nothing about who wrote it.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
rm -f .specify/landspec-files.sha256
printf '{\n  "mine": true\n}\n' > .claude/settings.json
printf '#!/usr/bin/env bash\necho mine\n' > .githooks/pre-commit
out="$(rm_out)"
check "when there is no record, then the user's own settings.json and hook are kept and not called edited" \
  'grep -q mine .claude/settings.json && grep -q mine .githooks/pre-commit && ! grep -qE "kept \(edited\): (.claude/settings.json|.githooks/pre-commit)" <<<"$out"'

# A hook kept because it was edited still calls scripts that are gone: say so.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
echo "# my line" >> .githooks/pre-commit
out="$(rm_out)"
check "when a git hook is kept, then one line says it still calls landspec's scripts and how to stop that" \
  '[[ -f .githooks/pre-commit ]] && grep -q "^kept: .githooks still calls landspec.s scripts" <<<"$out"'

rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
echo "# my line" >> .githooks/pre-push
out="$(rm_out)"
check "when only the pre-push hook is kept, then the line is printed too" \
  '[[ -f .githooks/pre-push && ! -e .githooks/pre-commit ]] && grep -q "^kept: .githooks still calls landspec.s scripts" <<<"$out"'

rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
printf '#!/usr/bin/env bash\necho mine\n' > .githooks/pre-commit
out="$(rm_out)"
check "when the user rewrote the hook and it no longer calls landspec, then the line is not printed" \
  'grep -q mine .githooks/pre-commit && ! grep -q "still calls landspec" <<<"$out"'

# --with-speckit deletes the record with .specify, so it must not say the record stays.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
echo "# my line" >> .githooks/pre-commit
out="$("$ROOT/bin/remove.sh" . --with-speckit 2>&1 || true)"
check "when --with-speckit runs with a kept file, then the file stays and no line says the record stays" \
  '[[ -f .githooks/pre-commit && ! -e .specify ]] && grep -qxF "kept (edited): .githooks/pre-commit" <<<"$out" && ! grep -q "^kept: .specify/landspec-files.sha256" <<<"$out"'

# The constitution: only an untouched template is deleted, and markers are read at line start.
const=.specify/memory/constitution.md
const_repo() { rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo lite; mkdir -p .specify/memory; cp "$ROOT/preset/templates/constitution-template.md" "$const"; "$SCRIPTS/level.sh" lite --no-branches >/dev/null; }
const_repo
out="$(rm_out)"
check "when the constitution is landspec's untouched template, then remove deletes it" '[[ ! -e "$const" ]] && grep -q "never filled in" <<<"$out"'

const_repo
sed -i.bak 's/^## Project$/## Project\n\nmy real text/' "$const"; rm -f "$const.bak"
rm_out >/dev/null
check "when it is filled in but keeps the title placeholder, then remove keeps the text and strips the block" \
  'grep -q "my real text" "$const" && ! grep -q "^<!-- landspec:start" "$const"'

const_repo
printf 'The marker is written <!-- landspec:start like this.\nThe end is <!-- landspec:end --> in prose.\n\n## After\nkeep me\n' >> "$const"
sed -i.bak '1s/.*/# App Constitution/' "$const"; rm -f "$const.bak"
rm_out >/dev/null
check "when a valid block is followed by mid-line markers, then everything after the block stays" \
  'grep -q "keep me" "$const" && grep -q "written <!-- landspec:start" "$const" && grep -q "end is <!-- landspec:end" "$const" && ! grep -q "^<!-- landspec:start" "$const"'

const_repo
sed -i.bak -e '1s/.*/# App Constitution/' -e '/^<!-- landspec:start/a\
The end is <!-- landspec:end --> in prose.\
stale block line
' "$const"; rm -f "$const.bak"
rm_out >/dev/null
check "when a mid-line end marker sits inside the block, then the whole block is stripped" '[[ -f "$const" ]] && ! grep -q "stale block line" "$const"'

const_repo
printf '# App Constitution\n\nThe marker is written <!-- landspec:start like this.\n' > "$const"
out="$(rm_out)"
check "when the only marker is mid-line, then no block is reported removed" '! grep -q "landspec block removed" <<<"$out" && grep -q "written <!-- landspec:start" "$const"'

const_repo
sed -i.bak '1s/.*/# App Constitution/' "$const"; rm -f "$const.bak"
out="$("$ROOT/bin/remove.sh" . --with-speckit 2>&1 || true)"
check "when --with-speckit deletes a filled constitution, then it says so and never that the text was kept" \
  '[[ ! -e .specify ]] && ! grep -q "your text kept" <<<"$out" && grep -q "the constitution went with it" <<<"$out"'
check "then the closing text does not count .specify among what was kept" 'grep -q "files you edited outside .specify/" <<<"$out"'

const_repo
rm "$const"
out="$("$ROOT/bin/remove.sh" . --with-speckit 2>&1 || true)"
check "when --with-speckit finds no constitution, then it does not say one went" '! grep -q "the constitution went with it" <<<"$out"'

const_repo
awk '/^<!-- landspec:end -->/ { next } /^<!-- landspec:start/ { print "<!-- landspec:end -->" } { print }' "$const" > "$const.tmp"; mv "$const.tmp" "$const"
echo 'my text after' >> "$const"
# A failing `specify` sends remove.sh to its rm -rf fallback, so a late refusal would lose the config.
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/specify"
unchanged() { cmp -s "$const" "$TMP/const.before" && cmp -s "$LANDSPEC_CFG" "$TMP/cfg.before" && [[ -f .githooks/pre-commit && -f .specify/landspec-files.sha256 ]]; }
LANDSPEC_CFG=.specify/extensions/landspec/landspec-config.yml; cp "$const" "$TMP/const.before"; cp "$LANDSPEC_CFG" "$TMP/cfg.before"
check "when the markers are reversed, then remove refuses and changes nothing, the scaffold and config included" \
  'fails_with "damaged" "$ROOT/bin/remove.sh" . && unchanged'

const_repo
sed -i.bak '/^<!-- landspec:end -->/d' "$const"; rm -f "$const.bak"; echo 'my text after' >> "$const"
cp "$const" "$TMP/const.before"; cp "$LANDSPEC_CFG" "$TMP/cfg.before"
check "when the end marker is missing, then remove refuses and changes nothing" \
  'fails_with "no '"'"'<!-- landspec:end -->'"'"'" "$ROOT/bin/remove.sh" . && unchanged'

const_repo
echo '<!-- landspec:start (managed) -->' >> "$const"
cp "$const" "$TMP/const.before"; cp "$LANDSPEC_CFG" "$TMP/cfg.before"
check "when a second start marker follows the block, then remove refuses and changes nothing" \
  'fails_with "damaged" "$ROOT/bin/remove.sh" . && unchanged'

const_repo
echo '<!-- landspec:end -->' >> "$const"
cp "$const" "$TMP/const.before"; cp "$LANDSPEC_CFG" "$TMP/cfg.before"
check "when a second end marker follows the block, then remove refuses and changes nothing" \
  'fails_with "damaged" "$ROOT/bin/remove.sh" . && unchanged'

const_repo
sed -i.bak '/^<!-- landspec:start/d' "$const"; rm -f "$const.bak"
cp "$const" "$TMP/const.before"; cp "$LANDSPEC_CFG" "$TMP/cfg.before"
check "when only an end marker is left, then remove refuses and changes nothing" \
  'fails_with "damaged" "$ROOT/bin/remove.sh" . && unchanged'

git init --quiet "$TMP/oldname"; mkdir -p "$TMP/oldname/.specify/extensions/jit"
check "when the project still has the old jit folder, then remove refuses and names init, and deletes nothing" \
  'fails_with "run /landspec:init once" "$ROOT/bin/remove.sh" "$TMP/oldname" && [[ -d "$TMP/oldname/.specify/extensions/jit" ]]'

# .mcp.json (aws: on) carries no marker: only its recorded SHA-256 says it is landspec's.
mcp_repo() {
  cd "$TMP"; rm -rf "$TMP/repo" "$TMP/origin.git"; new_repo lite
  echo "aws: on" >> .specify/extensions/landspec/landspec-config.yml
  "$SCRIPTS/level.sh" lite --no-branches >/dev/null
}
mcp_repo
out="$(rm_out)"
check "when the generated .mcp.json is unchanged, then remove.sh deletes it" \
  '[[ ! -e .mcp.json ]] && grep -qxF "removed: .mcp.json" <<<"$out"'
mcp_repo
printf '{ "mcpServers": {} }\n' > .mcp.json
out="$(rm_out)"
check "when the generated .mcp.json was edited, then remove.sh keeps it" \
  '[[ "$(cat .mcp.json)" == "{ \"mcpServers\": {} }" ]] && grep -qxF "kept (edited): .mcp.json" <<<"$out"'
cd "$TMP"; rm -rf "$TMP/repo" "$TMP/origin.git"; new_repo lite
printf '{ "mcpServers": {} }\n' > .mcp.json
"$SCRIPTS/level.sh" lite --no-branches >/dev/null
out="$(rm_out)"
check "when a .mcp.json landspec never wrote is there (aws off), then remove.sh leaves it and says nothing of it" \
  '[[ -f .mcp.json ]] && ! grep -qF ".mcp.json" <<<"$out"'

exit "$FAIL"
