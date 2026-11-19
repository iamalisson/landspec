#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# Static checks on this repo's own workflows and docs: pins, drift, references.
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
cd "$ROOT"

# The harness itself: a check must fail when any step fails, and must never end the file.
harness="$(FAIL=0; check "a failing first step" 'false; true'; check "an exit inside" 'exit 0'; echo "still running")"
check "the test harness fails a check whose first step fails (not only its last)" 'grep -q "^FAIL - a failing first step" <<<"$harness"'
check "an exit inside a check ends only that check, never the test file" 'grep -q "^still running$" <<<"$harness"'

# The runner: exit codes alone would miss a FAIL line in a file that lost its last line.
mkdir -p "$TMP/suite"; cp tests/run.sh "$TMP/suite/run.sh"
suite() { printf '%b' "$1" > "$TMP/suite/a.test.sh"; bash "$TMP/suite/run.sh"; }
check "when a test file passes and ends in its exit line, then run.sh passes" 'suite "FAIL=0\nexit \"\$FAIL\"\n"'
check "when a test file prints a FAIL line and still exits 0, then run.sh fails" '! suite "FAIL=0\necho \"FAIL - x\"\nexit \"\$FAIL\"\n"'
check "when a test file loses its last line, then run.sh fails and names it" 'fails_with "a.test.sh" suite "FAIL=0\necho fine\n"'

# The real spec-kit job cannot skip setup.test.sh's second half.
check "when the Linux job runs the tests, then it sets REQUIRE_SPECIFY" \
  'grep -q "REQUIRE_SPECIFY: \"1\"" <<<"$(sed -n "/^  linux:/,/^  bash32:/p" .github/workflows/test.yml)"'
no_scanners; rm -f "$TMP/none/specify"
check "when REQUIRE_SPECIFY is set and specify is missing, then setup.test.sh fails" \
  'PATH="$TMP/none" REQUIRE_SPECIFY=1 fails_with "REQUIRE_SPECIFY" bash tests/setup.test.sh'
check "when it is not set, then setup.test.sh skips the rest and says so" \
  'PATH="$TMP/none" REQUIRE_SPECIFY= bash tests/setup.test.sh | grep -q "^skip - the rest needs the specify CLI"'

# The Bash guard stays registered. The bash 3.2 job has no python3: there, the entry is read with sed.
check "when hooks.json is read, then it runs guard-git.sh on the Bash tool with onFailure block" \
  'if ! command -v python3 >/dev/null; then e="$(sed -n "/\"matcher\": *\"Bash\"/,/^      }/p" hooks/hooks.json)"; [[ "$e" == *guard-git.sh* && "$e" == *"\"onFailure\": \"block\""* ]]; exit; fi
  python3 -c "import json,sys; h=[e for e in json.load(open(sys.argv[1]))[\"hooks\"][\"PreToolUse\"] if \"guard-git.sh\" in e[\"hooks\"][0][\"command\"]]; sys.exit(0 if h[0][\"matcher\"]==\"Bash\" and h[0][\"hooks\"][0][\"onFailure\"]==\"block\" else 1)" hooks/hooks.json'

workflows="$(find .github/workflows extension/scaffold -name '*.yml' -path '*workflows*')"

check "every action in every workflow is pinned to a full commit SHA" \
  '! grep -hE "uses: [^ ]+@" $workflows | grep -vE "@[0-9a-f]{40}( |$)"'

# An action pinned in pins.sh must use that same SHA everywhere, so one bump updates everything.
drift=""
while IFS= read -r line; do
  ref="${line#*=\"}"; ref="${ref%% *}"; action="${ref%@*}"
  other="$(grep -hoE "uses: $action@[0-9a-f]{40}" $workflows | sed 's/^uses: //' | sort -u | grep -vx "$ref" || true)"
  [[ -z "$other" ]] || drift+="$other (pins.sh: $ref) "
done < <(grep -E '^PIN_[A-Z_]+="' extension/scripts/pins.sh)
check "then actions also in pins.sh use the same SHA everywhere${drift:+ — drift: $drift (fix: bin/sync-pins.sh)}" '[[ -z "$drift" ]]'

# F4.1: Dependabot reads only this repo's workflows, so every PIN_* action is used by one of them,
# exactly as pins.sh writes it (pins.yml's never-run actions job); the tool versions are checked weekly.
unused=""
while IFS= read -r line; do
  ref="${line#*=\"}"; ref="${ref%\"*}"
  grep -qrF -- "uses: $ref" .github/workflows || unused+="${line%%=*} "
done < <(grep -E '^PIN_[A-Z_]+="' extension/scripts/pins.sh)
check "when pins.sh has a PIN_* action, then some workflow in .github/workflows uses it as pins.sh writes it${unused:+ — unused: $unused}" '[[ -z "$unused" ]]'
tools_job="$(awk '/^  tools:/ { p = 1; next } /^  [a-z_]+:/ { p = 0 } p' .github/workflows/pins.yml 2>/dev/null || true)"
check "when pins.yml's tools job is read, then it runs bin/check-tools.sh with issues: write" \
  'grep -q "bin/check-tools.sh" <<<"$tools_job" && grep -qE "^ +issues: write" <<<"$tools_job"'
check "then pins.yml runs on a weekly schedule" 'grep -qE "^ +- cron: \"[0-9]+ [0-9]+ \* \* [0-6]\"" .github/workflows/pins.yml'

# The PyPI pin is bumped by hand (check-tools.sh reads GitHub only): the generated .mcp.json must follow it.
mcp_v="$(sed -nE 's/^MCP_PROXY_VERSION="([^"]+)".*/\1/p' extension/scripts/pins.sh)"
check "when pins.sh sets MCP_PROXY_VERSION, then the .mcp.json level.sh generates runs that exact version" \
  '[[ -n "$mcp_v" ]] && cd "$TMP" && new_repo lite >/dev/null && echo "aws: on" >> .specify/extensions/landspec/landspec-config.yml && "$SCRIPTS/level.sh" lite --no-branches >/dev/null && [[ "$(grep -oE "mcp-proxy-for-aws==[^\"]+" .mcp.json)" == "mcp-proxy-for-aws==$mcp_v" ]]'
check "then docs/reference.md says this pin is bumped by hand" 'grep -qF "MCP_PROXY_VERSION" docs/reference.md'

if python3 -c "import yaml" 2>/dev/null; then
  check "every workflow is valid YAML" 'python3 -c "import sys, yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]" $workflows'
else
  echo "skip - YAML parse check (python3 with PyYAML not available here)"
fi

# bin/sync-pins.sh, on a copy: a Dependabot-style bump in every workflow is copied into pins.sh.
copy="$TMP/pins-repo"; mkdir -p "$copy/extension/scripts"
cp -R bin .github "$copy/"; cp extension/scripts/pins.sh "$copy/extension/scripts/"; cp -R extension/scaffold "$copy/extension/"
old="$(sed -nE 's/^PIN_CHECKOUT="actions\/checkout@([0-9a-f]{40}).*/\1/p' extension/scripts/pins.sh)"
new=1111111111111111111111111111111111111111
find "$copy/.github/workflows" -name '*.yml' -exec sed -i.bak "s/checkout@$old # v[0-9.]*/checkout@$new # v9.9.9/" {} +
check "when Dependabot bumped an action in every workflow, then sync-pins copies it into pins.sh" \
  '"$copy/bin/sync-pins.sh" | grep -q "SYNCED=1" && grep -qx "PIN_CHECKOUT=\"actions/checkout@$new # v9.9.9\"" "$copy/extension/scripts/pins.sh"'
check "then sync-pins keeps pins.sh executable (it rewrites in place)" '[[ -x "$copy/extension/scripts/pins.sh" ]]'
check "then sync-pins also updates the scaffold workflows Dependabot doesn't see" \
  'grep -q "uses: actions/checkout@$new # v9.9.9" "$copy/extension/scaffold/full/.github/workflows/release.yml" && ! grep -rq "checkout@$old" "$copy/extension/scaffold"'
cp "$copy/.github/workflows/test.yml" "$copy/.github/workflows/other.yml"
sed -i.bak "s/checkout@$new # v9.9.9/checkout@$old # v4.4.0/" "$copy/.github/workflows/other.yml"
check "when workflows disagree on an action, then sync-pins refuses and lists both" \
  'out="$("$copy/bin/sync-pins.sh" 2>&1)" && exit 1; grep -q "$old" <<<"$out" && grep -q "$new" <<<"$out"'

# F5.6: the macOS job runs on PRs that touch the scripts and on every tag, in its own workflow
# (path filters are per workflow). One condition per check: an && chain would hide which grep failed.
mac=.github/workflows/macos.yml
on_pr="$(awk '/^  pull_request:/ { p = 1; next } /^  [a-z_]+:/ { p = 0 } p' "$mac" 2>/dev/null || true)"
on_push="$(awk '/^  push:/ { p = 1; next } /^  [a-z_]+:/ { p = 0 } p' "$mac" 2>/dev/null || true)"
check "when macos.yml is read, then it runs on pull requests touching extension/scripts/" 'grep -qF -- "- \"extension/scripts/**\"" <<<"$on_pr"'
check "then it runs on pull requests touching bin/" 'grep -qF -- "- \"bin/**\"" <<<"$on_pr"'
check "then it runs on pull requests touching hooks/" 'grep -qF -- "- \"hooks/**\"" <<<"$on_pr"'
check "then it runs on every tag" 'grep -qF "tags: [\"**\"]" <<<"$on_push"'
check "then no if: in macos.yml names github.event_name (it would skip the PR and tag runs)" '[[ -f "$mac" ]] && ! grep -qE "^ *if:.*github\.event_name" "$mac"'
check "then test.yml has no macOS job left" '! grep -qE "runs-on: *macos" .github/workflows/test.yml'

# The spec-kit version landspec is tested with is written in three places; they must agree.
sk="$(sed -nE 's/^SPECKIT_VERSION="(v[0-9.]+)".*/\1/p' bin/setup.sh)"
check "the spec-kit version in setup.sh ($sk) matches the init skill and the README badge" \
  '[[ -n "$sk" ]] && grep -qF "spec-kit.git@$sk\`" skills/init/SKILL.md && grep -qF "spec--kit-$sk-" README.md && grep -qF "alt=\"spec-kit $sk\"" README.md'

# F2.4: the guard's "onFailure": "block" needs Claude Code 2.1.295, so no doc may give a lower minimum.
mins="$(grep -ohE "Claude Code v?[0-9]+\.[0-9]+\.[0-9]+ or (newer|later)" README.md docs/*.md .specify/memory/constitution.md | awk '{ sub(/^v/, "", $3); print $3 }' | tr '\n' ' ')"
low=""
for v in $mins; do
  IFS=. read -r v1 v2 v3 <<<"$v"
  if ((v1 < 2 || (v1 == 2 && (v2 < 1 || (v2 == 1 && v3 < 295))))); then low+=" $v"; fi
done
check "when hooks.json uses onFailure, then every \"Claude Code X or newer\" in the docs is 2.1.295 or newer (found: ${mins:-none}${low:+; too low:$low}) and the README says nothing about older versions" \
  '! grep -q "\"onFailure\"" hooks/hooks.json || { [[ -n "$mins" && -z "$low" ]] && ! grep -qi "older versions" README.md; }'

# F1.6: close-linked-issues' step, its run: block run as Actions runs it (bash -e), with a fake gh
# that fails to close #12.
sed -n '/^        run: |$/,$p' extension/scaffold/standard/.github/workflows/close-linked-issues.yml | sed '1d; s/^          //' > "$TMP/close-step.sh"
mkdir -p "$TMP/closebin"
printf '#!/bin/sh\necho "$*" >> "%s"\n[ "$3" = 12 ] || exit 0\necho "HTTP 403: Resource not accessible" >&2; exit 1\n' "$TMP/close.log" > "$TMP/closebin/gh"
chmod +x "$TMP/closebin/gh"
check "when the body says \"fixes #12\" and \"Closes #3\" and closing 12 fails, then the step exits non-zero and names #12" \
  'out="$(BODY="fixes #12 and Closes #3" REPO=acme/app PR=7 BASE=develop PATH="$TMP/closebin:$PATH" bash -eo pipefail "$TMP/close-step.sh" 2>&1)" && exit 1; grep -q "could not close: #12" <<<"$out"'
check "then gh issue close 3 is still called" 'grep -q "^issue close 3 " "$TMP/close.log"'

# F3.1/F4.3: a security finding reaches the PR as one line, never its detail: both prompts say so.
check "the review prompt's Report section and pr.md step 5 say a security finding is one 'Security: reported privately (<id>)' line" \
  'r="$(sed -n "/^## Report/,\$p" extension/commands/review.md)"; p="$(sed -n "/^5\. /,/^6\. /p" extension/commands/pr.md)" \
   && [[ "$r" == *"Security: reported privately (<id>)"* && "$p" == *"Security: reported privately (<id>)"* ]]'

# F4.2: the audit's advisory call sends the JSON body GitHub accepts, after looking for an existing one.
adv="$(sed -n '/^- \*\*Public repository:\*\*/,/^- \*\*A real secret/p' skills/security/SKILL.md)"
adv_body="$(sed -n '/--input -/,/^ *EOF$/p' <<<"$adv")"
check "when the skill's advisory call is read, then the JSON after --input - names summary, description, severity, vulnerabilities and ecosystem" \
  '[[ -n "$adv_body" ]]; for k in summary description severity vulnerabilities ecosystem; do grep -q "\"$k\"" <<<"$adv_body"; done'
check "then a --paginate lookup of the advisories comes before the -X POST" \
  'p="$(grep -n -- "--paginate" <<<"$adv" | head -1 | cut -d: -f1)"; x="$(grep -n -- "-X POST" <<<"$adv" | head -1 | cut -d: -f1)"; [[ -n "$p" && -n "$x" ]] && ((p < x))'

# F4.5: Semgrep's rules are not in the extension (their license forbids it): the docs say where they come from.
check "when the README CI row and the security doc's CI row are read, then they say the rules come from the Semgrep registry" \
  'grep -E "^\| \*\*every PR, and weekly\*\* \|" README.md | grep -q "Semgrep registry" && grep -E "^\| Every PR, push and week \|" docs/security.md | grep -q "Semgrep registry"'

# F4.4/#41: init offers the free GitHub settings on every level, and the docs say what lite lacks.
# init's calls are made by the model, so these are plain reads of the prompt (said, not faked).
init_gh="$(sed -n '/^4\. \*\*GitHub settings\*\* (every level)/,/^5\. /p' skills/init/SKILL.md | sed '$d')"
check "when init's step 4 is read, then it is for every level and offers allow_rebase_merge=false, and on lite allow_merge_commit=false" \
  '[[ -n "$init_gh" ]] && ! grep -q "(standard and full)" <<<"$init_gh" && grep -q "allow_rebase_merge=false" <<<"$init_gh" && grep -A3 "On lite" <<<"$init_gh" | grep -q "allow_merge_commit=false"'
check "then for a PUBLIC repo it offers secret scanning with push protection and private vulnerability reporting, and branch protection is step 5 (standard and full)" \
  'grep -q "PUBLIC" <<<"$init_gh" && grep -q "secret_scanning_push_protection" <<<"$init_gh" && grep -q "private-vulnerability-reporting" <<<"$init_gh" && grep -q "^5\. \*\*Branch protection\*\* (standard and full)" skills/init/SKILL.md'
check "when the docs are read, then the README CI row names (standard and full), the security doc says lite has no CI gate, and the design doc ties the one-revert promise to one commit per task PR" \
  'grep -E "^\| \*\*every PR, and weekly\*\* \|" README.md | grep -qF "(standard and full)" && grep -q "On lite there is no CI gate" docs/security.md && sed -n "/^## One task = one issue/,/^## /p" docs/design.md | grep -q "one commit per task PR"'

# Generated CI's first run: required jobs must have a way out, and a new advisory must not stop unrelated PRs.
init_bp="$(sed -n '/^5\. \*\*Branch protection\*\*/,/^6\. /p' skills/init/SKILL.md)"
check "when init's step 5 is read, then protection waits for green checks, and running init again offers it" \
  'tr "\n" " " <<<"$init_bp" | grep -qE "Offer it only once .*green" && grep -qF "gh run list --branch <base branch>" <<<"$init_bp" && tr "\n" " " <<<"$init_bp" | grep -qF "/landspec:init\` again"'
check "then the osv-scanner job is left out of the required checks, and the security doc says so" \
  'tr "\n" " " <<<"$init_bp" | grep -qE "Leave +\`Dependencies \(osv-scanner\)\` +out" && grep -qF "OSV-Scanner is not a required check" docs/security.md'
gate_doc="$(sed -n '/^## When a gate is red/,/^## /p' docs/security.md)"
check "when the security doc is read, then it says how to accept what each gate already finds" \
  'for f in .gitleaksignore osv-scanner.toml zizmor.yml .trivyignore .semgrepignore; do grep -qF "\`$f\`" <<<"$gate_doc"; done'
check "then the constitution template and adopt say to keep the placeholder when there is no such step" \
  'grep -q "keep its \[PLACEHOLDER\]" preset/templates/constitution-template.md && grep -q "leave its placeholder" skills/adopt/SKILL.md'

check "when init's summary is read, then it repeats a warning that a kept workflow never runs on task PRs, and the reference names it" \
  'grep -qF "never runs on a task PR" <<<"$(sed -n "/^7\. Summarize/,/^8\. /p" skills/init/SKILL.md)" && grep -qF "never runs on a task PR" docs/reference.md'

# The setup commit has to reach the base branch: task branches start there, and scripts read the level from the tree.
init_commit="$(sed -n '/^8\. \*\*Offer to commit it/,$p' skills/init/SKILL.md)"
check "when init's step 8 is read, then the setup branch starts from origin/<base> and the PR names that base, on yes and on no" \
  'grep -qF "git switch -c <branch> origin/<base>" <<<"$init_commit" && grep -qF "pr.sh fix \"chore: landspec <version> (level <level>)\" <body-file>" <<<"$init_commit" && grep -qF "opens it into \`<base>\`" <<<"$init_commit" && tr "\n" " " <<<"$init_commit" | grep -qE "On no: .*into +\`<base>\`" && grep -q "next promotion" <<<"$init_commit"'
check "when the level skill is read, then a level change goes to the base branch too" \
  'grep -qF "opens it into \`<base branch>\`" skills/level/SKILL.md'
check "when the level skill is read, then going up from lite offers merge commits on, and going down offers squash-only" \
  'grep -qF "allow_merge_commit=true" skills/level/SKILL.md && grep -qF "allow_merge_commit=false -F allow_squash_merge=true" skills/level/SKILL.md'
check "when the reference Update and level.sh are read, then marked files are re-created, so commit first or delete the marker" \
  'grep -qF "commit your edits to those first, or delete the marker" docs/reference.md && ! grep -qF "touches nothing else" docs/reference.md && grep -qF "commit edits first, or delete the marker" extension/scripts/level.sh && ! grep -qF "existing files are never overwritten" extension/scripts/level.sh'
check "when the review_model row is read, then it says the key is no longer read and the hook blocks a review launch on any model but opus" \
  'grep -qF "a review launch on any model but \`opus\`" docs/reference.md && grep "^| \`review_model\` |" docs/reference.md | grep -qF "no longer read"'
check "when the docs say what the scan proves, then it ran, never that it passed, and the review is the one fast pass" \
  'grep -qF "refuses the PR until \`security-scan.sh --changed\` ran" docs/security.md && grep -qF "the PR is refused until they ran" README.md && grep -qF "one fast pass on the diff" docs/security.md && ! grep -qF "one mutation" docs/security.md'
# FR-013/#258: the plan gate is a layer of the security model, with what it checks and how far it holds.
check "when the security layers table is read, then a Before a PR opens, with row names tfplan.sh gate and its Skipped line" \
  'grep -E "^\| Before a PR opens, with " docs/security.md | grep -F "tfplan.sh gate" | grep -qF "Skipped"'
check "when the example describes a [P] task, then it uses the parallel offer of next" \
  'grep -qF "\`next\` prints a \`parallel\` line" examples/README.md && ! grep -qF "claude --worktree" examples/README.md'
check "when the docs are read, then the README Start and the reference Update say the setup goes to the base branch" \
  'grep -q "base branch" <<<"$(sed -n "/^## Start/,/^## The loop/p" README.md)" && grep -q "base branch" <<<"$(sed -n "/^## Update/,/^## What/p" docs/reference.md)"'

# A new project needs a GitHub repo before the foundation spec, and develop after its first push.
new_landspec="$(sed -n '/^7\. \*\*Set up landspec/,$p' skills/new/SKILL.md)"
check "when new's steps 7 and 8 are read, then it offers gh repo create before setup, and the next step is commit, push and level, before the spec" \
  'tr "\n" " " <<<"$new_landspec" | grep -qE "gh repo create .*--source \. --remote origin.*bin/setup\.sh" && tr "\n" " " <<<"$new_landspec" | grep -qE "commit the setup.*git push -u origin.*/landspec:level <level>.*/speckit-specify"'
check "when init's step 1 is read, then it checks for a GitHub repository and offers to create one" \
  'grep -qE "gh repo view.*gh repo create .*--source \. --remote origin" <<<"$(sed -n "/^1\. \*\*Tools/,/^2\. /p" skills/init/SKILL.md | tr "\n" " ")"'

# review.sh record compares against the merge-base with origin's base (lib.sh base_ref): the prompt names the same one.
# Spec 004 T002: the reviewer runs detached in its own copy, so the facts' base: (the parent of a
# stacked branch, else origin/<base>) decides the diff, the risk map and Reviewed:, as record does.
check "the review prompt reads the facts' base: for the diff, the risk map and the Reviewed: range" \
  'f="$(tr "\n" " " < extension/commands/review.md | tr -s " ")"; [[ "$f" == *"\`base:\` the ref the branch is diffed against"* \
   && "$f" == *"review.sh risk \"\$(git merge-base HEAD <base>)\"\` with the facts'"'"' \`base:\`"* && "$f" == *"git diff <base>...HEAD"* \
   && "$f" == *"(\`git merge-base HEAD <base>\`, with the facts'"'"' \`base:\`"* ]] && ! grep -qF "origin/<base>...HEAD" extension/commands/review.md'
check "pr.md passes base: from base_ref" 'grep -qF "\`base:\` is" extension/commands/pr.md && grep -qF "base_ref" extension/commands/pr.md'

# FR-034: every review runs in the plugin's reviewer agent on a pinned strong model; FR-035: no fast-model checker.
check "when agents/reviewer.md is read, then it has name: reviewer, model: opus, effort: medium and no ## Method (review.md is the only copy)" \
  'grep -qx "name: reviewer" agents/reviewer.md && grep -qx "model: opus" agents/reviewer.md && grep -qx "effort: medium" agents/reviewer.md && ! grep -q "^## Method" agents/reviewer.md'
# Guard half (FR-035): it passes on main too, so it is never presented as failing-first.
check "then the plugin ships no fast-model checker agent and plugin.json has no agents key (the default scan finds agents/)" \
  '[[ ! -e agents/checker.md ]] && ! grep -q "\"agents\"" .claude-plugin/plugin.json'
check "when review.md, pr.md and issues.md launch the reviewer, then each names landspec:reviewer and pr.md and issues.md no longer launch a general-purpose subagent" \
  'grep -qF "landspec:reviewer" extension/commands/review.md && grep -qF "landspec:reviewer" extension/commands/pr.md && grep -qF "landspec:reviewer" extension/commands/issues.md \
   && ! tr "\n" " " < extension/commands/pr.md | grep -qE "general-purpose +subagent" && ! tr "\n" " " < extension/commands/issues.md | grep -qE "general-purpose +subagent"'
check "when review.md sets the reviewer model, then the call's model is opus, it names no review_model, and it keeps the general-purpose fallback and the sentinel line" \
  'f=extension/commands/review.md; grep -qF "call'"'"'s \`model\`: \`opus\`" $f && ! grep -qF "review_model" $f \
   && grep -qF "general-purpose" $f && grep -qF "landspec review: independent reviewer" $f'
# Spec 003 T001: every review runs in its own copy of the reviewed commit, never in the author's checkout.
check "when review.md, pr.md and issues.md launch the reviewer, then each passes isolation: \"worktree\"" \
  'for f in review pr issues; do grep -qF "isolation: \"worktree\"" extension/commands/$f.md || exit 1; done'
check "when review.md lists the facts and the reviewer's steps, then it has commit:, checkout:, the detach to <commit>, the agent-* step 0, the /landspec:init stop, never writing to <checkout> and the Copy: line" \
  'f=extension/commands/review.md; grep -qF "\`commit:\`" $f && grep -qF "\`checkout:\`" $f && grep -qF "git checkout --quiet --detach <commit>" $f \
   && grep -qF "be an \`agent-*\` folder directly under a \`.claude/worktrees/\`" $f && grep -qE "predates the plugin: run +/landspec:init" <<<"$(tr "\n" " " < $f)" \
   && grep -qF "Never write to \`<checkout>\`" $f && grep -qF "\`Copy: <git rev-parse --show-toplevel>\`" $f'
check "when agents/reviewer.md is read, then it has isolation: worktree, the agent-* step 0, the /landspec:init stop and never writing to the author's checkout" \
  'f=agents/reviewer.md; grep -qx "isolation: worktree" $f && grep -qF "be an \`agent-*\` folder directly under a \`.claude/worktrees/\`" $f \
   && grep -qF "predates the plugin: run /landspec:init" $f && grep -qF "never write to the author'"'"'s checkout" $f'
# Spec 003 T002: the reviewer follows personal data and secrets into the helpers that log them.
check "when a changed function fails differently, then review.md asks for every caller with how it handles the new failure, both kinds of fallback, and the delta takes those callers in" \
  'f="$(tr "\n" " " < extension/commands/review.md | tr -s " ")"; [[ "$f" == *"When a changed function fails differently (it raises where it returned, returns where it raised, or changes the error type or value it fails with), search for every caller of it, in the diff or not"* \
   && "$f" == *"give each one a \`- deep:\` line in the risk map saying how it handles the new failure"* && "$f" == *"a caller that catches the old error type, and one that checks \`not res.ok\` or a status code"* \
   && "$f" == *"A caller whose fallback no longer runs is a finding"* && "$f" == *"a fix commit that changes how a function fails makes every caller of that function part of the fix"* ]]'
check "when review.md is read, then step 3 tries to break each claim, the Claims lines come before the findings, the Findings rule tries to disprove, the plan review checks reuse and changed callers, and the report has one count line" \
  'f="$(tr "\n" " " < extension/commands/review.md | tr -s " ")"; r="$(sed -n "/^## Report/,\$p" extension/commands/review.md | tr "\n" " " | tr -s " ")"
   [[ "$f" == *"**Try to break it.**"* && "$f" == *"build one concrete counterexample"* && "$f" == *"follow each one'"'"'s own scenario through the fix"* \
   && "$f" == *"A plan review or a feature review skips this step"* && "$r" == *"after the risk map and before the findings"* \
   && "$r" == *"- held: <claim>"* && "$r" == *"- broke: <claim>"* && "$r" == *"try to disprove it"* && "$r" == *"exactly \`Findings: <n> high, <n> medium, <n> low\`"* \
   && "$f" == *"**Reuse:** a task that adds a helper"* && "$f" == *"every caller of a function whose behaviour it changes"* ]]'
# Feature 008 T018 (R13): the Assessment follows the gates, and a delta has no size limit.
check "when review.md's Report is read, then a plan review ends changes needed only with a High and a task review only with a High or Medium" \
  'r="$(sed -n "/^## Report/,\$p" extension/commands/review.md | tr "\n" " " | tr -s " ")"
   [[ "$r" == *"a plan review ends \`changes needed\` only with a High finding"* && "$r" == *"a task review (full or delta) only with a High or Medium"* ]]'
check "when review.md is read, then a delta has no 20-line limit and a conflict round's delta reads the merge's resolution" \
  'f="$(tr "\n" " " < extension/commands/review.md | tr -s " ")"; ! grep -qF "20 lines" extension/commands/review.md \
   && [[ "$f" == *"reads the merge'"'"'s resolution (\`git show --remerge-diff <merge>\`) and the commits after it"* ]]'
check "when review.md's delta is read, then a bug it notices outside its fix commits is not counted on the Findings: line" \
  'tr "\n" " " < extension/commands/review.md | tr -s " " | grep -qF "is reported at its true severity, is not counted on the \`Findings:\` line and does not change the assessment"'
check "when review.md's plan review is read, then only a High failing row or open earlier finding blocks a ready" \
  'f="$(tr "\n" " " < extension/commands/review.md | tr -s " ")"; [[ "$f" == *"refuses a \`ready\` with a failing row only when the report counts a High finding"* \
   && "$f" == *"and a \`ready\` with an \`open\` row only when it counts a High finding"* ]]'
check "when the Impact rule is read, then the tasks template and issues step 1 also search what a task changes the behaviour of" \
  'grep -qF "changes the behaviour of" extension/commands/issues.md && tr "\n" " " < preset/templates/tasks-template.md | tr -s " " | grep -qF "removes or changes the behaviour of"'
check "when review.md lists the bugs to look for, then it names data reaching a log inside a helper, says to open each helper, and ranks a faked asserted component" \
  'f="$(tr "\n" " " < extension/commands/review.md | tr -s " ")"; [[ "$f" == *"reaches a log, including inside a helper the changed lines call with it"* \
   && "$f" == *"Open each helper a changed line passes personal data or a secret to"* && "$f" == *"names the helper'"'"'s own \`file:line\` that writes the log"* && "$f" == *"a test that fakes the component whose behavior it asserts"* \
   && "$f" == *"is **Medium** when it is the only proof of a privacy or security rule"* && "$f" == *"Personal data in a log is **High** when the project'"'"'s rules forbid it"* ]]'
check "when docs/reference.md is read, then the Configuration table has a review_model row, and it says CLAUDE_CODE_SUBAGENT_MODEL_FORCE overrides it and the hook exists only where the plugin is installed" \
  'grep -q "^| \`review_model\` |" docs/reference.md && grep -qF "CLAUDE_CODE_SUBAGENT_MODEL_FORCE" docs/reference.md && grep -qi "only where the plugin is installed" docs/reference.md'
# FR-001/FR-008: the passes review.md asks for are the ones review.sh checks, in the same order, and its Report names them.
md_passes="$(grep -oE '^\*\*Pass `[a-z]+`\*\*' extension/commands/review.md | sed -E 's/.*`(.*)`.*/\1/' | tr '\n' ' ')"
sh_passes="$(sed -n 's/^PASSES="\(.*\)"$/\1/p' extension/scripts/review.sh)"
check "when review.md's **Pass \`<name>\`** paragraphs and review.sh's PASSES are read, then they name the same eight passes in the same order, as the Report's plan report does" \
  '[[ "$md_passes" == "$sh_passes " && "$(wc -w <<<"$sh_passes")" -eq 8 ]] \
   && [[ "$(sed -n "/^- \*\*A plan report\*\*/,/^- Before/p" extension/commands/review.md | grep -oE "\`[a-z]+\`" | tr -d "\`" | tr "\n" " ")" == "$sh_passes " ]]'
# Issue #108: the plan review reads spec-folder code and orderings; #221: every round is read cold.
check "when the plan review and issues step 2 are read, then spec-folder code gets the bug list, each state machine's orderings meet one invariant, and every round is read cold with an Earlier findings table" \
  'r="$(tr "\n" " " < extension/commands/review.md)"; i="$(tr "\n" " " < extension/commands/issues.md)"
   [[ "$r" == *"**Spec-folder code:** every file under \`specs/NNN-*/\` that is not markdown is code"* && "$r" == *"script that hides an error"* \
   && "$r" == *"**Orderings:** for each state machine in"* && "$r" == *"out of order, delivered twice, the original event replayed, opposite actions both pending"* \
   && "$r" == *"never narrows the review"* && "$r" == *"under a heading exactly \`### Earlier findings\`"* \
   && "$i" == *"Every round is read cold"* && "$i" != *"same class"* && "$i" != *"once per class"* \
   && "$(tr "\n" " " < skills/implement/SKILL.md | tr -s " ")" == *"every round is read cold"* ]]'
# FR-004 (#221): the plan review's facts never carry the author's answers to the findings.
plan_facts="$(awk '/^- for a plan review:/ { on = 1; print; next } on && /^(- |$)/ { exit } on' extension/commands/review.md)"
check "when review.md's plan-review facts are read, then they pass review.sh diff --plan and never mention an answer" \
  '[[ "$plan_facts" == *"review.sh diff --plan"* && "$(tr A-Z a-z <<<"$plan_facts")" != *answer* ]]'
# The section is read into a variable: a pipe into grep -q can fail under pipefail (SIGPIPE on sed).
sec_readme="$(sed -n "/^## Security, built in/,/^## Levels/p" README.md)"
check "when the README's Security, built in table is read, then it names the reviewer's model" \
  '[[ "$sec_readme" == *"landspec:reviewer"* && "$sec_readme" == *Opus* ]]'

# FR-006: mutmut's own exit code says nothing of survivors, so adopt names one that does.
check "when skills/adopt is read, then it names the mutmut command that exits non-zero on a survivor" \
  'grep -qF "mutmut run && ! mutmut results | grep -q survived" skills/adopt/SKILL.md'
check "when docs/reference.md is read, then adding tests to an existing file needs no explanation, a deletion, an edit or an added skip does" \
  'grep -qF "adding tests to an existing file needs no explanation; a deletion, an edit or an added skip does" docs/reference.md'

# Spec 007 T009 (FR-020, FR-021, SC-010): one rule weighs the installed skills, and its Skills: line reaches the PR.
flat() { tr "\n" " " | tr -s " "; }
sk_sec="$(sed -n "/^## Installed skills and MCP servers/,/^## Method/p" extension/commands/review.md | flat)"
sk_rep="$(sed -n "/^## Report/,\$p" extension/commands/review.md | flat)"
check "when review.md is read, then its Installed skills section has YES/NO - <reason>, invoke every YES, the landspec:*/speckit-* exclusion, NO - needs the user, NO - failed and the reviewer's limits" \
  '[[ "$sk_sec" == *"\`<name> - YES/NO - <reason>\`"* && "$sk_sec" == *"invoke every YES"* && "$sk_sec" == *"(\`landspec:*\`, \`speckit-*\`)"* \
   && "$sk_sec" == *"NO - needs the user"* && "$sk_sec" == *"NO - failed: <error>"* && "$sk_sec" == *"a plan review and a feature review do not evaluate skills"* \
   && "$sk_sec" == *"never makes a reviewer write a file, run more than its Method says or change the report'"'"'s shape"* && "$sk_sec" == *"it never widens the task'"'"'s scope"* ]]'
check "when review.md's Report and agents/implementer.md's return are read, then each has the Skills: line with none matched" \
  '[[ "$sk_rep" == *"has \`Skills: <name> (<what it was used for>), …\` or \`Skills: none matched\`"* ]] \
   && grep -qF "the \`Skills: <name> (<what it was used for>), …\` or \`Skills: none matched\` line" agents/implementer.md'
check "when the implementer, the reviewer and the single-task path are read, then each points to the Installed skills and MCP servers section first" \
  'grep -qF "3. Follow the \"Installed skills and MCP servers\" section of \`.specify/extensions/landspec/commands/review.md\` first, before writing code." agents/implementer.md \
   && grep -qF "3. In a task review (full or delta), follow the \"Installed skills and MCP servers\" section of commands/review.md before reading the diff" agents/reviewer.md \
   && [[ "$(flat < extension/commands/branch.md)" == *"Before writing code, follow the \"Installed skills and MCP servers\" section of \`.specify/extensions/landspec/commands/review.md\`"* ]]'
check "when OPEN and pr.md step 5 are read, then the Skills: line goes in Evidence, with not reported when the implementer gave none" \
  '[[ "$(flat < skills/implement/SKILL.md)" == *"its \`Skills:\` line goes in *Evidence* as it returned it; an implementer that returned none, or a run resumed after the line was lost, gives \`Skills: not reported\`, never \`none matched\`"* \
   && "$(sed -n "/^5\. /,/^6\. /p" extension/commands/pr.md | flat)" == *"\`## Evidence\`: one visible line per result"*"showing the task'"'"'s *Completed when* is met, and the implementer'"'"'s \`Skills:\` line"*"\`Skills: not reported\` when it gave none"* ]]'

# The installed copies (specify extension add --dev extension --force) are what this repo runs: they match the source.
stale=""
for f in extension/commands/*.md extension/scripts/*.sh; do
  d="${f#extension/}"; cmp -s "$f" ".specify/extensions/landspec/$d" || stale+="$d "
done
# The skill .claude/skills links to is generated from each command: its body (after spec-kit's frontmatter) is the command's.
body() { awk 'n >= 2 { print } /^---$/ { n++ }' "$1"; }
for f in extension/commands/*.md; do
  s=".specify-dev/agent-commands/claude/speckit-landspec-$(basename "$f" .md)/SKILL.md"
  [[ -f ".specify/extensions/landspec/$s" && "$(body "$f")" == "$(body ".specify/extensions/landspec/$s")" ]] || stale+="$s "
done
check "every extension command and script equals its .specify/extensions/landspec copy${stale:+ — stale: $stale(fix: specify extension add --dev extension --force)}" '[[ -z "$stale" ]]'

# A link copied from the README into docs/ keeps its docs/ prefix and breaks; every relative link
# in a markdown file must point at a file that exists next to it.
broken=""
while IFS=: read -r f target; do
  [[ -e "$(dirname "$f")/${target%%#*}" ]] || broken+="$f -> $target "
done < <(grep -oE '\]\([^)#:]+(\.md|\.yaml|\.yml)(#[^)]*)?\)' README.md docs/*.md examples/README.md | sed -E 's/\]\(//; s/\)$//')
check "every relative link in the docs points at a file that exists${broken:+ — broken: $broken}" '[[ -z "$broken" ]]'

refs=docs/references.yaml
check "every reference has a title, url, use_when and key" \
  '[[ $(grep -c "^ *- title: " $refs) -gt 0 && $(grep -c "^ *- title: " $refs) == $(grep -c "^ *url: https://" $refs) && $(grep -c "^ *- title: " $refs) == $(grep -c "^ *use_when: " $refs) && $(grep -c "^ *- title: " $refs) == $(grep -c "^ *key: " $refs) ]]'
check "then no reference is listed twice" '[[ -z "$(grep -oE "url: \S+" $refs | sort | uniq -d)" ]]'
check "then no reference is Wikipedia (primary sources only)" '! grep -q "wikipedia.org" $refs'

# FR-025: the three version files move together.
v_plugin="$(sed -nE 's/^ *"version": *"([^"]+)".*/\1/p' .claude-plugin/plugin.json | head -1)"
v_ext="$(sed -nE 's/^  version: *"([^"]+)".*/\1/p' extension/extension.yml | head -1)"
v_preset="$(sed -nE 's/^  version: *"([^"]+)".*/\1/p' preset/preset.yml | head -1)"
check "when the plugin, extension and preset versions are read, then they are equal ($v_plugin, $v_ext, $v_preset)" \
  '[[ -n "$v_plugin" && "$v_plugin" == "$v_ext" && "$v_plugin" == "$v_preset" ]]'
# FR-025: the release notes have a table row for every finding feature 002 fixed (a reader finds each id's change).
notes="docs/releases/$v_plugin.md"; missing=""
if [[ "$v_plugin" == 1.8.0 ]]; then
  for id in F1.1 F1.2 F1.6 F1.7 F1.8 F1.9 F2.3 F2.4 F3.1 F3.3 F3.4 F3.5 F3.6 F3.7 F3.8 F3.9 F4.1 F4.2 F4.3 F4.4 F4.5 F4.7 F5.2 F5.3 F5.4 F5.6 "#41"; do
    grep -qF -- "| $id |" "$notes" 2>/dev/null || missing+="$id "
  done
  check "when docs/releases/1.8.0.md is read, then it has a row for every fixed id${missing:+ — missing: $missing}" '[[ -f "$notes" && -z "$missing" ]]'
  check "then Upgrading names claude plugin update and no longer says changed files are kept" \
    'grep -qF "claude plugin update" "$notes" && ! grep -qF "are kept when you changed them" "$notes"'
  check "then the notes list T013 to T021" \
    'for n in 13 14 15 16 17 18 19 20 21; do grep -q "^| T0$n |" "$notes" || exit 1; done'
fi

# /landspec:implement (spec 004 T006): the loop's steps, the order around the PR, and the implementer's rules.
im="$(cat skills/implement/SKILL.md)"; ag="$(cat agents/implementer.md)"
check "when /landspec:implement launches an implementer, then it uses landspec:implementer with isolation worktree, in the background" \
  'grep -qF "subagent_type: \"landspec:implementer\"" <<<"$im" && grep -qF "isolation: \"worktree\"" <<<"$im" && grep -qF "run_in_background: true" <<<"$im"'
check "then each pass runs restack, then status with --running, and reviews against base: <base_ref <branch>>" \
  'grep -qF "I restack" <<<"$im" && grep -qF "I status --running" <<<"$im" && grep -qF "base: <base_ref <branch>>" <<<"$im"'
check "then it has a step for each of START, REVIEW, FIX and OPEN, and reads ORDER=" \
  'for k in START REVIEW FIX OPEN; do grep -qF "**\`$k\`**" <<<"$im" || exit 1; done; grep -qF "ORDER=" <<<"$im"'
check "then a task under review is in flight, so a second reviewer never starts on it, and the run waits for reviewers too" \
  'r="$(sed -n "/\*\*\`REVIEW\`\*\*/,/\*\*\`FIX\`\*\*/p" <<<"$im")"; grep -qF "Add the task to \`in flight\`" <<<"$r" && grep -qF "remove it from \`in flight\`" <<<"$r" && grep -qF "no implementer and no reviewer" <<<"$im"'
check "then a fix round reads the review from the <task>.report file, is reviewed as a delta, and falls back to a full review when the delta refuses" \
  'r="$(sed -n "/\*\*\`REVIEW\`\*\*/,/\*\*\`FIX\`\*\*/p" <<<"$im" | tr "\n" " " | tr -s " ")"; grep -qF "landspec-run/<feature dir name>/<task>.report" <<<"$im" \
   && grep -qF "\`review.sh record --delta --branch <branch> <report>\`" <<<"$r" && grep -qF "When \`record --delta\` refuses" <<<"$r" && grep -qF "run a full review instead and record it with \`review.sh record --branch\`" <<<"$r" && ! grep -qF "never \`--delta\`" <<<"$im"'
check "then OPEN runs the scan and mutation testing only when this diff has no record of them" \
  'o="$(sed -n "/\*\*\`OPEN\`\*\*/,/^4\. /p" <<<"$im" | tr "\n" " " | tr -s " ")"; grep -qF "only when this diff has no record of them" <<<"$o" && grep -qF "diff_record" <<<"$o" && grep -qF "landspec-security" <<<"$o" && grep -qF "landspec-mutants" <<<"$o"'
check "then every return that is not done leaves in flight, and one that returns nothing is marked red, failed at RED=2 or with no branch" \
  'r="$(sed -n "/^Otherwise:/,/^## End/p" <<<"$im" | tr "\n" " " | tr -s " ")"; [[ "$(grep -o "remove it from \`in flight\`" <<<"$r" | wc -l)" -eq 4 ]] \
   && grep -qF "It returned none of these" <<<"$r" && grep -qF "With a branch, \`I mark <task> red\`: at \`RED=2\`, \`I fail <task> \"implementer returned nothing\"\`" <<<"$r" && grep -qF "With no branch, \`I fail <task> \"implementer returned nothing\"\` at once" <<<"$r"'
check "when the implementer works, then it reads the test rules and Method step 2 it is held to, and runs the scan and mutants before it detaches" \
  'grep -qF "\"Tests are evidence\" rules of \`.specify/extensions/landspec/commands/pr.md\` step 2" <<<"$ag" && grep -qF "step 2 of the Method in \`.specify/extensions/landspec/commands/review.md\`" <<<"$ag" \
   && [[ "$(grep -n "security-scan.sh --changed\` and \`bash .specify/extensions/landspec/scripts/mutants.sh\`" <<<"$ag" | cut -d: -f1)" -lt "$(grep -n "Last, \`git switch --detach\`" <<<"$ag" | cut -d: -f1)" ]] \
   && grep -qF "the last \`security-scan.sh\` and \`mutants.sh\` result lines" <<<"$ag"'
check "when pr.md records the review, then it records the file the reviewer names, never a saved copy" \
  '! grep -qF "Save the report as it came" extension/commands/pr.md && grep -qF "Record the file the reviewer names on its report'"'"'s first line (\`Report file: <path>\`), as it" extension/commands/pr.md'
check "when pr.md runs step 4, then the scan comes before the reviewer, mutants after /security-review, and a test-only commit after ready gets a delta" \
  's4="$(sed -n "/^4\. /,/^5\. /p" extension/commands/pr.md | tr "\n" " " | tr -s " ")"; [[ "$s4" =~ security-scan\.sh\ --changed.*Then\ launch\ the\ reviewer.*run\ \`/security-review\`\ on\ the\ branch,\ then.*mutation\ testing.*mutants\.sh ]] \
   && grep -qF "never both at once in this tree" <<<"$s4" && grep -qF "A commit that only adds tests (killing a survivor) after a \`ready\` review is checked with a delta." <<<"$s4" && grep -qF "after any later commit (a fix round'"'"'s too), run both again" <<<"$s4"'
check "when pr.md runs mutants while the reviewer runs, then it waits for mutants.sh before it records, edits or re-runs step 2" \
  's4="$(sed -n "/^4\. /,/^5\. /p" extension/commands/pr.md | tr "\n" " " | tr -s " ")"; [[ "$s4" =~ Wait\ for\ \`mutants\.sh\`\ to\ finish\ before\ you\ record\ the\ review,\ edit\ any\ file\ or\ re-run\ step\ 2.*Record\ the\ file\ the\ reviewer\ names ]]'
check "then a returning implementer's tests run first in its copy: green marks it implemented, red marks it red, failed at RED=2" \
  'r="$(sed -n "/^## When an implementer returns/,/^## End/p" <<<"$im")"; grep -qF "run the project'"'"'s test command before anything else" <<<"$r" \
   && grep -qF "green: \`I mark <task> implemented\`" <<<"$r" && grep -qF "red: \`I mark <task> red\`. At \`RED=2\`" <<<"$r" && grep -qF "\`I fail <task> \"tests red twice\"\`" <<<"$r"'
check "then only implementers take parallel_tasks slots (status --running), while every task in flight is kept from restack" \
  'grep -qF "\`I status --running <the implementers in flight, comma separated>\`" <<<"$im" && grep -qF "\`I restack --running <every task in flight, implementers and reviewers, comma separated>\`" <<<"$im" \
   && grep -qF "reviewers take no slot" docs/reference.md'
check "then a listed task already in flight is skipped, so a task under review never gets a second reviewer" \
  'grep -qF "skipping any task that is in \`in flight\`" <<<"$im"'
check "then red once goes back to its implementer with the test output, not through FIX's review report" \
  'r="$(sed -n "/^## When an implementer returns/,/^## End/p" <<<"$im")"; grep -qF "At \`RED=1\`, SendMessage its" <<<"$r" && grep -qF "with that output. It stays in flight." <<<"$r"'
check "then the PR step switches to the branch first, runs gh pr ready after pr.sh task on a draft that targets the base, and detaches last" \
  'o="$(sed -n "/\*\*\`OPEN\`\*\*/,/^4\. /p" <<<"$im" | tr "\n" " ")"; [[ "$o" =~ git\ switch\ \<branch\>.*pr\.sh\ task.*gh\ pr\ ready.*git\ switch\ +--detach ]] && grep -qF "never while \`landspec-parent\` is set" <<<"$o"'
check "then nothing in the skill or the implementer merges a PR" '! grep -qF "gh pr merge" skills/implement/SKILL.md agents/implementer.md'
# Spec 007 T011: the hand-over rule (FR-025) and Copilot's comments (FR-024) in every hand-over step.
handover_ok() {
  # 250, not more: RE_DUP_MAX is 255 in musl, the libc of the busybox CI job, so a larger bound fails to compile.
  local t re='pr\.sh state <pr>`.{0,250}`CONFLICT=no` and `COPILOT=` `none`, `clean` or `unavailable`'
  t="$(flat < "$1")"; [[ "$t" =~ $re && "$t" == *'"CI still running"'* ]]
}
for f in skills/implement/SKILL.md extension/commands/pr.md extension/commands/branch.md extension/commands/issues.md; do
  check "when $f hands a PR over, then it runs pr.sh state and the CONFLICT=no / COPILOT= rule, with CI still running shown" "handover_ok $f"
done
check "when the implement End lists PRs, then each is [#N](<url>) and one waiting for Copilot is listed apart" \
  'grep -qF "\`[#N](<url>)\`" <<<"$im" && grep -qF "\"waiting for Copilot'"'"'s review\"" <<<"$im"'
check "when Copilot's threads are answered, then the implement skill, branch.md and issues.md reply with a file and resolve RESOLVE= ones with none" \
  'i="$(flat < skills/implement/SKILL.md)"; b="$(flat < extension/commands/branch.md)"; s="$(flat < extension/commands/issues.md)"
   [[ "$i" == *"\`pr.sh state <pr> --reply <thread id> <file>\`"* && "$i" == *"\`pr.sh state <pr> --reply <thread>\`, with no file"* \
   && "$b" == *"\`pr.sh state <pr> --reply <thread id> <file>\`"* && "$b" == *"\`pr.sh state <pr> --reply <thread id>\` with no file"* \
   && "$s" == *"\`pr.sh state <spec PR> --reply <thread id> <file>\`"* && "$s" == *"\`--reply <thread id>\` with no file"* ]]'
check "when the implementer has a Copilot fix round, then it returns one Answer: <thread id> line per thread, fixed or not a defect" \
  'grep -qF "\`Answer: <thread id> fixed in <sha>\` or \`Answer: <thread id> not a defect: <reason>\` line per thread" <<<"$ag"'
check "when a hook rewrites files outside the task, then the implementer returns the Failed: formatter line (FR-017)" \
  'grep -qF "return \`Failed: formatter <hook> rewrote <n> files outside the task'"'"'s change: run /landspec:adopt, or format the code in its own PR first\` and stop" <<<"$ag"'
check "then a missing Copy: is recreated detached beside the repository" 'grep -qF "git worktree add --detach <repo>-<feature>-<task> <branch>" <<<"$im"'
check "then a fix round without SendMessage launches a new implementer on the branch" 'grep -qF "if SendMessage is not available, or the" <<<"$im" && grep -qF "launch a new implementer as in \`START\`, on the existing branch" <<<"$im"'
check "then a failed worktree_setup fails the task with its output" 'grep -qF "I fail <task> \"worktree_setup: <its output>\"" <<<"$im"'
check "then branch.sh exit 3 makes the task elsewhere and the next one starts" 'grep -qF "\`branch.sh\` exit 3" <<<"$im" && grep -qF "the task is \`elsewhere\`" <<<"$im"'
check "then no \"not built yet\" line is left: the gaps are filed" '! grep -qF "not built yet" skills/implement/SKILL.md'
gp="$(sed -n "/^5\. \*\*The gaps\*\*/,/^## /p" skills/implement/SKILL.md)"
check "then each not met becomes a task through pr.sh spec, in the run worktree, which is detached last" \
  'grep -qF "<repo>-<feature>-run" <<<"$gp" && grep -qF "pr.sh spec" <<<"$gp" && grep -qF "issues.sh" <<<"$gp" && grep -qF "review.sh record --plan" <<<"$gp" \
   && [[ "$(grep -n "pr.sh spec" <<<"$gp" | head -1 | cut -d: -f1)" -lt "$(grep -n "git switch --detach\` there, last" <<<"$gp" | cut -d: -f1)" ]]'
check "then a spec branch checked out elsewhere is SKIPPED=, and the check never runs with an open spec PR" \
  'grep -qF "SKIPPED=spec/<feature dir name> (checked out in <path>)" <<<"$gp" && grep -qF "SPEC_PR=<url>" <<<"$im" && grep -qF "skip the" <<<"$im"'
check "then, when gaps were filed, the report ends with the merge … then run again line" \
  'grep -qF "Last line, when gaps were filed: \`merge the PRs in ORDER and <spec PR>, then run /landspec:implement" <<<"$im"'
check "when issues.md ends, then step 6 names /landspec:implement for the whole feature" \
  'grep -qF "merge it, then run \`/landspec:implement\`" extension/commands/issues.md'
check "when next.sh prints RUN=, then the next skill offers /landspec:implement" \
  'grep -qF "If it printed \`RUN=/landspec:implement <feature>\`" skills/next/SKILL.md && grep -qF "/landspec:implement" <<<"$(sed -n 3p skills/next/SKILL.md)"'
rv="$(cat extension/commands/review.md)"
check "when review.md describes the feature review, then it has the three line kinds and record --feature" \
  'for k in "- met: " "- not met: " "- not verifiable: "; do grep -qF -- "$k" <<<"$rv" || exit 1; done; grep -qF "record --feature <file>" <<<"$rv" && grep -qF "only when no line is \`not met\`" <<<"$rv"'
check "then /landspec:implement checks the feature: check-copy, a conflict stacked with stack, the test, check-result, the feature review, --remove" \
  'grep -qF "I check-copy" <<<"$im" && grep -qF "I stack <task> <earlier task>" <<<"$im" && grep -qF "I check-result red" <<<"$im" && grep -qF "review.sh record --feature <report>" <<<"$im" && grep -qF "I check-copy --remove" <<<"$im"'
check "then it stops and asks on UNCHANGED= and ROUNDS_EXHAUSTED=, and waits for an open spec PR" \
  'grep -qF "\`UNCHANGED=<n>\`" <<<"$im" && grep -qF "\`ROUNDS_EXHAUSTED=<n>\`" <<<"$im" && grep -qF "Either way, stop, and ask the developer" <<<"$im" && grep -qF "merge <url> first" <<<"$im"'
check "then the reference documents feature_rounds" 'grep -q "^| \`feature_rounds\` | \`3\` |" docs/reference.md'
check "then it reads implement_model and refuses any model but sonnet, opus or fable" 'grep -qF "implement_model must be sonnet, opus or" <<<"$im"'
check "when agents/implementer.md is read, then it is named implementer, isolated in a worktree, never git add -A, and detaches last" \
  'grep -qx "name: implementer" agents/implementer.md && grep -qx "isolation: worktree" agents/implementer.md && grep -qF "never \`git add -A\`" <<<"$ag" \
   && grep -qF "Last, \`git switch --detach\`" <<<"$ag" && grep -qF "branch.sh <feature> <task> [--from <parent>]\`, first" <<<"$ag"'
check "then it runs worktree_setup, stays in its copy, and returns Copy: and BRANCH=" \
  'grep -qF "worktree_setup:" <<<"$ag" && grep -qF "never touch a path outside it" <<<"$ag" && grep -qF "\`Copy: <git rev-parse --show-toplevel>\` and \`BRANCH=<branch>\`" <<<"$ag"'
check "then without worktree_setup it prepares its own copy from the README, and returns Failed: setup: when the tests still cannot run" \
  'grep -qF "When it is not set, prepare your copy as the project'"'"'s README says" <<<"$ag" && grep -qF "in your copy only, never in the developer'"'"'s checkout" <<<"$ag" \
   && grep -qF "return \`Failed: setup: <what is missing>\` and stop" <<<"$ag"'
check "then README, help and the reference list /landspec:implement, worktree_setup and implement_model" \
  'grep -qF "/landspec:implement" README.md && grep -qF "\`implement\`" skills/help/SKILL.md && grep -q "^| \`worktree_setup\` |" docs/reference.md && grep -q "^| \`implement_model\` |" docs/reference.md'

# Only the repository's own PRs count: a fork's PR may reuse any branch name or title.
check "when a script lists PRs, then every gh pr list keeps only PRs from this repository" \
  'c="$(cat extension/scripts/*.sh)"; n="$(grep -o "gh pr list" <<<"$c" | wc -l)"; k="$(grep -oF "select(.isCrossRepository | not)" <<<"$c" | wc -l)"; [[ $n -ge 9 && $n -eq $k ]]'

# /landspec:implement's release (spec 004 T009): one step per RELEASE= line, and it never merges.
rl="$(sed -n "/^## The release/,/^## When an implementer returns/p" skills/implement/SKILL.md)"
check "when the skill makes the release, then it acts on the one RELEASE= line, for each of bump, tag, publish, pending, done and none" \
  'grep -qF "I release-plan" <<<"$rl" && grep -qF "act on the **one** \`RELEASE=\` line it prints, never on anything else" <<<"$rl" \
   && for k in bump tag publish pending done none; do grep -qF -- "- \`RELEASE=$k" <<<"$rl" || exit 1; done'
check "then the bump goes through pr.sh fix in the run worktree, which is detached after" \
  'grep -qF "<repo>-<feature>-run" <<<"$rl" && grep -qF "pr.sh fix \"chore(release): X.Y.Z\"" <<<"$rl" && grep -qF "git switch --detach origin/<base>\` there" <<<"$rl"'
check "then publish reads the notes from the base, or from the release PR's body cut at the first ## Evidence or ## Review, never --generate-notes" \
  'grep -qF "git show origin/<base>:<path>" <<<"$rl" && grep -qF "gh pr view <n> --json body -q .body" <<<"$rl" \
   && grep -qF "before the first line that is exactly \`## Evidence\` or \`## Review\`, whichever comes first" <<<"$rl" && grep -qF "stop and say the release PR has no notes" <<<"$rl" \
   && grep -qF "put the notes first in the release PR'"'"'s body, before its" <<<"$rl" && ! grep -qF -- "--generate-notes" <<<"$rl"'
check "then nothing in the skill merges a PR" '! grep -qF "gh pr merge" skills/implement/SKILL.md'
check "then landspec's own config names its four version files and docs/releases" \
  'c=.specify/extensions/landspec/landspec-config.yml; for f in .claude-plugin/plugin.json extension/extension.yml preset/preset.yml .specify/extensions/landspec/extension.yml; do grep "^version_files:" $c | grep -qF "$f" || exit 1; done; grep -qx "release_notes: docs/releases" $c'

# The run report (spec 004 T013): why a task waits, and how to free a locked worktree.
check "when the run ends, then the report gives each waiting task's reason and the unlock and remove commands for a locked worktree" \
  'e="$(sed -n "/^## End/,\$p" skills/implement/SKILL.md)"; grep -qF "each \`waiting\` task with its \`REASON=\`" <<<"$e" && grep -qF "\`git worktree unlock <path>\`, then \`git worktree remove <path>\`" <<<"$e"'

# The audit before the release (spec 004 T010): once per base commit, unattended, holding on a confirmed critical or high.
au="$(sed -n "/^## The audit before the bump/,/^## When an implementer returns/p" skills/implement/SKILL.md)"
check "when the skill reaches a bump, then it acts on the one AUDIT= line, for needed, done and hold" \
  'grep -qF "On \`RELEASE=bump\` and on \`RELEASE=none\`, once the whole-feature check on the base passed and before anything else" <<<"$au" && [[ "$(grep -cF "then the audit (below); only on \`AUDIT=done\`" skills/implement/SKILL.md)" == 2 ]] && grep -qF "I audit-plan" <<<"$au" && grep -qF "I audit-record <sha> <file> <n>" <<<"$au" \
   && for k in needed done hold; do grep -qF -- "- \`AUDIT=$k" <<<"$au" || exit 1; done'
check "then a hold files and posts nothing and the last line names /landspec:security with the report" \
  'grep -qF "nothing filed or posted about the findings" <<<"$au" && grep -qF "release held: <n> confirmed critical or high; run /landspec:security" skills/implement/SKILL.md'
check "then the main session runs /code-review high and /security-review for the audit, and the unattended audit takes them from its prompt and names a missing one" \
  'grep -qF "There the main session runs \`/code-review high\` and \`/security-review\`" <<<"$au" && grep -qF "one that is not available here gets a file saying so" <<<"$au" \
   && grep -qF "the \`/code-review high\` and \`/security-review\` output from the files the prompt names" skills/security/SKILL.md \
   && grep -qF "is named in the report'"'"'s coverage, as a" skills/security/SKILL.md && grep -qF "\`confirmed\` or \`plausible\`;" skills/security/SKILL.md'
check "then with HOLD=0 the notes get Known issues by visibility, counts only on a public repository, never an exploit detail" \
  'grep -qF "\"Known issues\" section from the report" <<<"$au" && grep -qF "gh repo view --json visibility -q" <<<"$au" && grep -qF "a failed call stops the release here" <<<"$au" \
   && grep -qF "on a \`PUBLIC\` one, only a count per severity" <<<"$au" && grep -qF "on a private or internal one, each" <<<"$au" \
   && grep -qF "confirmed medium or low and each plausible finding, with its title and category" <<<"$au" && grep -qF "the title" <<<"$au" && grep -qF "rewritten if it carries more than what is affected. Never an exploit detail" <<<"$au" && grep -qF "<code-review file>" <<<"$au" && grep -qF "<security-review file>" <<<"$au" \
   && grep -qF "\"Known issues\" of the audit (below)" skills/implement/SKILL.md'
check "then the run report names the missing scanners, which do not hold the release" \
  'e="$(sed -n "/^## End/,\$p" skills/implement/SKILL.md)"; grep -qF "report'"'"'s coverage names as missing (they do not hold the release" <<<"$e"'
check "then /landspec:security has the unattended mode (steps 1 to 6, HOLD=) and takes a report for step 7" \
  'grep -qF "**Unattended**" skills/security/SKILL.md && grep -qF "steps 1 to 6 only" skills/security/SKILL.md && grep -qF "\`HOLD=<n>\`" skills/security/SKILL.md \
   && grep -qF "Read it, show its summary as step 6 says, then step 7" skills/security/SKILL.md'
check "then /landspec:next and README point to /landspec:implement once every task is merged, never to /speckit-converge" \
  'grep -qF "it checks the whole feature on the base against the spec" skills/next/SKILL.md && grep -qF "audits the base and makes the release" skills/next/SKILL.md \
   && grep -qF "however the tasks were done: it checks the" README.md && grep -qF "audits the base" README.md \
   && ! grep -qF "speckit-converge" skills/next/SKILL.md && ! grep -qF "/speckit-converge" README.md'
check "then, with every task merged, the base is checked only on RELEASE=bump or none, and a red run is a gap task with no release" \
  'grep -qF "only from \"The release\" below: after" <<<"$im" && grep -qF "on \`RELEASE=bump\` or \`RELEASE=none\`, never on \`pending\`, \`tag\`, \`publish\` or \`done\`" <<<"$im" \
   && grep -qF "there is no task branch to fix:" <<<"$im" && grep -qF "the failing test becomes a gap task (step 5), and there is no release" <<<"$im" \
   && grep -qF "first the whole-feature check on the base (above): go on" <<<"$im" && grep -qF "\`CHECKED=<sha>\`" <<<"$im" && grep -qF "\`base: <FROM>\`" <<<"$im"'

# /landspec:report: public issues, so nothing is filed without a yes and nothing private leaves the project.
rp="$(cat skills/report/SKILL.md)"
check "when /landspec:report drafts an issue, then it files on the plugin's repository only after a yes" \
  'grep -qF "plugin.json" <<<"$rp" && grep -qF "never file without a yes" <<<"$rp" && grep -qF "gh issue create -R <repo>" <<<"$rp"'
check "then it keeps the project private and checks duplicates first" \
  'grep -qF "Keep the project private" <<<"$rp" && grep -qF "gh issue list -R <repo> --state all" <<<"$rp"'
check "then README and help list it" 'grep -qF "/landspec:report" README.md && grep -qF "\`report\`" skills/help/SKILL.md'

# The AWS agent role (contracts/template.md). Read with awk, so the bash 3.2 job (no python3) runs it too.
role=extension/aws/agent-role.yaml
if python3 -c "import yaml" 2>/dev/null; then
  check "when agent-role.yaml is parsed, then it is plain YAML with the four parameters and their defaults" \
    'python3 -c "import sys, yaml; p = yaml.safe_load(open(sys.argv[1]))[\"Parameters\"]; sys.exit(0 if {k: v.get(\"Default\") for k, v in p.items()} == {\"RoleName\": \"landspec-agent\", \"Access\": \"read\", \"TrustMode\": \"sso\", \"PermissionSetName\": \"\"} else 1)" '"$role"
else
  check "when agent-role.yaml is read, then no value starts with a ! tag (python3 with PyYAML not available here)" \
    '! grep -qE "(:|^ *-) +!" '"$role"
fi
check "then Access allows read and build, and TrustMode sso alone (login mode removed: research R3 unconfirmed)" \
  'p="$(awk "/^Parameters:/{f=1;next} /^[A-Z]/{f=0} f" '"$role"')"; for v in read build sso; do grep -qx "      - $v" <<<"$p"; done; ! grep -qE "LoginUserNames|SignInSessionArn|TrustLogin|^ *- login$" '"$role"
# "<Sid> <Effect> <action>" per action, "<Sid> <Effect> @<resource>" per resource; "(no-Sid)" when a statement has none.
statements() {
  awk '/^ *- Sid: /{s=$NF; a=0; r=0; next} /^ *- Effect: /{s="(no-Sid)"; e=$NF; next} /^ *Effect: /{e=$NF; next}
       /^ *(- )?(NotAction|NotResource|NotPrincipal):/{print s, e, "NOT"; next}
       /^ *Action:/{a=1; if (NF > 1) print s, e, $2; next}
       /^ *Resource:/{a=0; r=1; if (NF > 1) { print s, e, "@" $2; r=0 }; next}
       r && /Fn::Sub:/{print s, e, "@" $2; r=0; next}
       a && /^ *- [A-Za-z0-9-]+:[A-Za-z*]+$/{print s, e, $2; next} {a=0}' "$1"
}
# role_problems <template> <denied-actions.txt> <denied-read-actions.txt>: one line per broken rule, none when all hold.
role_problems() {
  local t="$1" st f d own='@arn:${AWS::Partition}:iam::${AWS::AccountId}:role/${RoleName}'
  st="$(statements "$t")"
  for f in "$2:DenyListed" "$3:DenyReadData"; do
    # comm, not diff: busybox diff prints unified output by default, with no </> lines
    d="$(comm -3 <(awk -v s="${f#*:}" '$1 == s && $2 == "Deny" && $3 !~ /^@/ {print $3}' <<<"$st" | sort) <(cut -d" " -f1 "${f%:*}" | sort) | awk -F'\t' '{printf "%s ", ($1 == "" ? "> " $2 : "< " $1)}')"
    [[ -z "$d" ]] || echo "the ${f#*:} deny differs from ${f%:*}: $d"
    awk '$1 ~ /\*/ && ($2 == "" || $2 ~ /\*/) || NF > 2 {print "no concrete action to simulate for " $1 " in " FILENAME}' "${f%:*}"
  done
  awk '$2 == "Allow" && $3 !~ /^@/ && ($1 ~ /^Trust/ ? $3 != "sts:AssumeRole" : $3 != "iam:GetRole" && $3 != "iam:SimulatePrincipalPolicy") {print "an allow grants " $3 " (" $1 ")"}' <<<"$st"
  grep -qx "ReadIam Allow iam:GetRole" <<<"$st" || echo "ReadIam does not allow iam:GetRole"
  for f in "ReadIam Allow" "DenySelfEdit Deny"; do [[ "$(awk -v s="${f% *}" '$1 == s && $3 ~ /^@/' <<<"$st")" == "$f $own" ]] || echo "${f% *} is not on the role's own ARN alone"; done
  for f in iam:PassRole "sts:AssumeRole*" sts:AssumeRoot "sso:*" "sso-directory:*" "identitystore:*"; do grep -qxF "DenyListed Deny $f" <<<"$st" || echo "the deny lacks $f"; done
  # sso-admin is the SDK client's name; IAM Identity Center's action prefix is sso, so sso-admin:* matches nothing.
  ! grep -qE "(^| )sso-admin:" "$2" <(cut -d" " -f3 <<<"$st") || echo "an entry uses sso-admin: (the IAM prefix is sso:)"
  grep -qxF '    AllowedPattern: "^[A-Za-z0-9+=,.@_-]*$"' <<<"$(awk '/^  PermissionSetName:/{f=1;next} /^  [A-Za-z]/{f=0} f' "$t")" || echo "PermissionSetName does not refuse * and ?"
  for f in UpdateStack DeleteStack CreateChangeSet ExecuteChangeSet SetStackPolicy; do grep -qxF "DenyOwnStack Deny cloudformation:$f" <<<"$st" || echo "the stack deny lacks cloudformation:$f"; done
  grep -qxF 'DenyOwnStack Deny @arn:${AWS::Partition}:cloudformation:${AWS::Region}:${AWS::AccountId}:stack/${AWS::StackName}/*' <<<"$st" || echo "the stack deny is not on \${AWS::StackName}"
  grep -qE 'sso\.amazonaws\.com/\*AWSReservedSSO_\$\{PermissionSetName\}_\?{16}$' "$t" || echo "the trust does not end /*AWSReservedSSO_<PermissionSetName>_ and 16 ?"
  ! grep -qF 'sso.amazonaws.com/*/AWSReservedSSO_' "$t" || echo "the trust uses sso.amazonaws.com/*/AWSReservedSSO_ (misses us-east-1)"
  [[ "$(grep -c "^ *- Sid: Trust" "$t")" == 1 ]] || echo "not one trust statement"
  grep -qx "      MaxSessionDuration: 3600" "$t" || echo "MaxSessionDuration is not 3600"
  grep -qx "        - Key: landspec:access" "$t" || echo "no landspec:access tag"
  grep -oE "iam::aws:policy/[A-Za-z]+" "$t" | grep -vxE "iam::aws:policy/(ReadOnlyAccess|PowerUserAccess)" | sed "s/^/a managed policy other than ReadOnlyAccess or PowerUserAccess: /" || true
  for f in AWS::IAM::User AWS::IAM::AccessKey AWS::IAM::ManagedPolicy AWS::IAM::Policy "PermissionsBoundary:"; do ! grep -qF "$f" "$t" || echo "the template has $f"; done
}
aws_lists="extension/aws/denied-actions.txt extension/aws/denied-read-actions.txt"
problems="$(role_problems "$role" $aws_lists | tr "\n" ";")"
check "when agent-role.yaml is checked against contracts/template.md, then nothing is wrong${problems:+ — $problems}" '[[ -z "$problems" ]]'
check "then its Deny holds the 26 actions of denied-actions.txt and its read deny the 23 of denied-read-actions.txt" \
  '[[ "$(statements '"$role"' | grep -c "^DenyListed Deny [^@]")" == 26 && "$(statements '"$role"' | grep -c "^DenyReadData Deny [^@]")" == 23 && "$(wc -l < extension/aws/denied-actions.txt)" -eq 26 ]]'
check "then the read deny exists only when Access=read" \
  'grep -B2 -- "- Sid: DenyReadData" '"$role"' | grep -q -- "- IsRead"'
# The failure paths: a broken copy is named.
broken() { # broken <expected problem> <awk program applied to the template> [<awk program applied to denied-actions.txt>]
  mkdir -p "$TMP/role"; awk "$2" "$role" > "$TMP/role/t.yaml"; awk "${3:-1}" extension/aws/denied-actions.txt > "$TMP/role/d.txt"
  role_problems "$TMP/role/t.yaml" "$TMP/role/d.txt" extension/aws/denied-read-actions.txt | grep -qF -- "$1"
}
check "when an allow also grants iam:CreateRole, then the check names it" \
  'broken "an allow grants iam:CreateRole (ReadIam)" "{print} /- iam:SimulatePrincipalPolicy/{print \"                  - iam:CreateRole\"}"'
check "when an allow statement has no Sid, then its actions are still read" \
  'broken "an allow grants iam:CreateRole ((no-Sid))" "{print} /^ *Statement:/ && !x {x=1; print \"              - Effect: Allow\"; print \"                Action:\"; print \"                  - iam:CreateRole\"}"'
check "when sts:AssumeRole* is dropped from the template and the list, then the check names it" \
  'broken "the deny lacks sts:AssumeRole*" "!/- sts:AssumeRole\\*$/" "!/^sts:AssumeRole\\*/"'
check "when the template and denied-actions.txt differ, then the check names the action" \
  'broken "the DenyListed deny differs from $TMP/role/d.txt: < kms:DisableKey" "1" "!/^kms:DisableKey$/"'
check "when a wildcard entry has no concrete action, then the check names it" \
  'broken "no concrete action to simulate for sts:AssumeRole*" "1" "{sub(/^sts:AssumeRole\\* sts:AssumeRole$/, \"sts:AssumeRole*\")} 1"'
check "when ReadIam drops iam:GetRole, then the check names it" \
  'broken "ReadIam does not allow iam:GetRole" "!/- iam:GetRole$/"'
check "when the stack deny names a fixed stack, then the check names it" \
  'broken "the stack deny is not on \${AWS::StackName}" "{sub(/stack\\/\\\$\\{AWS::StackName\\}/, \"stack/landspec-agent\")} 1"'
check "when the trust uses sso.amazonaws.com/*/AWSReservedSSO_, then the check names it" \
  'broken "the trust uses sso.amazonaws.com/*/AWSReservedSSO_" "{sub(/sso.amazonaws.com\\/\\*AWSReservedSSO_/, \"sso.amazonaws.com/*/AWSReservedSSO_\")} 1"'
check "when the trust ends _* again, then the check names it" \
  'broken "the trust does not end /*AWSReservedSSO_<PermissionSetName>_ and 16 ?" "{sub(/_\\?+$/, \"_*\")} 1"'
check "when a second trust statement is added, then the check names it" \
  'broken "not one trust statement" "{print} /^        Statement:/{print \"          - Sid: TrustLogin\"}"'
check "then the trust ARN matches permission set Dev's role and not Dev_ReadOnly's, nor a short suffix (ArnLike ? is one character)" \
  'pat="$(grep -oE "sso\.amazonaws\.com/\*AWSReservedSSO_.*" '"$role"')"; pat="${pat//\$\{PermissionSetName\}/Dev}"; r=sso.amazonaws.com/eu-west-1/AWSReservedSSO_
   [[ "sso.amazonaws.com/AWSReservedSSO_Dev_0123456789abcdef" == $pat && "${r}Dev_0123456789abcdef" == $pat ]] \
   && [[ "${r}Dev_ReadOnly_0123456789abcdef" != $pat && "${r}Dev_0123456789abcde" != $pat && "${r}Dev_0123456789abcdef0" != $pat ]]'
check "when sso-admin:* is put back in the template and the list, then the check names it" \
  'broken "an entry uses sso-admin:" "{sub(/- sso:\\*$/, \"- sso-admin:*\")} 1" "{sub(/^sso:\\* sso:/, \"sso-admin:* sso-admin:\")} 1"'
check "when PermissionSetName loses its AllowedPattern, then the check names it" \
  'broken "PermissionSetName does not refuse * and ?" "!/AllowedPattern: \"\\^\\[A-Za-z0-9/"'
check "then the PermissionSetName pattern takes a name and empty, and refuses * and ?" \
  'for v in Dev_Admin ""; do [[ "$v" =~ ^[A-Za-z0-9+=,.@_-]*$ ]]; done; for v in "*" "Dev?" "a*b"; do ! [[ "$v" =~ ^[A-Za-z0-9+=,.@_-]*$ ]]; done'
check "when the template adds an access key, then the check names it (SC-003)" \
  'broken "the template has AWS::IAM::AccessKey" "{print} /^Resources:/{print \"  Key:\"; print \"    Type: AWS::IAM::AccessKey\"}"'
check "when the template adds a permissions boundary, then the check names it" \
  'broken "the template has PermissionsBoundary:" "{print} /^      MaxSessionDuration:/{print \"      PermissionsBoundary: x\"}"'

# The organization policy (contracts/template.md "scp-agent.json"). The action lists are read with awk, so every job runs them.
scp=extension/aws/scp-agent.json
if command -v python3 >/dev/null; then check "when scp-agent.json is parsed, then it is valid JSON (python3)" 'python3 -m json.tool '"$scp"' >/dev/null'
elif command -v jq >/dev/null; then check "when scp-agent.json is parsed, then it is valid JSON (jq)" 'jq . '"$scp"' >/dev/null'
else echo "skip - scp-agent.json JSON validity (neither python3 nor jq here)"; fi
# scp_problems <scp> <denied-actions.txt>: one line per broken rule, none when all hold. Reads one string per line, as the file is written.
scp_problems() {
  local p="$1" st s d pa='"aws:PrincipalArn": "arn:aws:iam::*:role/landspec-agent*"'
  st="$(awk '/"Sid":/{s=$2; gsub(/[",]/, "", s)} /"Effect":/{e=$2; gsub(/[",]/, "", e)} /"Action": \[/{a=1; next} a && /\]/{a=0} a {gsub(/[ ",]/, ""); print s, e, $0}' "$1")"
  [[ "$(grep -c '"Sid":' "$p")" == 3 && "$(grep -c '"Effect": "Deny",' "$p")" == 3 ]] || echo "not three Deny statements"
  ! grep -q '"Effect": "Allow"' "$p" || echo "an Allow statement"
  for s in DenyListedForAgent DenyListedViaMcp; do
    d="$(comm -3 <(awk -v s="$s" '$1 == s && $2 == "Deny" {print $3}' <<<"$st" | sort) <(cut -d" " -f1 "$2" | sort) | awk -F'\t' '{printf "%s ", ($1 == "" ? "> " $2 : "< " $1)}')"
    [[ -z "$d" ]] || echo "the $s deny differs from $2: $d"
  done
  d="$(comm -3 <(awk '$1 == "DenySelfEdit" && $2 == "Deny" {print $3}' <<<"$st" | sort) <(statements "$role" | awk '$1 == "DenySelfEdit" && $3 !~ /^@/ {print $3}' | sort) | tr '\t\n' '  ')"
  [[ -z "${d// /}" ]] || echo "the DenySelfEdit deny differs from the template's: $d"
  [[ "$(grep -cF "\"Condition\": { \"ArnLike\": { $pa } }" "$p")" == 2 ]] || echo "DenyListedForAgent and DenySelfEdit are not both on aws:PrincipalArn role/landspec-agent*"
  grep -qF '"Condition": { "Bool": { "aws:ViaAWSMCPService": "true" } }' "$p" || echo "no statement on aws:ViaAWSMCPService"
  grep -qF '"Resource": "arn:aws:iam::*:role/landspec-agent*",' "$p" || echo "DenySelfEdit is not on role/landspec-agent*"
  (($(wc -c < "$p") <= 5120)) || echo "longer than the 5120 characters an SCP may hold"
}
problems="$(scp_problems "$scp" extension/aws/denied-actions.txt | tr "\n" ";")"
check "when scp-agent.json is checked against contracts/template.md, then nothing is wrong${problems:+ — $problems}" '[[ -z "$problems" ]]'
check "then its two listed denies hold the 26 actions each, and the MCP one is the second" \
  '[[ "$(grep -c "^        \"" '"$scp"')" == 64 ]] && grep -A33 "\"Sid\": \"DenyListedViaMcp\"" '"$scp"' | grep -q "aws:ViaAWSMCPService"'
scp_broken() { # scp_broken <expected problem> <awk program applied to the SCP> [<awk program applied to denied-actions.txt>]
  mkdir -p "$TMP/scp"; awk "$2" "$scp" > "$TMP/scp/p.json"; awk "${3:-1}" extension/aws/denied-actions.txt > "$TMP/scp/d.txt"
  [[ "$(scp_problems "$TMP/scp/p.json" "$TMP/scp/d.txt")" == *"$1"* ]] # not | grep -q: a match before the last line is a SIGPIPE under pipefail
}
check "when denied-actions.txt gains an action the SCP lacks, then the check names it in both denies" \
  'scp_broken "the DenyListedForAgent deny differs from $TMP/scp/d.txt: > ec2:DeleteVpc" 1 "1; END {print \"ec2:DeleteVpc\"}" && scp_broken "the DenyListedViaMcp deny differs from $TMP/scp/d.txt: > ec2:DeleteVpc" 1 "1; END {print \"ec2:DeleteVpc\"}"'
check "when the MCP deny drops an action, then the check names it" \
  'scp_broken "the DenyListedViaMcp deny differs from $TMP/scp/d.txt: > kms:DisableKey" "/DenyListedViaMcp/{m=1} !(m && /\"kms:DisableKey\"/)"'
check "when the self-edit deny drops iam:DeleteRole, then the check names it" \
  'scp_broken "the DenySelfEdit deny differs from the template" "!/\"iam:DeleteRole\"/"'
check "when the MCP condition is dropped, then the check names it" \
  'scp_broken "no statement on aws:ViaAWSMCPService" "!/aws:ViaAWSMCPService/"'
check "when the principal pattern names another role, then the check names it" \
  'scp_broken "not both on aws:PrincipalArn" "{sub(/role\\/landspec-agent\\*\" } }/, \"role/other\\\" } }\")} 1"'
check "when a statement turns into an Allow, then the check names it" \
  'scp_broken "not three Deny statements" "{sub(/\"Effect\": \"Deny\"/, \"\\\"Effect\\\": \\\"Allow\\\"\")} 1" && scp_broken "an Allow statement" "{sub(/\"Effect\": \"Deny\"/, \"\\\"Effect\\\": \\\"Allow\\\"\")} 1"'
check "when the self-edit deny is on another resource, then the check names it" \
  'scp_broken "DenySelfEdit is not on role/landspec-agent*" "{sub(/\"Resource\": \"arn:aws:iam::\\*:role\\/landspec-agent\\*\"/, \"\\\"Resource\\\": \\\"*\\\"\")} 1"'
pad() { echo "1; END {for (i = 0; i < $(($1 - $(wc -c < "$scp"))); i++) printf \" \"}"; } # pad <size>: the SCP grown to exactly <size> characters
check "when the policy holds 5121 characters, then the check names it, and at exactly 5120 it does not" \
  'scp_broken "longer than the 5120 characters" "$(pad 5121)" && ! scp_broken "longer than the 5120 characters" "$(pad 5120)" && [[ "$(wc -c < "$TMP/scp/p.json")" -eq 5120 ]]'

exit "$FAIL"
