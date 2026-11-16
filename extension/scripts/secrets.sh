#!/usr/bin/env bash
# Fast secret check, run by the git pre-commit and pre-push hooks.
#   secrets.sh staged            check what is about to be committed
#   secrets.sh range <from> <to> check every commit in from..to, one by one (a secret added and
#                                removed again in the same push is still caught)
#   secrets.sh range - <to>      check every commit reachable from <to> that no remote has yet
# Refuses secret-bearing files (.env, private keys, credential files) and secret-looking added
# lines. Uses gitleaks when installed; the built-in patterns below always run too.
# A line can be allowed on purpose with a trailing comment containing "landspec:allow-secret".
# Exits 1 with findings as file:line and the kind of secret, never the secret itself; 0 when clean.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
landspec_cd_root

mode="${1:-staged}"
# Non-ASCII paths come back as written (café/.env), not quoted and escaped, so the file rules and
# the file:line of each finding see the real name.
git() { command git -c core.quotePath=false "$@"; }
# The diff format is pinned, whatever the user's git config says: color.ui=always or
# diff.noprefix would otherwise hide every added line from the parser below. Merge commits are
# diffed against their first parent, so lines added while resolving a merge are scanned too.
fmt=(--no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/)
case "$mode" in
  staged) files="$(git diff --cached --no-color --name-only --diff-filter=ACMR)"
          diff="$(git diff --cached "${fmt[@]}" --unified=0 --diff-filter=ACMR)" ;;
  range) [[ -n "${2:-}" && -n "${3:-}" ]] || die "usage: secrets.sh range <from|-> <to>"
         if [[ "$2" == - ]]; then revs=("$3" --not --remotes); else revs=("$2..$3"); fi
         files="$(git log --no-color --diff-merges=first-parent --name-only --format= --diff-filter=ACMR "${revs[@]}" | sort -u)"
         diff="$(git log -p "${fmt[@]}" --diff-merges=first-parent --unified=0 --format= --diff-filter=ACMR "${revs[@]}")" ;;
  *) die "usage: secrets.sh staged | secrets.sh range <from|-> <to>" ;;
esac

findings=()

# Files that should never be committed, whatever their case (.ENV, key.PEM). Templates
# (.env.example etc.) are fine.
shopt -s nocasematch
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  base="${f##*/}"
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist) continue ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.jks|*.keystore|id_rsa|id_dsa|id_ecdsa|id_ed25519|*.tfstate|*.tfstate.backup|credentials.json|service-account*.json|.netrc|.pgpass)
      findings+=("$f: secret-bearing file") ;;
  esac
done <<<"$files"
shopt -u nocasematch

# Added lines that look like credentials (provider formats first, then generic assignments).
# Provider formats are case-sensitive, as the providers issue them: matched without case, lowercase
# prose (AKIA…) and slugs (task-assessment-… holds "sk-…") were refused. Flag i: any case.
# A key that can sit inside a word (sk-) must start one, so risk-… and task-… never match.
names=(); patterns=(); nocase=()
add() { names+=("$1"); patterns+=("$2"); nocase+=("${3:-}"); }
add "AWS access key"          'AKIA[0-9A-Z]{16}'
add "AWS secret key"          'aws_?secret_?access_?key["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+]{40}' i
add "GitHub token"            'gh[pousr]_[A-Za-z0-9]{36,}'
add "GitHub fine-grained token" 'github_pat_[A-Za-z0-9_]{60,}'
add "GitLab token"            'glpat-[A-Za-z0-9_-]{20,}'
add "Slack token"             'xox[abprs]-[A-Za-z0-9-]{10,}'
add "Stripe live key"         'sk_live_[A-Za-z0-9]{20,}'
add "Google API key"          'AIza[0-9A-Za-z_-]{35}'
add "npm token"               'npm_[A-Za-z0-9]{36}'
add "Anthropic key"           '(^|[^A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{20,}'
add "OpenAI key"              '(^|[^A-Za-z0-9_-])sk-(proj-)?[A-Za-z0-9_-]{40,}'
add "SendGrid key"            'SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}'
add "JSON web token"          'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
add "private key"             '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
add "URL with a password"     '(https?|ftp|postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^:/@ ]+:[^@ ]{3,}@' i
add "hard-coded credential"   '(password|passwd|secret|api_?key|access_?token|auth_?token|client_?secret)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'$<{ ]{8,}["'"'"']' i

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: > "$tmp/cs"; : > "$tmp/ci"
for k in "${!patterns[@]}"; do
  if [[ -n "${nocase[$k]}" ]]; then echo "${patterns[$k]}" >> "$tmp/ci"; else echo "${patterns[$k]}" >> "$tmp/cs"; fi
done
# One line per added line: where it is (meta) and what it says (text), in the same order.
# Lines marked landspec:allow-secret (or jit:allow-secret, the name before 2.0.0) are blanked, so they never match.
# A hunk's header says how many lines it adds; those are read as lines whatever they start with,
# so an added "++…" line is scanned, not taken for a "+++" file header.
awk -v meta="$tmp/meta" -v text="$tmp/text" '
  left > 0 && /^\+/ { s = substr($0, 2); if (index(s, "landspec:allow-secret") || index(s, "jit:allow-secret")) s = ""
           print file ":" line > meta; print s > text; line++; left--; next }
  left > 0 && /^[-\\]/ { next }
  /^\+\+\+ b\// { file = substr($0, 7); left = 0; next }
  /^@@/ { c = split($3, n, ","); line = substr(n[1], 2) + 0; left = (c > 1) ? n[2] + 0 : 1; next }
' <<<"$diff"
touch "$tmp/meta" "$tmp/text"
# One grep per case rule over every added line. Only matching line numbers come back: never the text.
while IFS= read -r n; do
  where="$(sed -n "${n}p" "$tmp/meta")"; text="$(sed -n "${n}p" "$tmp/text")"
  kind="secret"
  for k in "${!patterns[@]}"; do
    if grep -q${nocase[$k]}E -e "${patterns[$k]}" <<<"$text"; then kind="${names[$k]}"; break; fi
  done
  findings+=("$where: possible $kind")
done < <({ grep -nE -f "$tmp/cs" "$tmp/text"; grep -niE -f "$tmp/ci" "$tmp/text"; } | cut -d: -f1 | sort -un || true)

if command -v gitleaks >/dev/null; then
  if [[ "$mode" == staged ]]; then
    gitleaks git --pre-commit --staged --redact --no-banner >/dev/null 2>&1 || findings+=("gitleaks: secrets found (run: gitleaks git --pre-commit --staged --redact -v)")
  else
    opts="$2..$3"; [[ "$2" == - ]] && opts="$3 --not --remotes"
    gitleaks git --log-opts="$opts" --redact --no-banner >/dev/null 2>&1 || findings+=("gitleaks: secrets found (run: gitleaks git --log-opts=\"$opts\" --redact -v)")
  fi
fi

if ((${#findings[@]})); then
  echo "landspec: refusing: possible secrets" >&2
  printf '  %s\n' "${findings[@]}" >&2
  cat >&2 <<'EOF'
  Remove them (and rotate any real credential that was ever committed or pushed).
  Load secrets from the environment and keep a .env.example with the keys only.
  A false positive can be allowed on that line with a comment containing: landspec:allow-secret
EOF
  exit 1
fi
