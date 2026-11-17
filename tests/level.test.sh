#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_gh
l="$SCRIPTS/level.sh"
blocks() { grep -c '^<!-- landspec:start' .specify/memory/constitution.md; }

new_repo lite
cp "$ROOT/preset/templates/constitution-template.md" .specify/memory/constitution.md 2>/dev/null \
  || { mkdir -p .specify/memory; cp "$ROOT/preset/templates/constitution-template.md" .specify/memory/constitution.md; }
printf '[workspace]\n' > Cargo.toml; printf '{"packageManager":"pnpm@9.0.0","scripts":{"lint":"x","test":"y"}}\n' > package.json
# An install from before these keys existed: level.sh must add them.
sed -i.bak '/^milestone:/d; /^project:/d' .specify/extensions/landspec/landspec-config.yml

"$l" lite >/dev/null
check "when set to lite, then only the PR template is scaffolded" \
  '[[ -f .github/pull_request_template.md && -f .github/copilot-instructions.md && ! -f .github/workflows/ci.yml && ! -f .github/dependabot.yml ]]'
check "then the constitution has one landspec block for lite" '[[ "$(blocks)" == 1 ]] && grep -q "level: lite" .specify/memory/constitution.md'
check "then the branch flow targets main" 'grep -qF "feat/* → main" .specify/memory/constitution.md'
check "then an older config gains empty milestone and project keys (nothing is guessed)" \
  'grep -qx "milestone: \"\"" .specify/extensions/landspec/landspec-config.yml && grep -qx "project: \"\"" .specify/extensions/landspec/landspec-config.yml'
check "then Claude settings drop AI attribution from commits and PRs" 'grep -q "\"attribution\"" .claude/settings.json'
check "then every file it wrote is recorded with its SHA-256 (what remove.sh compares against)" \
  'h="$(sha256sum < .githooks/pre-commit 2>/dev/null || shasum -a 256 < .githooks/pre-commit)"; grep -qxF "${h%% *} .githooks/pre-commit" .specify/landspec-files.sha256 && [[ "$(grep -c " .githooks/pre-commit$" .specify/landspec-files.sha256)" == 1 ]] && "$l" lite >/dev/null && [[ "$(grep -c " .githooks/pre-commit$" .specify/landspec-files.sha256)" == 1 ]]'

mkdir -p .github/workflows; echo "# mine" > .github/workflows/ci.yml
echo '{}' > .claude/settings.json
check "when Claude settings exist without attribution (a team that discloses AI use), then they are kept and nobody nags" \
  'out="$("$l" lite)"; [[ "$(cat .claude/settings.json)" == "{}" && "$out" != *"attribution"* ]]'
"$l" standard >/dev/null
check "when going up to standard, then CI is never overwritten if it already exists" '[[ "$(cat .github/workflows/ci.yml)" == "# mine" ]]'
check "then every Dependabot entry waits 7 days before proposing a release (zizmor dependabot-cooldown)" \
  'n=$(grep -c "package-ecosystem:" .github/dependabot.yml); [[ $n -gt 0 && "$(grep -c "default-days: 7" .github/dependabot.yml)" == "$n" ]]'
check "then dependabot covers the detected stacks and targets develop" \
  'grep -q "package-ecosystem: cargo" .github/dependabot.yml && grep -q "package-ecosystem: npm" .github/dependabot.yml && grep -q "target-branch: develop" .github/dependabot.yml'
check "then the stack idioms and test command come from the manifests" \
  'grep -q "cargo clippy" .specify/memory/constitution.md && grep -qF "\`cargo test --all && pnpm test\`" .specify/memory/constitution.md'
check "then the block is replaced, not duplicated" '[[ "$(blocks)" == 1 ]] && grep -q "level: standard" .specify/memory/constitution.md'

rm .github/workflows/ci.yml
"$l" standard >/dev/null
check "when there is no Dockerfile or Terraform, then the security CI has no infra scan" '! grep -q "trivy" .github/workflows/security.yml'
check "when CI is missing, then it is generated with rust and pnpm jobs" \
  'grep -q "cargo clippy --all-targets" .github/workflows/ci.yml && grep -q "pnpm install --frozen-lockfile" .github/workflows/ci.yml && grep -q "pnpm run lint" .github/workflows/ci.yml'
check "then the Node CI uses the current LTS, not a hard-coded major" 'grep -q "node-version: lts/\*" .github/workflows/ci.yml'
check "when the project pins Node, then CI uses that file" \
  '(echo 26 > .node-version; rm .github/workflows/ci.yml; "$l" standard >/dev/null; grep -q "node-version-file: .node-version" .github/workflows/ci.yml; s=$?; rm .node-version; exit $s)'

cp .github/workflows/security.yml "$TMP/sec.bak"; echo "name: my own security" > .github/workflows/security.yml
out="$("$l" full --no-branches)"
check "when security.yml has no marker, then it is kept and the output says how to get the current one" \
  'grep -qxF "kept (no marker): .github/workflows/security.yml — delete it to get the current one" <<<"$out" && [[ "$(cat .github/workflows/security.yml)" == "name: my own security" ]]'
"$l" standard --no-branches >/dev/null; cp "$TMP/sec.bak" .github/workflows/security.yml
rm -f .github/workflows/security.yml .github/dependabot.yml
mkdir -p services/api terraform/envs/prod
printf 'FROM scratch\n' > Dockerfile; printf 'FROM scratch\n' > services/api/Dockerfile.prod
echo 'terraform {}' > terraform/envs/prod/main.tf
"$l" standard >/dev/null
check "when a Dockerfile and Terraform exist, then the security CI scans them with checksum-verified trivy" \
  'grep -q "trivy config --exit-code 1 --severity HIGH,CRITICAL" .github/workflows/security.yml && grep -q "sha256sum -c" .github/workflows/security.yml'
check "then Dependabot updates every folder with a Dockerfile, and every folder with Terraform" \
  '[[ "$(grep -A1 "package-ecosystem: docker" .github/dependabot.yml | grep -c "directory:")" == 2 ]] && grep -q "directory: \"/\"" .github/dependabot.yml && grep -q "directory: \"/services/api\"" .github/dependabot.yml && grep -A1 "package-ecosystem: terraform" .github/dependabot.yml | grep -q "directory: \"/terraform/envs/prod\""'
rm -rf Dockerfile services terraform

"$l" full >/dev/null
check "when going up to full, then staging is created on origin" 'git ls-remote --exit-code origin staging'
check "then SECURITY.md, CODEOWNERS and the release workflow exist" '[[ -f SECURITY.md && -f .github/CODEOWNERS && -f .github/workflows/release.yml ]]'

cp .specify/memory/constitution.md "$TMP/const.bak"; LANDSPEC_CFG=.specify/extensions/landspec/landspec-config.yml
sed -i.bak '/<!-- landspec:end -->/d' .specify/memory/constitution.md; echo "my own principle" >> .specify/memory/constitution.md
check "when the landspec:end marker is missing, then it refuses and keeps the user's text" \
  'fails_with "no '"'"'<!-- landspec:end -->'"'"'" "$l" lite && grep -q "my own principle" .specify/memory/constitution.md'
cp "$TMP/const.bak" .specify/memory/constitution.md

awk '/^<!-- landspec:end -->/ { next } /^<!-- landspec:start/ { print "<!-- landspec:end -->" } { print }' .specify/memory/constitution.md > "$TMP/const.rev"
echo 'my text after' >> "$TMP/const.rev"; cp "$TMP/const.rev" .specify/memory/constitution.md; cp "$LANDSPEC_CFG" "$TMP/cfg.bak"
check "when the markers are reversed, then it refuses before anything changes, the level included" \
  'fails_with "damaged" "$l" lite && cmp -s "$TMP/const.rev" .specify/memory/constitution.md && cmp -s "$TMP/cfg.bak" "$LANDSPEC_CFG"'
{ cat "$TMP/const.bak"; echo '<!-- landspec:start (managed) -->'; } > .specify/memory/constitution.md; cp .specify/memory/constitution.md "$TMP/const.two"
check "when a second start marker follows the block, then it refuses before anything changes" \
  'fails_with "damaged" "$l" lite && cmp -s "$TMP/const.two" .specify/memory/constitution.md && cmp -s "$TMP/cfg.bak" "$LANDSPEC_CFG"'
{ cat "$TMP/const.bak"; echo '<!-- landspec:end -->'; } > .specify/memory/constitution.md; cp .specify/memory/constitution.md "$TMP/const.two"
check "when a second end marker follows the block, then it refuses before anything changes" \
  'fails_with "damaged" "$l" lite && cmp -s "$TMP/const.two" .specify/memory/constitution.md && cmp -s "$TMP/cfg.bak" "$LANDSPEC_CFG"'
sed '/^<!-- landspec:start/d' "$TMP/const.bak" > .specify/memory/constitution.md; cp .specify/memory/constitution.md "$TMP/const.two"
check "when only an end marker is left, then it refuses before anything changes" \
  'fails_with "damaged" "$l" lite && cmp -s "$TMP/const.two" .specify/memory/constitution.md && cmp -s "$TMP/cfg.bak" "$LANDSPEC_CFG"'
cp "$TMP/const.bak" .specify/memory/constitution.md
printf 'The marker is written <!-- landspec:start like this.\nThe end is <!-- landspec:end --> in prose.\nkeep me\n' >> .specify/memory/constitution.md
check "when mid-line markers follow the block, then they are plain text and stay" \
  '"$l" full >/dev/null && grep -q "keep me" .specify/memory/constitution.md && grep -q "written <!-- landspec:start" .specify/memory/constitution.md && grep -q "end is <!-- landspec:end" .specify/memory/constitution.md'
cp "$TMP/const.bak" .specify/memory/constitution.md
sed -i.bak '/^<!-- landspec:start/a\
The end is <!-- landspec:end --> in prose.\
stale block line
' .specify/memory/constitution.md; rm -f .specify/memory/constitution.md.bak
check "when a mid-line end marker sits inside the block, then the whole block is replaced" \
  '"$l" full >/dev/null && ! grep -q "stale block line" .specify/memory/constitution.md'
cp "$TMP/const.bak" .specify/memory/constitution.md

out="$("$l" lite)"
check "when going back down to lite, then no file is deleted and it says so" \
  '[[ -f SECURITY.md && -f .github/workflows/ci.yml && "$out" == *"were kept"* ]] && grep -q "level: lite" .specify/memory/constitution.md'
check "then the level is stored in the config" 'grep -qx "level: lite" .specify/extensions/landspec/landspec-config.yml'
check "when given an unknown level, then it refuses" '! "$l" huge'

printf '# Custom constitution\n\n## Governance\n\nRules.\n' > .specify/memory/constitution.md
"$l" standard --no-branches >/dev/null
check "when the constitution has no landspec block, then it is inserted before Governance and the rest is kept" \
  '[[ "$(blocks)" == 1 ]] && grep -q "^# Custom constitution" .specify/memory/constitution.md && awk "/landspec:end/{e=NR} /^## Governance/{g=NR} END{exit !(e<g)}" .specify/memory/constitution.md'

rm Cargo.toml package.json .github/workflows/ci.yml
"$l" standard --no-branches >/dev/null
check "when no stack is detected, then CI is a clearly marked placeholder" 'grep -q "no stack detected" .github/workflows/ci.yml'

# Security scaffolding, pinning and git hooks (fresh repo).
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
printf '{"scripts":{"test":"x"}}\n' > package.json
"$l" lite >/dev/null
check "when set to lite, then the git hooks are installed, executable and enabled" \
  '[[ -x .githooks/pre-commit && -x .githooks/pre-push && "$(git config core.hooksPath)" == .githooks ]]'
check "then lite has no security workflow yet" '[[ ! -f .github/workflows/security.yml ]]'
"$l" standard >/dev/null
check "when set to standard, then the security workflow scans secrets, dependencies and workflows" \
  'grep -q "gitleaks git --redact" .github/workflows/security.yml && grep -q "osv-scanner scan source" .github/workflows/security.yml && grep -q "zizmorcore/zizmor-action@" .github/workflows/security.yml'
check "then downloaded scanners are checksum-verified" '[[ "$(grep -c "sha256sum -c -" .github/workflows/security.yml)" == 2 ]]'
check "then it also runs weekly, for new CVEs in unchanged dependencies" 'grep -q "cron:" .github/workflows/security.yml'
check "then standard has no SAST job (that is full)" '! grep -q "semgrep scan" .github/workflows/security.yml'
check "then every action in generated workflows is pinned to a full commit SHA" \
  '! grep -hE "uses: [^ ]+@" .github/workflows/*.yml | grep -vE "@[0-9a-f]{40}( |$)"'
check "then every checkout says persist-credentials: false (the default keeps the token on disk)" \
  'n=$(grep -c "actions/checkout@" .github/workflows/ci.yml); [[ $n -gt 0 && "$(grep -A2 "actions/checkout@" .github/workflows/ci.yml | grep -c "persist-credentials: false")" == "$n" ]]'
rm .github/workflows/security.yml
"$l" full >/dev/null
check "when level.sh full writes security.yml, then Semgrep runs from semgrep/semgrep@sha256:<64 hex> equal to SEMGREP_DIGEST, with the default and OWASP rules" \
  'd="$(sed -nE "s/^SEMGREP_DIGEST=\"([0-9a-f]{64})\".*/\1/p" "$SCRIPTS/pins.sh")"; [[ -n "$d" ]] && grep -qE "^ +image: semgrep/semgrep@sha256:$d( |$)" .github/workflows/security.yml && grep -q "semgrep scan --config p/default --config p/owasp-top-ten --error --metrics off" .github/workflows/security.yml'
check "then nothing installs Semgrep by version alone" '! grep -qE "semgrep==|install .*semgrep|semgrep/semgrep:" .github/workflows/security.yml'

rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo standard
git config core.hooksPath .husky
out="$("$l" standard --no-branches)"
check "when the repo already uses its own hooks (husky), then they are not replaced and it says how to add ours" \
  '[[ "$(git config core.hooksPath)" == .husky ]] && grep -q "secrets.sh staged" <<<"$out"'

# `gh repo create --clone`: an origin, but no commits yet.
git init --quiet --bare "$TMP/empty-origin.git"; git clone --quiet "$TMP/empty-origin.git" "$TMP/empty" 2>/dev/null
cd "$TMP/empty"; git config user.email t@t; git config user.name t
mkdir -p .specify/extensions/landspec && ln -s "$ROOT/extension/scripts" .specify/extensions/landspec/scripts
check "when the repo has an origin but no commits yet, then setup succeeds and says the branches come later" \
  'out="$("$l" standard 2>&1)" && grep -q "develop not created yet (no commits)" <<<"$out" && [[ -f .specify/memory/constitution.md ]]'

# Committed locally, nothing pushed yet: setup must not push local (unscanned) commits anywhere.
git init --quiet --bare "$TMP/unpushed-origin.git"; git clone --quiet "$TMP/unpushed-origin.git" "$TMP/unpushed" 2>/dev/null
cd "$TMP/unpushed"; git config user.email t@t; git config user.name t
mkdir -p .specify/extensions/landspec && ln -s "$ROOT/extension/scripts" .specify/extensions/landspec/scripts
echo x > a.txt; git add a.txt; git commit --quiet --no-verify -m local
check "when the default branch isn't on origin yet, then setup pushes nothing and says to push it first" \
  'out="$("$l" standard 2>&1)" && grep -q "origin/develop not created yet" <<<"$out" && [[ -z "$(git ls-remote --heads origin)" ]]'


# ── Generated CI on its first run ──
ci_repo() { rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo lite; }
ci_yml=.github/workflows/ci.yml
ci_repo
printf '{"scripts":{"test":"x"}}\n' > package.json; : > pnpm-lock.yaml
"$l" standard --no-branches >/dev/null
check "when a pnpm project has no packageManager field, then CI gives pnpm/action-setup a version" \
  'grep -A2 "pnpm/action-setup@" $ci_yml | grep -q "^          version: latest$"'
printf '{"packageManager" : "pnpm@9.0.0","scripts":{"test":"x"}}\n' > package.json; rm $ci_yml
"$l" standard --no-branches >/dev/null
check "when packageManager names pnpm, then CI gives no version (the action refuses two)" \
  'grep -q "pnpm/action-setup@" $ci_yml && ! grep -q "version: latest" $ci_yml'

ci_repo
printf '{"packageManager":"yarn@4.5.0","scripts":{"test":"x"}}\n' > package.json; : > yarn.lock
"$l" standard --no-branches >/dev/null
check "when packageManager is Yarn 2+, then setup-node has no cache (it would run the runner's Yarn 1) and corepack comes before the install" \
  '! grep -qE "^ +cache:" $ci_yml && [[ "$(grep -A1 -F "npm install -g corepack && corepack enable" $ci_yml | tail -1)" == "      - run: yarn install --immutable" ]] && ! grep -q "frozen-lockfile" $ci_yml'
printf '{"packageManager":"yarn@1.22.22","scripts":{"test":"x"}}\n' > package.json; rm $ci_yml
"$l" standard --no-branches >/dev/null
check "when packageManager is Yarn 1, then CI keeps the cache and the frozen install, with no corepack" \
  'grep -q "cache: yarn" $ci_yml && grep -q "yarn install --frozen-lockfile" $ci_yml && ! grep -q corepack $ci_yml'

ci_repo
printf '{"packageManager":"npm@10.9.0","scripts":{"test":"x"}}\n' > package.json
"$l" standard --no-branches >/dev/null
check "when a project has no lockfile, then setup-node gets no cache, not even its automatic one, which would fail the first run" \
  '! grep -qE "^ +cache:" $ci_yml && grep -q "package-manager-cache: false" $ci_yml && grep -q "run: npm install" $ci_yml'
: > package-lock.json; rm $ci_yml
"$l" standard --no-branches >/dev/null
check "when it has a lockfile, then the cache is kept" 'grep -q "cache: npm" $ci_yml && ! grep -q package-manager-cache $ci_yml && grep -q "run: npm ci" $ci_yml'

ci_repo
mkdir -p .specify/memory; cp "$ROOT/preset/templates/constitution-template.md" .specify/memory/constitution.md
printf '{"scripts":{"test":"x"}}\n' > package.json
for none in none None N/A -; do
  sed -i.bak -E "s#^\*\*Commands\*\*.*#**Commands**: build \`$none\` · test \`make check\` · lint \`$none\` · mutate \`$none\`#" .specify/memory/constitution.md
  rm -f $ci_yml; "$l" standard --no-branches >/dev/null
  check "when the Commands line says build \`$none\`, then it is unset: no such step in CI and no such mutate command" \
    '! grep -qF -- "run: $none" $ci_yml && grep -q "run: make check" $ci_yml && (source "$SCRIPTS/lib.sh"; [[ -z "$(constitution_cmd mutate)" ]])'
done

# A kept workflow filtered to other branches never runs on a task PR.
gate_repo() { # gate_repo <the workflow's on: block> [<level>]
  rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo lite; mkdir -p .github/workflows
  printf 'name: Tests\non:\n%b\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo branches\n' "$1" > .github/workflows/tests.yml
  out="$("$l" "${2:-standard}" --no-branches)"
}
says_skipped='warning: .github/workflows/tests.yml never runs on a task PR into develop'
gate_repo '  pull_request:\n    branches: [master]'
check "when kept CI is filtered to master (inline list), then it names the workflow and the branch to add" \
  'grep -qF "$says_skipped" <<<"$out" && grep -qF "add develop to its pull_request branches" <<<"$out" && [[ ! -f .github/workflows/ci.yml ]]'
gate_repo "  push:\n    branches: [develop]\n  pull_request:\n    branches:\n      - main # release\n      - 'release/**'\n  schedule:\n    - cron: '1 1 * * 1'"
check "when kept CI is filtered to main (block list, with a develop filter under push), then it says so too" \
  'grep -qF "$says_skipped" <<<"$out"'
gate_repo '  pull_request:\n    branches:\n    - main' full
check "when the list sits at the key's own indent, at full, then it says so too" 'grep -qF "$says_skipped" <<<"$out"'
gate_repo '  pull_request:\n    branches: [main, develop]'
check "when the filter lists the base branch, then nothing is said" '! grep -q "^warning:" <<<"$out"'
gate_repo "  pull_request:\n    branches: ['dev*']"
check "when a glob in the filter matches the base branch, then nothing is said" '! grep -q "^warning:" <<<"$out"'
gate_repo '  pull_request:\n  push:\n    branches: [main]'
check "when pull_request has no filter, then a push filter does not count and nothing is said" '! grep -q "^warning:" <<<"$out"'
gate_repo '  pull_request:\n    branches: [main]'; set_cfg base_branch main
check "when base_branch names the branch in the filter, then nothing is said" 'out="$("$l" standard --no-branches)"; ! grep -q "^warning:" <<<"$out"'

# Task branches start from the base branch, so that is where the setup has to land.
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo lite
git push --quiet origin --delete develop; git fetch --quiet --prune origin
out="$("$l" full)"
check "when level.sh creates the base branch, then it says the setup goes there and the default branch gets it at the next promotion" \
  'git ls-remote --exit-code origin develop && grep -qF "open its PR with --base develop" <<<"$out" && grep -qF "main gets it at the next promotion" <<<"$out"'
check "then it says so once, for the base branch and not for staging" '[[ "$(grep -c -- "--base" <<<"$out")" == 1 ]]'
check "when the branch already exists, then it says nothing" '! "$l" full | grep -q -- "--base"'

# ── Hooks in repos that already use the pre-commit framework or husky ──
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo lite
printf 'repos:\n  - repo: https://github.com/x/y\n    rev: v1\n    hooks:\n      - id: a\n' > .pre-commit-config.yaml
out="$("$l" lite --no-branches)"
check "when the repo uses the pre-commit framework, then both landspec hooks are appended with the file's own indentation" \
  'grep -q "^  - repo: local$" .pre-commit-config.yaml && grep -q "^      - id: landspec-secrets$" .pre-commit-config.yaml && grep -q "^        stages: \[pre-push\]$" .pre-commit-config.yaml && [[ -z "$(git config core.hooksPath)" ]]'
check "then it says the hooks are not active in this clone until pre-commit install runs" \
  'grep -q "pre-commit install --hook-type pre-commit --hook-type pre-push" <<<"$out"'
check "when run again, then nothing is appended twice" '"$l" lite --no-branches >/dev/null; [[ "$(grep -c "id: landspec-secrets" .pre-commit-config.yaml)" == 1 ]]'
if python3 -c "import yaml" 2>/dev/null; then
  check "then the config is still valid YAML with one local repo holding the two hooks" \
    'python3 -c "import yaml,sys; r=[x for x in yaml.safe_load(open(\".pre-commit-config.yaml\"))[\"repos\"] if x[\"repo\"]==\"local\"]; sys.exit(0 if len(r)==1 and [h[\"id\"] for h in r[0][\"hooks\"]]==[\"landspec-secrets\",\"landspec-prepush\"] else 1)"'
else
  echo "skip - pre-commit config YAML check (python3 with PyYAML not available here)"
fi
printf 'repos:\n-   repo: local\n    hooks:\n    -   id: landspec-secrets\n        name: secrets\n        entry: bash .specify/extensions/landspec/scripts/secrets.sh staged\n        language: system\n' > .pre-commit-config.yaml
"$l" lite --no-branches >/dev/null
check "when only the commit hook was added by hand (4-space style), then only the push hook is appended, in that style" \
  '[[ "$(grep -c "scripts/secrets.sh" .pre-commit-config.yaml)" == 1 ]] && grep -q "^    -   id: landspec-prepush$" .pre-commit-config.yaml && grep -q "^        entry: bash .specify/extensions/landspec/scripts/prepush.sh$" .pre-commit-config.yaml'
rm .pre-commit-config.yaml; mkdir -p .husky; echo "npm test" > .husky/pre-commit
"$l" lite --no-branches >/dev/null
check "when the repo uses husky, then the checks are appended to its hook files and the existing line is kept" \
  '[[ "$(head -1 .husky/pre-commit)" == "npm test" ]] && grep -q "secrets.sh staged" .husky/pre-commit && grep -qF "prepush.sh \"\$@\"" .husky/pre-push && [[ -z "$(git config core.hooksPath)" ]]'

# A top-level key after repos: must stay after landspec's item, or the file stops parsing.
pc_valid() { # the repos list has the two landspec hooks, and every key the file had is still at the top level
  ! python3 -c "import yaml" 2>/dev/null || python3 -c "
import yaml,sys
d=yaml.safe_load(open('.pre-commit-config.yaml'))
ids=[h['id'] for r in d['repos'] if r['repo']=='local' for h in r['hooks']]
sys.exit(0 if ids==['landspec-secrets','landspec-prepush'] and set(d)>=set(sys.argv[1:]) else 1)" "$@"
}
before_key() { awk -v k="$1" '/repo: local$/ { r = NR } index($0, k) == 1 { c = NR } END { exit !(r && c && r < c) }' .pre-commit-config.yaml; }
pc_repo() { rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo lite; printf "$1" > .pre-commit-config.yaml; }
pc_repo 'repos:\n  - repo: https://github.com/x/y\n    rev: v1\n    hooks:\n      - id: a\n\n# pre-commit.ci\nci:\n  autofix_prs: false\n'
"$l" lite --no-branches >/dev/null
check "when a top-level key follows repos:, then landspec's item goes in the list, before that key and its comment" \
  'before_key "ci:" && before_key "# pre-commit.ci" && pc_valid ci repos'
pc_repo 'default_stages: [pre-commit]\nrepos:\n- repo: https://github.com/x/y\n  rev: v1\n  hooks:\n  - id: a\nexclude: ^vendor/\nfail_fast: true\n'
"$l" lite --no-branches >/dev/null
check "when the list items sit at column 0, then they stay in the list and landspec's item joins them before the next key" \
  'before_key "exclude:" && [[ "$(grep "^- repo:" .pre-commit-config.yaml | tail -1)" == "- repo: local" ]] && pc_valid default_stages exclude fail_fast repos'
pc_repo 'repos:\n  - repo: https://github.com/x/y\n    rev: v1\n    hooks:\n      - id: a'
"$l" lite --no-branches >/dev/null
check "when the file has no newline at its end, then the last line stays whole" \
  'grep -qx "      - id: a" .pre-commit-config.yaml && grep -q "^  - repo: local$" .pre-commit-config.yaml && pc_valid repos'
pc_repo 'exclude: ^vendor/'
"$l" lite --no-branches >/dev/null
check "when the file has no repos: key, then it gains one holding landspec's item" 'grep -qx "repos:" .pre-commit-config.yaml && pc_valid exclude repos'
pc_repo 'repos:\n  - repo: https://github.com/x/y\n    rev: v1\n    hooks:\n      - id: a\n'; cp .pre-commit-config.yaml "$TMP/pc.orig"
mkdir -p "$TMP/pc-bad"; printf '#!/bin/sh\nexit 1\n' > "$TMP/pc-bad/pre-commit"; chmod +x "$TMP/pc-bad/pre-commit"
out="$(PATH="$TMP/pc-bad:$PATH" "$l" lite --no-branches)"
check "when pre-commit refuses the result, then the file stays as it was and it gives the lines to add, not a success" \
  'cmp -s "$TMP/pc.orig" .pre-commit-config.yaml && [[ ! -e .pre-commit-config.yaml.tmp ]] && grep -qF "add these lines to it" <<<"$out" && grep -qF "id: landspec-secrets" <<<"$out" && ! grep -q "added to .pre-commit-config" <<<"$out"'
pc_repo 'repos: []\n'; cp .pre-commit-config.yaml "$TMP/pc.orig"
printf '#!/bin/sh\nexit 0\n' > "$TMP/pc-bad/pre-commit"
out="$(PATH="$TMP/pc-bad:$PATH" "$l" lite --no-branches)"
check "when the list is written inline, then the file stays as it was even with a pre-commit that would pass it" \
  'cmp -s "$TMP/pc.orig" .pre-commit-config.yaml && grep -qF "add these lines to it" <<<"$out"'

# ── What the hook lines say: the checks run, or they are not claimed to ──
hook_repo() { rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"; new_repo lite; }
tok="ghp_$(printf 'a%.0s' {1..36})" # built here, so this file holds no token
add_lines="add these lines to it"

hook_repo
mkdir .githooks; printf '#!/bin/sh\n# run secrets.sh here one day\n' > .githooks/pre-commit
git config core.hooksPath .githooks
out="$("$l" lite --no-branches)"
check "when an own .githooks/pre-commit does not call secrets.sh, then it prints the add-these-lines message and not enabled" \
  'grep -q "(.githooks); $add_lines" <<<"$out" && ! grep -q "enabled" <<<"$out"'
hook_repo
mkdir .githooks; printf '#!/bin/sh\necho mine\n' > .githooks/pre-push
out="$("$l" lite --no-branches)"
check "when an own .githooks/pre-push does not call prepush.sh, on a first run too, then it prints the same message and not enabled" \
  'grep -q "(.githooks); $add_lines" <<<"$out" && ! grep -q "enabled" <<<"$out"'

hook_repo
touch .git/hooks/pre-commit.sample
out="$("$l" lite --no-branches)"
check "when .git/hooks holds only samples, then .githooks is enabled and says so" \
  '[[ "$(git config core.hooksPath)" == .githooks ]] && grep -q "^git hooks: enabled (.githooks" <<<"$out"'
hook_repo
printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
out="$("$l" lite --no-branches)"
check "when .git/hooks already has hooks, then core.hooksPath is not set and the message names .git/hooks, not enabled" \
  '[[ -z "$(git config core.hooksPath)" ]] && grep -q "(.git/hooks); $add_lines" <<<"$out" && ! grep -q "enabled" <<<"$out"'
printf '#!/bin/sh\nbash .specify/extensions/landspec/scripts/secrets.sh staged\n' > .git/hooks/pre-commit
printf '#!/bin/sh\nbash .specify/extensions/landspec/scripts/prepush.sh "$@"\n' > .git/hooks/pre-push
out="$("$l" lite --no-branches)"
check "when a .git/hooks file calling the check is not executable, then it is not called enabled" \
  'grep -q "(.git/hooks); $add_lines" <<<"$out" && ! grep -q "enabled" <<<"$out"'
chmod +x .git/hooks/pre-push; out="$("$l" lite --no-branches)"
check "when the lines were added there, then it says so instead of asking again" \
  '[[ -z "$(git config core.hooksPath)" ]] && grep -q "^git hooks: enabled (.git/hooks" <<<"$out" && ! grep -q "$add_lines" <<<"$out"'

hook_repo
mkdir -p "$TMP/home" "$TMP/wide"
printf '#!/bin/sh\ntouch "%s/wide-ran"\n' "$TMP" > "$TMP/wide/pre-commit"; chmod +x "$TMP/wide/pre-commit"
git config --file "$TMP/home/.gitconfig" core.hooksPath "$TMP/wide"
wide() { HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home" "$@"; }
out="$(wide "$l" lite --no-branches)"
check "when core.hooksPath is machine-wide, then it says so, not that it is the repo's own, and not enabled" \
  'grep -q "machine-wide" <<<"$out" && grep -q "$add_lines" <<<"$out" && ! grep -q "this repo already has its own" <<<"$out" && ! grep -q "enabled" <<<"$out"'
check "then no repo setting takes over and a real commit still runs the machine-wide hook" \
  '[[ -z "$(git config --local --get core.hooksPath)" ]] && git add -A && wide git commit --quiet --allow-empty -m wide && [[ -f "$TMP/wide-ran" ]]'

hook_repo
mkdir .husky; printf 'true' > .husky/pre-commit
out="$("$l" lite --no-branches)"
check "when a husky file ends without a newline, then the check starts on its own line" \
  '[[ "$(sed -n 1p .husky/pre-commit)" == true && "$(sed -n 2p .husky/pre-commit)" == "bash .specify/extensions/landspec/scripts/secrets.sh staged" ]]'
check "then both husky files are executable" '[[ -x .husky/pre-commit && -x .husky/pre-push ]]'
check "when core.hooksPath does not reach .husky, then it prints not active in this clone yet and not enabled" \
  'grep -q "not active in this clone yet" <<<"$out" && ! grep -q "enabled" <<<"$out"'
git config core.hooksPath .husky/_
check "when core.hooksPath names a .husky folder that does not exist, then it is not active either" \
  '"$l" lite --no-branches | grep -q "not active in this clone yet"'
git config --unset core.hooksPath
check "when a machine-wide core.hooksPath is in charge, then husky is not active either" \
  'wide "$l" lite --no-branches | grep -q "not active in this clone yet"'
git config core.hooksPath .husky
out="$("$l" lite --no-branches)"
check "when core.hooksPath reaches .husky, then it says added, with no not-active line, and appends nothing twice" \
  'grep -q "^git hooks: added to .husky" <<<"$out" && ! grep -q "not active" <<<"$out" && [[ "$(grep -c "secrets.sh" .husky/pre-commit)" == 1 ]]'
printf 'const t = "%s";\n' "$tok" > app.js; git add app.js
check "then a real commit through the active husky hook is refused by the check" 'fails_with "app.js:1: possible GitHub token" git commit -m token'

# The checks through git itself: a hook replaced by `exit 0` turns these red.
hook_repo
"$l" lite --no-branches >/dev/null
printf 'const t = "%s";\n' "$tok" > app.js; git add app.js
head_before="$(git rev-parse HEAD)"
check "when level.sh set the hooks, then a real git commit of a sample token is refused" \
  'fails_with "app.js:1: possible GitHub token" git commit -m token && [[ "$(git rev-parse HEAD)" == "$head_before" ]]'
git switch --quiet -c feat/token; git commit --quiet --no-verify -m token
check "then a real git push of that commit to origin is refused" \
  'fails_with "app.js:1: possible GitHub token" git push origin feat/token && [[ -z "$(git ls-remote --heads origin feat/token)" ]]'

# ── CI from the constitution's commands, managed files, existing PR gates ──
rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo standard
mkdir -p .specify/memory; cp "$ROOT/preset/templates/constitution-template.md" .specify/memory/constitution.md
printf '[project]\nname="x"\n' > pyproject.toml; touch uv.lock
"$l" standard --no-branches >/dev/null
check "when the constitution's Commands are placeholders, then CI uses the stack defaults and carries the managed-file line" \
  'grep -q "uv run pytest" .github/workflows/ci.yml && [[ "$(head -1 .github/workflows/ci.yml)" == "# landspec: managed file"* ]]'
sed -i.bak 's/^\*\*Commands\*\*.*/**Commands**: build `uv build` · test `uv run pytest -q tests` · lint `uv run ruff check src \&\& uv run mypy src`/' .specify/memory/constitution.md
"$l" standard --no-branches >/dev/null
check "when adopt filled the Commands line, then the managed CI is re-created with those commands: lint, test, build" \
  '[[ "$(grep -o -- "- run: uv run ruff check src && uv run mypy src\|- run: uv run pytest -q tests\|- run: uv build" .github/workflows/ci.yml | tr "\n" "|")" == "- run: uv run ruff check src && uv run mypy src|- run: uv run pytest -q tests|- run: uv build|" ]] && ! grep -q "ruff check \.$" .github/workflows/ci.yml'
check "then the constitution's landspec block runs the suite with that test command" 'grep -qF "\`uv run pytest -q tests\`" .specify/memory/constitution.md'
sed -i.bak '1d' .github/workflows/ci.yml; echo "# edited by hand" >> .github/workflows/ci.yml
"$l" standard --no-branches >/dev/null
check "when the managed-file line is removed, then the file is the user's and is kept" 'grep -q "# edited by hand" .github/workflows/ci.yml'
rm .github/workflows/ci.yml .github/workflows/security.yml
printf 'name: Checks\non:\n  pull_request:\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make test\n' > .github/workflows/checks.yml
out="$("$l" standard --no-branches)"
check "when a workflow of the project's own already checks pull requests, then no second CI is generated and it says which" \
  '[[ ! -f .github/workflows/ci.yml && -f .github/workflows/security.yml ]] && grep -q "checks.yml" <<<"$out"'

# ── Refresh: newer pins kept, files of releases before the marker recognized ──
vn() { (source "$SCRIPTS/lib.sh"; version_newer "$@"); }
check "when versions are compared, then v1.10.0 is newer than v1.9.9 (numbers, not text)" 'vn v1.10.0 v1.9.9 && ! vn v1.9.9 v1.10.0'
check "then v7.0.1 is not newer than v7.1.0, and v2 equals v2.0.0" '! vn v7.0.1 v7.1.0 && vn v7.1.0 v7.0.1 && ! vn v2 v2.0.0 && ! vn v2.0.0 v2'
check "then a branch name like master is never newer" '! vn master v1.0.0 && ! vn v1.0.0 master'

source "$SCRIPTS/pins.sh"; co="${PIN_CHECKOUT%% *}"; co="${co%@*}"
newer="$co@1111111111111111111111111111111111111111 # v99.0.0"; older="$co@2222222222222222222222222222222222222222 # v1.0.0"
sed -i.bak "s|uses: $co@.*|uses: $newer|" .github/workflows/security.yml
out="$("$l" standard --no-branches)"
check "when a managed workflow has a newer checkout pin than pins.sh, then level.sh keeps it and prints kept newer pin" \
  'grep -qF "uses: $newer" .github/workflows/security.yml && ! grep -qF "uses: $PIN_CHECKOUT" .github/workflows/security.yml && [[ "$(grep -cxF "kept newer pin: $co v99.0.0" <<<"$out")" == 1 ]]'
sed -i.bak "s|uses: $co@.*|uses: $older|" .github/workflows/security.yml
out="$("$l" standard --no-branches)"
check "when it has an older pin, then it is replaced by pins.sh's" \
  'grep -qF "uses: $PIN_CHECKOUT" .github/workflows/security.yml && ! grep -qF "$older" .github/workflows/security.yml && ! grep -q "kept newer pin" <<<"$out"'

rm -rf "$TMP/repo" "$TMP/origin.git"; cd "$TMP"
new_repo standard
mkdir -p .githooks .github/workflows
cp "$ROOT/tests/fixtures/v1.3.0-pre-commit" .githooks/pre-commit
cp "$ROOT/tests/fixtures/v1.3.1-close-linked-issues.yml" .github/workflows/close-linked-issues.yml
printf 'version: 2\nupdates: []\n' > .github/dependabot.yml
echo "my own hook" > .githooks/pre-push
out="$("$l" standard --no-branches)"
check "when .githooks/pre-commit is v1.3.0's exact file, then level.sh replaces it and it carries the marker" \
  'head -2 .githooks/pre-commit | grep -q "^# landspec: managed file" && grep -qxF "updated: .githooks/pre-commit" <<<"$out"'
check "when close-linked-issues.yml is v1.3.1's, then it is kept and named with its versions" \
  'cmp -s "$ROOT/tests/fixtures/v1.3.1-close-linked-issues.yml" .github/workflows/close-linked-issues.yml && grep -qF "kept (written by landspec 1.0.0,1.2.0,1.3.0,1.3.1, no marker): .github/workflows/close-linked-issues.yml — delete it to get the current one" <<<"$out"'
check "when an old hook matched, then a generated file without the marker is named as possibly an old release's" \
  'grep -qF "kept (written by landspec 1.2.0,1.3.0,1.3.1 or older, no marker): .github/dependabot.yml — delete it to get the current one" <<<"$out"'
check "then a user's own unmarked file is still kept: as before" \
  '[[ "$(cat .githooks/pre-push)" == "my own hook" ]] && grep -qxF "kept:    .githooks/pre-push" <<<"$out"'

rm -f .github/dependabot.yml
"$l" standard --no-branches >/dev/null
sed -i.bak -e 's#^\# landspec: managed file. /landspec:level#\# jit-speckit: managed file. /jit-speckit:level#' .github/dependabot.yml; rm -f .github/dependabot.yml.bak
echo "# stale" >> .github/dependabot.yml
check "when a generated file has the marker from before 2.0.0, then it is re-created under the new one" \
  'grep -q "^# jit-speckit: managed file" .github/dependabot.yml && "$l" standard --no-branches >/dev/null && grep -q "^# landspec: managed file" .github/dependabot.yml && ! grep -q "stale" .github/dependabot.yml'

# The AWS layer (006): .mcp.json and the "Cloud access" text exist only with aws: on.
cd "$TMP"; rm -rf "$TMP/repo" "$TMP/origin.git"; new_repo standard
cfgf=.specify/extensions/landspec/landspec-config.yml
"$l" standard --no-branches >/dev/null
check "when aws is unset (off by default), then no .mcp.json and no Cloud access section (SC-005)" \
  '[[ ! -e .mcp.json ]] && ! grep -q "Cloud access" .specify/memory/constitution.md && ! grep -q "mcp.json" .specify/landspec-files.sha256'
echo "aws: off" >> "$cfgf"; "$l" full --no-branches >/dev/null
check "when aws is off, then still no .mcp.json and no Cloud access section" \
  '[[ ! -e .mcp.json ]] && ! grep -q "Cloud access" .specify/memory/constitution.md'
set_cfg aws on
out="$("$l" standard --no-branches)"
check "when aws is on and there is no .mcp.json, then level.sh writes it with the pinned proxy, run as the dev agent profile" \
  'grep -qxF "created: .mcp.json" <<<"$out" && grep -qF "\"mcp-proxy-for-aws==1.7.0\"" .mcp.json && grep -qF "\"https://aws-mcp.us-east-1.api.aws/mcp\"" .mcp.json && grep -qF "\"AWS_REGION=us-east-1\"" .mcp.json && grep -qF "\"AWS_PROFILE\": \"landspec-agent-dev\"" .mcp.json && grep -q " .mcp.json$" .specify/landspec-files.sha256'
check "then .mcp.json is valid JSON naming the aws-mcp server" \
  'if command -v python3 >/dev/null; then python3 -c "import json; json.load(open(\".mcp.json\"))[\"mcpServers\"][\"aws-mcp\"]"; else grep -q "\"aws-mcp\": {" .mcp.json; fi'
check "then the constitution has the Cloud access text of lite and standard, inside the landspec block, and not full" \
  'b="$(sed -n "/^<!-- landspec:start/,/^<!-- landspec:end/p" .specify/memory/constitution.md)"; grep -qx "### Cloud access" <<<"$b" && grep -qx "### Cloud access in dev" <<<"$b" && grep -qF "resources that take no role" <<<"$b" && ! grep -q "Cloud access in prod" <<<"$b"'
"$l" lite --no-branches >/dev/null
check "when aws is on at lite, then the agent only reads: no dev applies" \
  'grep -qx "### Cloud access" .specify/memory/constitution.md && ! grep -q "Cloud access in dev" .specify/memory/constitution.md'
"$l" full --no-branches >/dev/null
check "when aws is on at full, then prod changes go only through the pipeline" \
  'grep -qx "### Cloud access in prod" .specify/memory/constitution.md && grep -qx "### Cloud access in dev" .specify/memory/constitution.md'
printf '{ "mcpServers": {} }\n' > .mcp.json; cp .mcp.json "$TMP/mcp.mine"
out="$("$l" standard --no-branches)"
check "when .mcp.json already exists, then it is kept byte for byte and named kept" \
  'cmp -s .mcp.json "$TMP/mcp.mine" && grep -qE "^kept: +\.mcp\.json$" <<<"$out"'
rm .mcp.json; "$l" standard --no-branches >/dev/null; cp .mcp.json "$TMP/mcp.ours"
out="$("$l" standard --no-branches)"
check "when level.sh runs again over its own .mcp.json (no marker), then it is kept as it is" \
  'cmp -s .mcp.json "$TMP/mcp.ours" && grep -qE "^kept: +\.mcp\.json$" <<<"$out"'

exit "$FAIL"
