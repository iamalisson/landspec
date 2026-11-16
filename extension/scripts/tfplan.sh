#!/usr/bin/env bash
# Record what a Terraform plan does, for the diff it was made on, and hold infrastructure PRs to it.
#   tfplan.sh record <planfile> [--chdir <dir>]
#       Reads `terraform show -json <planfile>` with python3 (without python3, `terraform show
#       -no-color`; `tofu` when terraform is missing) and writes or replaces the section of the
#       planned root (the planfile's folder, or <dir>) in this diff's record,
#       .git/landspec-tfplan/<diff id>. Resource addresses and counts only: an attribute value
#       may hold a secret and is never copied. Refuses a planfile older than the last commit,
#       checkout or rebase, or made while a *.tf file is uncommitted.
#       Prints PLAN=create <n> change <n> destroy <n>, then STATEFUL=<replace|destroy> <address>
#       for each stateful resource the plan replaces or destroys.
#   tfplan.sh gate
#       pr.sh's plan gate: only with `aws: on`, a level other than lite and a diff that touches a
#       *.tf file. Refuses without a record, or without a section for each touched root in
#       aws_prod_paths; otherwise prints the "## Terraform plan" section for the PR body.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
here="$(pwd -P)" # the planfile and --chdir are named from where the user ran terraform
landspec_cd_root
top="$(pwd -P)"

# R11: the resource types whose replace or destroy loses data.
STATEFUL_RE='^(aws_db_instance|aws_rds_cluster|aws_s3_bucket|aws_dynamodb_table|aws_kms_key|aws_efs_file_system|aws_elasticache_[a-z0-9_]+|aws_ebs_volume|aws_secretsmanager_secret|aws_cognito_user_pool)$'

# abs <path>: <path>, named from where the script was run, as an absolute physical path.
abs() { local p="$1"; [[ "$p" == /* ]] || p="$here/$p"; (cd "$(dirname "$p")" 2>/dev/null && echo "$(pwd -P)/$(basename "$p")"); }
# rel <abs dir>: that folder from the repository root ("." for the root itself); fails outside it.
rel() { if [[ "$1" == "$top" || "$1" == "$top/." ]]; then echo .; elif [[ "$1" == "$top"/* ]]; then echo "${1#"$top"/}"; else return 1; fi; }

# summarize_json / summarize_text: terraform show's output on stdin, lines "create|change|destroy <n>"
# then "replace|destroy <address>" for the stateful ones. Empty when it is no plan.
summarize_json() {
  python3 -I -c '
import json, re, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
if not isinstance(p, dict) or "format_version" not in p:
    sys.exit(0)
c = u = d = 0
hits = []
for r in p.get("resource_changes") or []:
    a = (r.get("change") or {}).get("actions") or []
    kind = None
    if "delete" in a and "create" in a:
        c += 1; d += 1; kind = "replace"
    elif "delete" in a:
        d += 1; kind = "destroy"
    elif "create" in a:
        c += 1
    elif "update" in a:
        u += 1
    if kind and re.match(sys.argv[1], str(r.get("type", ""))):
        hits.append("%s %s" % (kind, r.get("address", "")))
print("create %d\nchange %d\ndestroy %d" % (c, u, d))
for h in hits:
    print(h)
' "$STATEFUL_RE"
}
summarize_text() {
  # Only the resource headers ("  # <address> must be replaced", two spaces in) and the Plan: line:
  # a value printed deeper in can never pass for an address.
  awk -v re="$STATEFUL_RE" '
    /^Plan: / { plan = 1
      for (i = 2; i <= NF; i++) { n = $(i - 1)
        if ($i == "to" && $(i + 1) == "add,") c = n
        if ($i == "to" && $(i + 1) == "change,") u = n
        if ($i == "to" && $(i + 1) ~ /^destroy[.,]?$/) d = n } next }
    /^No changes\./ { plan = 1; next }
    /^  # .* (must be replaced|will be destroyed)$/ {
      a = substr($0, 5); kind = (a ~ / must be replaced$/) ? "replace" : "destroy"
      sub(/ (must be replaced|will be destroyed)$/, "", a); sub(/ \(deposed object [^)]*\)$/, "", a)
      t = a; while (t ~ /^module\.[^.[]+(\[[^]]*\])?\./) sub(/^module\.[^.[]+(\[[^]]*\])?\./, "", t)
      sub(/\..*$/, "", t)
      if (t ~ re) hits[++h] = kind " " a }
    END { if (!plan) exit
      printf "create %d\nchange %d\ndestroy %d\n", c, u, d
      for (i = 1; i <= h; i++) print hits[i] }'
}

# roots_using <dir>: <dir> and every local module it uses (a source starting ./ or ../ in its *.tf
# files), followed recursively, one repository path per line.
roots_using() {
  local seen=" " todo="$1" d f src m
  while [[ -n "$todo" ]]; do
    d="${todo%%$'\n'*}"; [[ "$todo" == *$'\n'* ]] && todo="${todo#*$'\n'}" || todo=""
    [[ "$seen" != *" $d "* ]] || continue
    seen+="$d "; echo "$d"
    for f in "$d"/*.tf; do
      [[ -f "$f" ]] || continue
      while IFS= read -r src; do
        m="$(cd "$d/$src" 2>/dev/null && pwd -P)" || continue
        m="$(rel "$m")" || continue
        todo+="${todo:+$'\n'}$m"
      done < <(sed -nE 's#^[[:space:]]*source[[:space:]]*=[[:space:]]*"(\.\.?/[^"]*)".*#\1#p' "$f")
    done
  done
}

case "${1:-}" in
  record)
    [[ -n "${2:-}" ]] || die "usage: tfplan.sh record <planfile> [--chdir <dir>]"
    pf="$(abs "$2")" && [[ -f "$pf" && -r "$pf" ]] || die "cannot read the plan file $2; run terraform plan -out=tfplan, then tfplan.sh record tfplan"
    rootabs="$(dirname "$pf")"
    if [[ "${3:-}" == --chdir ]]; then
      [[ -n "${4:-}" ]] || die "usage: tfplan.sh record <planfile> [--chdir <dir>]"
      rootabs="$(cd "$here" && cd "$4" 2>/dev/null && pwd -P)" || die "no folder $4"
    fi
    root="$(rel "$rootabs")" || die "$rootabs is outside the repository"
    # A plan made before the last commit, checkout or rebase, or from uncommitted *.tf, is not this diff's.
    [[ "$pf" -nt "$(git rev-parse --git-path logs/HEAD)" && -z "$(git status --porcelain -- '*.tf')" ]] \
      || die "$2 is older than the last commit, or a *.tf file is uncommitted; plan again after the last commit, checkout or rebase"
    tf=terraform; command -v terraform >/dev/null || tf=tofu
    command -v "$tf" >/dev/null || die "terraform (or tofu) is required to read the plan"
    if command -v python3 >/dev/null; then
      sum="$(cd "$rootabs" && "$tf" show -json "$pf" 2>/dev/null | summarize_json)" || sum=""
    else
      sum="$(cd "$rootabs" && "$tf" show -no-color "$pf" 2>/dev/null | summarize_text)" || sum=""
    fi
    [[ -n "$sum" ]] || die "$tf show could not read $2 as a plan; run terraform plan -out=tfplan in $root again"
    rec="$(diff_record landspec-tfplan)" || exit 1
    tmp="$(mktemp "$rec.XXXXXX")"
    # This root's section replaces its old one; other roots' sections stay as they were. Zero counts
    # are left out, as data-model "Plan record" shows them.
    { [[ ! -f "$rec" ]] || awk -v h="[$root]" '/^\[/ { skip = ($0 == h) } !skip' "$rec"
      echo "[$root]"; awk '!/^(create|change|destroy) 0$/' <<<"$sum"; } > "$tmp"
    mv "$tmp" "$rec"
    echo "PLAN=$(awk 'NR <= 3' <<<"$sum" | tr '\n' ' ' | sed 's/ $//')"
    awk 'NR > 3 { print "STATEFUL=" $0 }' <<<"$sum"
    ;;
  gate)
    [[ "$(cfg aws off)" == on && "$(landspec_level)" != lite ]] || exit 0
    touched="$(git diff --name-only "$(diff_base)" HEAD -- '*.tf')"
    [[ -n "$touched" ]] || exit 0
    rec="$(diff_record landspec-tfplan)" || exit 1
    need="no Terraform plan recorded for this diff; run terraform plan -out=tfplan in"
    run="then bash .specify/extensions/landspec/scripts/tfplan.sh record tfplan"
    [[ -s "$rec" ]] || die "$need $(cfg infra_dir infra), $run"
    tdirs="$(awk '{ if (!sub(/\/[^\/]*$/, "")) $0 = "." } 1' <<<"$touched")" # the folder of each touched file
    IFS=, read -r -a prod <<<"$(cfg aws_prod_paths "")"
    for p in ${prod[@]+"${prod[@]}"}; do
      p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"; p="${p#./}"; p="${p%/}"
      [[ -n "$p" ]] || continue
      ! grep -qxF "[$p]" "$rec" || continue
      # A root the diff deletes still needs its plan: roots_using lists it even without *.tf files.
      while IFS= read -r d; do
        if grep -qxF "$d" <<<"$tdirs"; then die "$need $p, $run"; fi
      done < <(roots_using "$p")
    done
    echo "## Terraform plan"
    awk '
      function flush() { if (r == "") return
        printf "\n### %s\n\n", r
        if (s != "") printf "**Destroys or replaces stateful resources:**\n%s\n", s
        printf "%s\n", (c != "") ? c : "no changes"; r = s = c = "" }
      /^\[/ { flush(); r = substr($0, 2, length($0) - 2); next }
      /^(create|change|destroy) [0-9]+$/ { c = c (c != "" ? " · " : "") $0; next }
      { s = s "- " $1 " `" substr($0, length($1) + 2) "`\n" }
      END { flush() }' "$rec"
    ;;
  *) die "usage: tfplan.sh record <planfile> [--chdir <dir>] | tfplan.sh gate" ;;
esac
