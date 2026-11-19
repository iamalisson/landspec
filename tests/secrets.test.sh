#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
s="$SCRIPTS/secrets.sh"
staged() { git add -- "$@"; }
reset() { git reset --quiet; git clean -fdq -e .specify; }

new_repo standard

echo "DB_PASSWORD=hunter22hunter" > .env; staged .env
check "when a .env file is staged, then the commit is refused" 'fails_with ".env: secret-bearing file" "$s" staged'
reset

echo "API_KEY=" > .env.example; staged .env.example
check "when only .env.example is staged, then it passes" '"$s" staged'
reset
echo "API_KEY=" > .env.dist; staged .env.dist
check "when only .env.dist is staged, then it passes" '"$s" staged'
reset

echo "{}" > prod.tfstate; staged prod.tfstate
check "when a Terraform state file is staged, then it is refused" 'fails_with "prod.tfstate: secret-bearing file" "$s" staged'
reset

echo "X=1" > .ENV; mkdir -p certs; echo x > certs/key.PEM; staged .ENV certs/key.PEM
check "when a secret-bearing file name is in upper case (.ENV, key.PEM), then it is still refused" \
  'out="$("$s" staged 2>&1)" && exit 1; grep -q ".ENV: secret-bearing file" <<<"$out" && grep -q "certs/key.PEM: secret-bearing file" <<<"$out"'
reset

mkdir -p café; echo "X=1" > café/.env; staged café/.env
check "when a .env sits under a non-ASCII path, then it is refused by its real name" 'fails_with "café/.env: secret-bearing file" "$s" staged'
reset
printf 'k = "AKIA%s"\n' "$(printf 'A%.0s' {1..16})" > ação.py; staged ação.py
check "when a secret is in a file with a non-ASCII name, then the finding names that file" 'fails_with "ação.py:1: possible AWS access key" "$s" staged'
reset

printf '++ t = "ghp_%s"\n' "$(printf 'a%.0s' {1..36})" > notes.txt; staged notes.txt
check "when an added line itself starts with ++, then it is still scanned" 'fails_with "notes.txt:1: possible GitHub token" "$s" staged'
reset

printf 'see task-assessment-for-the-new-customer-onboarding-flow-v2\n<div class="risk-assessment-panel-header-with-a-very-long-name">\nakiaabcdefghijklmnop\n' > notes.md; staged notes.md
check "when lowercase prose, a slug or a CSS class only looks like a key without case, then it passes" '"$s" staged'
reset

mkdir -p keys; printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > keys/deploy; staged keys/deploy
check "when a private key is staged under any name, then it is refused" 'fails_with "keys/deploy:1: possible private key" "$s" staged'
reset

printf 'x\n\nconst t = "ghp_%s";\n' "$(printf 'a%.0s' {1..36})" > app.js; staged app.js
check "when a GitHub token is in an added line, then it is refused with its file, line and kind" 'fails_with "app.js:3: possible GitHub token" "$s" staged'
check "then not even part of the token is printed" 'out="$("$s" staged 2>&1)" && exit 1; [[ $out == *refusing* ]] && ! grep -qE "ghp_|aaaa" <<<"$out"'
reset

printf 'aws_access_key_id = AKIAABCDEFGHIJKLMNOP\npassword = "hunter2hunter2"\n' > settings.ini; staged settings.ini
check "when an AWS key and a hard-coded password are added, then both are refused, without their values" \
  'out="$("$s" staged 2>&1)" && exit 1; grep -q "settings.ini:1: possible AWS access key" <<<"$out" && grep -q "settings.ini:2: possible hard-coded credential" <<<"$out" && ! grep -qE "AKIA|hunter2" <<<"$out"'
reset

seq 1 5000 | sed 's/^/const value_/; s/$/ = 1/' > big.js; staged big.js
check "when a 5000-line file is staged, then the scan takes under 10 seconds" \
  'start=$(date +%s); "$s" staged; (( $(date +%s) - start < 10 ))'
reset

printf 'url = "postgres://app:s3cretpw@db:5432/app"\n' > cfg.toml; staged cfg.toml
check "when a database URL carries a password, then it is refused" 'fails_with "cfg.toml" "$s" staged'
reset
printf 'remote = https://deploy:%s@git.example.com/app.git\n' "s3cretpw" > cfg.ini; staged cfg.ini
check "when an https URL carries a password, then it is refused" 'fails_with "cfg.ini:1: possible URL with a password" "$s" staged'
reset

printf 'aws = "AKIAABCDEFGHIJKLMNOP"  # landspec:allow-secret (AWS docs example key)\n' > doc.py; staged doc.py
check "when the line is marked landspec:allow-secret, then it passes" '"$s" staged'
printf 'aws = "AKIAABCDEFGHIJKLMNOP"  # jit:allow-secret (AWS docs example key)\n' > doc.py; staged doc.py
check "when the line carries the mark from before 2.0.0, then it still passes" '"$s" staged'
reset

printf 'password = os.environ["DB_PASSWORD"]\ntoken: ${{ secrets.TOKEN }}\nconst apiKey = process.env.API_KEY\n' > ok.py; staged ok.py
check "when secrets come from the environment, then it passes (no false positive)" '"$s" staged'
reset

git switch --quiet -c feat/x
printf 'k = "sk_live_%s"\n' "$(printf 'b%.0s' {1..24})" > pay.rb; git add pay.rb; git commit --quiet --no-verify -m leak
check "when a commit made with --no-verify is pushed, then the range check finds it" 'fails_with "pay.rb:1: possible Stripe live key" "$s" range HEAD~1 HEAD'

printf 'ok\n' > pay.rb; git commit --quiet --no-verify -am "remove the key again"
check "when a secret is added and removed again within one push, then the range check still finds it" \
  'fails_with "pay.rb:1: possible Stripe live key" "$s" range HEAD~2 HEAD'
git reset --quiet --hard HEAD~1

zero=0000000000000000000000000000000000000000
check "when pushing a branch whose commits leak a secret, then pre-push refuses" \
  'fails_with "pay.rb" bash "$SCRIPTS/prepush.sh" <<<"refs/heads/feat/x $(git rev-parse HEAD) refs/heads/feat/x $zero"'
unknown=1111111111111111111111111111111111111111
check "when the remote's tip was never fetched (moved on, or a --force), then pre-push scans what no remote has instead of failing on the range" \
  'out="$(bash "$SCRIPTS/prepush.sh" <<<"refs/heads/feat/x $(git rev-parse HEAD) refs/heads/feat/x $unknown" 2>&1)" && exit 1; [[ $out == *pay.rb* && $out != *fatal* ]]'
check "then a clean push over an unfetched remote tip passes" \
  'bash "$SCRIPTS/prepush.sh" <<<"refs/heads/feat/x $(git rev-parse HEAD~1) refs/heads/feat/x $unknown"'
check "when pushing straight to develop on standard, then pre-push refuses" \
  'fails_with "open a pull request" bash "$SCRIPTS/prepush.sh" <<<"refs/heads/develop $(git rev-parse HEAD~1) refs/heads/develop $(git rev-parse HEAD~1)"'
check "when a remote branch is deleted, then prepush.sh lets it through, a protected one too" \
  'bash "$SCRIPTS/prepush.sh" <<<"(delete) $zero refs/heads/develop $(git rev-parse HEAD~1)"'
set_cfg level lite
check "when the level is lite, then a push straight to main passes" \
  'bash "$SCRIPTS/prepush.sh" <<<"refs/heads/main $(git rev-parse HEAD~1) refs/heads/main $(git rev-parse HEAD~1)"'
check "then a secret in that push is still refused" \
  'fails_with "pay.rb" bash "$SCRIPTS/prepush.sh" <<<"refs/heads/main $(git rev-parse HEAD) refs/heads/main $(git rev-parse HEAD~1)"'
set_cfg level standard

# Lines added while resolving a merge are part of the push too.
git switch --quiet -c side; echo side > side.txt; git add side.txt; git commit --quiet --no-verify -m side
git switch --quiet feat/x; base_before="$(git rev-parse HEAD)"; echo x > x.txt; git add x.txt; git commit --quiet --no-verify -m x
git merge --quiet --no-commit side >/dev/null 2>&1 || true
printf 'k = "AKIAABCDEFGHIJKLMNOP"\n' > merged.txt; git add merged.txt; git commit --quiet --no-verify -m "merge side"
check "when a secret is added while resolving a merge, then the range check finds it" \
  'fails_with "merged.txt:1: possible AWS access key" "$s" range "$base_before" HEAD'

# The user's git config must not blind the scanner.
git config color.ui always; git config diff.noprefix true
check "when git is set to color.ui=always and diff.noprefix, then the scan still finds the secret and its file" \
  'fails_with "merged.txt:1: possible AWS access key" "$s" range "$base_before" HEAD'
git config --unset color.ui; git config --unset diff.noprefix

# A first push of a brand-new repo: the root commit itself carries the secret, and no remote has
# anything yet. Nothing may be skipped.
mkdir -p "$TMP/fresh" && cd "$TMP/fresh" && git init --quiet -b feat/first && git config user.email t@t && git config user.name t
mkdir -p .specify/extensions/landspec && ln -s "$SCRIPTS" .specify/extensions/landspec/scripts
printf 'key = "sk_live_%s"\n' "$(printf 'c%.0s' {1..24})" > root.rb; git add root.rb; git commit --quiet --no-verify -m root
# A feature branch, so the secret scan (not the protected-branch rule) is what refuses.
check "when the first push of a new repo has a secret in the root commit, then pre-push refuses" \
  'fails_with "root.rb:1: possible Stripe live key" bash "$SCRIPTS/prepush.sh" <<<"refs/heads/feat/first $(git rev-parse HEAD) refs/heads/feat/first $zero"'

# A brand-new repository on level standard: the remote is empty, so the first push of the setup
# to the default branch has no PR to go through. It is allowed once, and still scanned.
git init --quiet --bare "$TMP/empty.git"
mkdir -p "$TMP/boot" && cd "$TMP/boot" && git init --quiet -b main && git config user.email t@t && git config user.name t
git remote add origin "$TMP/empty.git"
mkdir -p .specify/extensions/landspec && ln -s "$SCRIPTS" .specify/extensions/landspec/scripts
printf 'level: standard\n' > .specify/extensions/landspec/landspec-config.yml
echo setup > README.md; git add README.md; git commit --quiet --no-verify -m setup
check "when the first push of a new repo goes to its empty remote, then main is allowed once and says so" \
  'bash "$SCRIPTS/prepush.sh" origin "$TMP/empty.git" <<<"refs/heads/main $(git rev-parse HEAD) refs/heads/main $zero" 2>&1 | gq "first push to an empty repository"'
printf 'k = "sk_live_%s"\n' "$(printf 'd%.0s' {1..24})" > boot.rb; git add boot.rb; git commit --quiet --no-verify -m leak
check "then that first push is still scanned: a secret in it is refused" \
  'fails_with "boot.rb:1: possible Stripe live key" bash "$SCRIPTS/prepush.sh" origin "$TMP/empty.git" <<<"refs/heads/main $(git rev-parse HEAD) refs/heads/main $zero"'
git reset --quiet --hard HEAD~1; git push --quiet --no-verify origin main
echo more >> README.md; git commit --quiet --no-verify -am more
check "when the remote already has branches, then pushing straight to main is refused again" \
  'fails_with "open a pull request" bash "$SCRIPTS/prepush.sh" origin "$TMP/empty.git" <<<"refs/heads/main $(git rev-parse HEAD) refs/heads/main $(git rev-parse HEAD~1)"'


# Under the pre-commit framework the hook gets no stdin: the push comes as PRE_COMMIT_* variables
# (measured with pre-commit 4.7.0 on 2026-11-04: args and stdin empty, one ref, the variables below).
pc=(env "PRE_COMMIT_TO_REF=$(git rev-parse HEAD)" "PRE_COMMIT_FROM_REF=$(git rev-parse HEAD~1)" PRE_COMMIT_LOCAL_BRANCH=refs/heads/main PRE_COMMIT_REMOTE_BRANCH=refs/heads/main PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT=1)
check "when pre-commit runs the push hook (no stdin, PRE_COMMIT_* set), then a push straight to main is still refused" \
  'fails_with "open a pull request" "${pc[@]}" bash "$SCRIPTS/prepush.sh" </dev/null'
git switch --quiet -c feat/pc; printf 'k = "sk_live_%s"\n' "$(printf 'e%.0s' {1..24})" > pc.rb; git add pc.rb; git commit --quiet --no-verify -m leak
pc=(env "PRE_COMMIT_TO_REF=$(git rev-parse HEAD)" "PRE_COMMIT_FROM_REF=$(git rev-parse HEAD~1)" PRE_COMMIT_LOCAL_BRANCH=refs/heads/feat/pc PRE_COMMIT_REMOTE_BRANCH=refs/heads/feat/pc PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT=1)
check "then a secret in the pushed commits is found through those variables too" \
  'fails_with "pc.rb:1: possible Stripe live key" "${pc[@]}" bash "$SCRIPTS/prepush.sh" </dev/null'

# ── FR-022: one sample per pattern, through staged and through range ──
# Every sample is assembled here from its prefix and a run of one letter, so this file holds none.
rep() { printf '%*s' "$2" '' | tr ' ' "$1"; } # rep <char> <n>
sample() { # sample <kind>: the added line for that kind of secret
  case "$1" in
    "AWS access key") echo "id = AKIA$(rep A 16)" ;;
    "GitHub token") echo "t = gh$(rep p 1)_$(rep a 36)" ;;
    "GitHub fine-grained token") echo "t = github_pat_$(rep a 60)" ;;
    "GitLab token") echo "t = glpat-$(rep a 20)" ;;
    "Slack token") echo "t = xoxb-$(rep a 10)" ;;
    "Stripe live key") echo "t = sk_live_$(rep a 24)" ;;
    "Google API key") echo "t = AIza$(rep a 35)" ;;
    "Anthropic key") echo "t = sk-ant-$(rep a 20)" ;;
    "OpenAI key") echo "t = sk-$(rep a 40)" ;;
    "SendGrid key") echo "t = SG.$(rep a 22).$(rep a 43)" ;;
    "private key") printf "%s%s\n" "-----BEGIN RSA " "PRIVATE KEY-----" ;;
    "URL with a password") echo "u = mongodb+srv://app:$(rep a 8)@db/app" ;;
    "AWS secret key") echo "aws_secret_access_key = $(rep a 40)" ;;
    "npm token") echo "//registry.npmjs.org/:_authToken=npm_$(rep a 36)" ;;
    "JSON web token") echo "t = eyJ$(rep a 12).eyJ$(rep a 12).$(rep a 12)" ;;
    "hard-coded credential") echo "client_secret = \"$(rep a 12)\"" ;;
  esac
}
kinds=("AWS access key" "GitHub token" "GitHub fine-grained token" "GitLab token" "Slack token" "Stripe live key" "Google API key"
  "Anthropic key" "OpenAI key" "SendGrid key" "private key" "URL with a password" "hard-coded credential"
  "AWS secret key" "npm token" "JSON web token")
mkdir -p "$TMP/pats" && cd "$TMP/pats" && git init --quiet -b feat/pats && git config user.email t@t && git config user.name t
mkdir -p .specify/extensions/landspec && ln -s "$SCRIPTS" .specify/extensions/landspec/scripts
echo ok > f.txt; git add f.txt; git commit --quiet --no-verify -m base
for kind in "${kinds[@]}"; do
  sample "$kind" > f.txt; git add f.txt
  check "when a $kind is staged, then it is refused as that kind, by file and line" 'fails_with "f.txt:1: possible $kind" "$s" staged'
  git commit --quiet --no-verify -m "add $kind"
  check "when a commit with a $kind is pushed, then the range check refuses it as that kind" 'fails_with "f.txt:1: possible $kind" "$s" range HEAD~1 HEAD'
  echo ok > f.txt; git commit --quiet --no-verify -am "clean"
done

exit "$FAIL"
