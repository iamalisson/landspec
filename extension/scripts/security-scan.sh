#!/usr/bin/env bash
# Run the deterministic security scanners that are installed and collect their reports.
#   security-scan.sh [--changed]
#     --changed  only the files this branch changed against the base branch (pre-PR check); the
#                summary lines are kept as this diff's record (.git/landspec-security/<diff id>)
# Scanners (each optional; missing ones are reported with how to install them):
#   gitleaks     secrets in files and git history
#   osv-scanner  known vulnerabilities in dependencies (every lockfile)
#   semgrep      code patterns: injection, XSS, SSRF, path traversal, crypto misuse (OWASP rules)
#   zizmor       GitHub Actions workflow weaknesses (injection, excessive permissions, unpinned)
#   trivy        Dockerfile / Terraform / Kubernetes misconfiguration (only when such files exist)
# Reports go to .git/landspec-security/<timestamp>/ so they are never committed or pushed.
# Prints one line per scanner: "<tool> ok|findings|missing|skipped <detail>", then REPORT_DIR=<dir>.
set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
landspec_cd_root

changed=false; [[ "${1:-}" == --changed ]] && changed=true
if $changed; then rec="$(diff_record landspec-security)" || exit 1; fi
# Every worktree shares this folder: the suffix keeps two runs in the same second apart.
dir="$(git rev-parse --git-common-dir)/landspec-security"; mkdir -p "$dir"
dir="$(mktemp -d "$dir/$(date +%Y%m%d-%H%M%S).XXXXXX")" || die "cannot create a report folder in $dir"
summary="$dir/summary.txt"; : > "$summary"

report() { printf '%-12s %-9s %s\n' "$1" "$2" "$3" | tee -a "$summary"; }
missing() { report "$1" missing "install: $2"; }
# With --changed, the summary lines become this diff's record, which pr.sh task requires. Copied
# only once the scan is done, so an interrupted scan records nothing.
finish() { if $changed; then cp "$summary" "$rec"; fi; echo "REPORT_DIR=$dir"; exit 0; }

files=()
if $changed; then
  ref="$(base_ref)" # a stacked branch scans only its own files, not its parent's
  while IFS= read -r f; do [[ -f "$f" ]] && files+=("$f"); done \
    < <(git diff --name-only --diff-filter=ACMR "$(git merge-base HEAD "$ref" 2>/dev/null || echo HEAD)" HEAD; git diff --name-only --diff-filter=ACMR)
  if ((${#files[@]} == 0)); then echo "all skipped no changed files" | tee "$summary"; finish; fi
fi

# gitleaks: exit 1 = leaks found
if command -v gitleaks >/dev/null; then
  if $changed; then gl=(git --log-opts="$(git merge-base HEAD "$ref" 2>/dev/null || echo HEAD~1)..HEAD"); else gl=(git); fi
  if gitleaks "${gl[@]}" --redact --no-banner --report-format json --report-path "$dir/gitleaks.json" >/dev/null 2>&1; then
    report gitleaks ok "no secrets"
  else report gitleaks findings "$dir/gitleaks.json"; fi
else missing gitleaks "https://github.com/gitleaks/gitleaks#installing (brew install gitleaks)"; fi

# osv-scanner: exit 1 = vulnerabilities, 128 = no lockfiles
if command -v osv-scanner >/dev/null; then
  osv-scanner scan source -r --format json --output "$dir/osv.json" . >/dev/null 2>&1
  case $? in
    0) report osv-scanner ok "no known vulnerable dependencies" ;;
    128) report osv-scanner skipped "no lockfiles found" ;;
    *) report osv-scanner findings "$dir/osv.json" ;;
  esac
else missing osv-scanner "https://google.github.io/osv-scanner/installation/ (brew install osv-scanner)"; fi

# semgrep: --error makes findings exit 1
if command -v semgrep >/dev/null; then
  targets=("."); $changed && targets=("${files[@]}")
  rc=0; semgrep scan --config p/default --config p/owasp-top-ten --error --quiet --metrics off \
       --json --output "$dir/semgrep.json" "${targets[@]}" >/dev/null 2>"$dir/semgrep.log" || rc=$?
  if [[ $rc == 0 ]]; then report semgrep ok "no code findings"
  elif [[ $rc == 1 ]]; then report semgrep findings "$dir/semgrep.json"
  elif [[ -s "$dir/semgrep.log" ]]; then report semgrep failed "exit $rc from semgrep: code patterns not scanned; see $dir/semgrep.log"
  else
    # With --json --output semgrep puts its error in the JSON. Only the text after "errors" is read,
    # since each result before it has its own "message". grep and sed: busybox has no jq or python3.
    msg="$(tr -d '\n' < "$dir/semgrep.json" 2>/dev/null | sed -n 's/.*"errors"[[:space:]]*://p' \
      | grep -oE '"message"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -n 1 \
      | sed -e 's/^"message"[[:space:]]*:[[:space:]]*"//' -e 's/"$//' -e 's/\\n.*//' -e 's/\\"/"/g')"
    if [[ -n "$msg" ]]; then report semgrep failed "exit $rc: ${msg:0:200}; see $dir/semgrep.json"
    else report semgrep failed "exit $rc: semgrep wrote no error ($dir/semgrep.log and $dir/semgrep.json are empty)"; fi
  fi
else missing semgrep "uv tool install semgrep (or pipx install semgrep)"; fi

# zizmor: only when there are workflows
if compgen -G ".github/workflows/*.y*ml" >/dev/null; then
  if command -v zizmor >/dev/null; then
    if zizmor --format json .github/workflows > "$dir/zizmor.json" 2>/dev/null; then
      report zizmor ok "workflows clean"
    else report zizmor findings "$dir/zizmor.json"; fi
  else missing zizmor "uv tool install zizmor (or brew install zizmor)"; fi
else report zizmor skipped "no GitHub workflows"; fi

# trivy config: only when infrastructure files exist
# (the same Dockerfile/Terraform check as the CI gate, plus Kubernetes manifests)
if [[ -n "$(infra_files)" || -n "$(git ls-files '*.yaml' '*.yml' 2>/dev/null | grep -E 'k8s|kubernetes|helm' || true)" ]]; then
  if command -v trivy >/dev/null; then
    if trivy config --exit-code 1 --severity HIGH,CRITICAL --format json --output "$dir/trivy.json" . >/dev/null 2>&1; then
      report trivy ok "no high/critical misconfiguration"
    else report trivy findings "$dir/trivy.json"; fi
  else missing trivy "https://trivy.dev (verify the release; trivy-action was compromised in March 2026)"; fi
else report trivy skipped "no Dockerfile/Terraform/Kubernetes files"; fi

finish
