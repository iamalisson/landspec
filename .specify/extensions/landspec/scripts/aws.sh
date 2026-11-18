#!/usr/bin/env bash
# The AWS access layer: configure the project and print what the human deploys (setup: never
# calls aws); check which identity Claude's AWS calls run as (check: read calls only).
#   aws.sh setup [--prod-profiles a,b] [--prod-paths p,q]
#   aws.sh setup --scp   prints the organization policy's path and how to attach it; changes nothing
# Sets aws: on, aws_agent_role (kept when set), the prod lists (only for a flag that is given: an
# omitted flag keeps the current value, an empty one empties it) and infra_dir (only when unset).
# Re-runs level.sh at the current level (.mcp.json, the "Cloud access" constitution text), then
# prints the entries to add by hand ("add to <file>: <entry>"), a "pin:" line for an .mcp.json
# that pins another proxy release, one "deploy: <command>" line per account kind and the
# ~/.aws/config profiles. Existing .mcp.json and .claude/settings.json are never rewritten.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=pins.sh
source "$LANDSPEC_EXT_DIR/scripts/pins.sh"

# The client entries setup prints and check reports missing; the Read denies matter because the
# guard sees Bash only.
client_entries=(allow:mcp__aws-mcp__aws___search_documentation allow:mcp__aws-mcp__aws___read_documentation
  allow:mcp__aws-mcp__aws___retrieve_skill allow:mcp__aws-mcp__aws___list_regions
  allow:mcp__aws-mcp__aws___get_regional_availability
  ask:mcp__aws-mcp__aws___run_script ask:mcp__aws-mcp__aws___get_presigned_url
  'deny:Read(./.env*)' 'deny:Read(**/*.tfstate*)')

#   aws.sh check [--simulate]
# Which identity Claude's AWS calls run as: only the agent role passes (exit 0). Prints IDENTITY=,
# ACCOUNT=, ROLE=, ACCESS=, PROD= (the prod profiles, or none: information only, never the verdict)
# and a "missing: <entry>" line per absent .mcp.json server or client entry; --simulate asks
# IAM's policy simulator whether each denied action is denied. Read calls only (sts
# get-caller-identity, iam get-role, iam simulate-principal-policy); never prints a key.
if [[ "${1:-}" == check ]]; then
  case "${2:-}" in "") sim=false ;; --simulate) sim=true ;; *) die "usage: aws.sh check [--simulate]" ;; esac
  (($# <= 2)) || die "usage: aws.sh check [--simulate]"
  landspec_cd_root
  role="$(cfg aws_agent_role landspec-agent)"; profile=landspec-agent-dev
  # str <key>: the first "<key>": "<value>" of the JSON on stdin, pretty or on one line.
  str() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/' || true; }
  if ! command -v aws >/dev/null 2>&1; then
    echo "IDENTITY=no-cli"
    die "the AWS CLI is not installed: install AWS CLI v2 (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), then run /landspec:aws again"
  fi
  if ! id="$(aws sts get-caller-identity --output json 2>/dev/null)"; then
    echo "IDENTITY=no-credentials"
    die "no AWS credentials: sign in with aws sso login --profile <your sso profile>, then use AWS_PROFILE=$profile"
  fi
  arn="$(str Arn <<<"$id")"; account="$(str Account <<<"$id")"
  res="${arn#*:*:*:*:*:}" # assumed-role/<role>/<session>, user/<path/>name, root
  access=unknown
  case "$res" in
    "assumed-role/$role/"*)
      verdict=agent; name="$role"
      # The tag's Value follows its Key in AWS's output; anything but read or build is unknown.
      tag="$(aws iam get-role --role-name "$role" --output json 2>/dev/null \
           | grep -oE '"(Key|Value)"[[:space:]]*:[[:space:]]*"[^"]*"' \
           | awk -F'"' '$2 == "Key" { k = $4; next } k == "landspec:access" { print $4; exit }' || true)"
      case "$tag" in read | build) access="$tag" ;; esac ;;
    user/*) verdict=user; name="${res##*/}" ;;
    *) verdict=other-role; name="${res#assumed-role/}"; name="${name%%/*}" ;;
  esac
  echo "IDENTITY=$verdict"; echo "ACCOUNT=$account"
  echo "ROLE=$([[ "$verdict" == user ]] || echo "$name")"; echo "ACCESS=$access"
  prod="$(cfg aws_prod_profiles "")"
  echo "PROD=${prod:-none: no prod configured (one account only; /landspec:aws --prod-profiles <names> adds one)}"
  grep -qF '"aws-mcp"' .mcp.json 2>/dev/null || echo "missing: .mcp.json: the aws-mcp server"
  for e in "${client_entries[@]}"; do
    if ! grep -qF "\"${e#*:}\"" .claude/settings.json 2>/dev/null; then echo "missing: .claude/settings.json: permissions.${e%%:*} \"${e#*:}\""; fi
  done
  case "$verdict" in
    user)
      echo "landspec: this is your own IAM user $name, not $role; use the profile that assumes $role (aws sso login --profile $profile)" >&2
      if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_SESSION_TOKEN:-}" ]]; then
        echo "landspec: it is a long-lived access key: remove it from the environment" >&2
      fi
      exit 1 ;;
    other-role) die "this is role $name, not $role; use the profile that assumes $role (AWS_PROFILE=$profile)" ;;
  esac
  $sim || exit 0
  # The simulator takes no wildcard: a wildcard entry's second column is its concrete action.
  lists="$LANDSPEC_EXT_DIR/aws/denied-actions.txt"
  [[ "$access" == read ]] && lists+=" $LANDSPEC_EXT_DIR/aws/denied-read-actions.txt"
  # shellcheck disable=SC2086  # $lists is two known paths without spaces
  actions="$(awk 'NF { print (NF > 1 ? $2 : $1) }' $lists)"
  part="${arn#arn:}"; part="${part%%:*}"
  # shellcheck disable=SC2086  # one argument per action
  out="$(aws iam simulate-principal-policy --policy-source-arn "arn:$part:iam::$account:role/$role" \
         --action-names $actions --output json)" || die "the policy simulation failed (the role needs iam:SimulatePrincipalPolicy on itself)"
  # "<action> <decision>" per result: each EvalDecision follows its EvalActionName.
  pairs="$(grep -oE '"Eval(ActionName|Decision)"[[:space:]]*:[[:space:]]*"[^"]*"' <<<"$out" \
           | awk -F'"' '$2 == "EvalActionName" { a = $4; next } { print a, $4 }' || true)"
  bad=0
  for act in $actions; do
    d="$(awk -v a="$act" '$1 == a { print $2; exit }' <<<"$pairs")"
    case "$d" in
      implicitDeny | explicitDeny) echo "denied $act" ;;
      allowed) echo "ALLOWED $act"; bad=1 ;;
      *) echo "unknown $act: the simulation gave no decision"; bad=1 ;;
    esac
  done
  exit "$bad"
fi

usage="usage: aws.sh setup [--prod-profiles a,b] [--prod-paths p,q] | setup --scp"
[[ "${1:-}" == setup ]] || die "$usage"; shift
set_profiles=false; set_paths=false
# Checked before anything is written. A quote, | or & in a name would break the config line
# (cfg_set is a sed s|||); a leading - is a flag given where a value was due.
names() { [[ "$2" =~ ^[A-Za-z0-9_.,/@+=:-]*$ && "$2" != -* ]] || die "$1 takes comma-separated names (letters, digits and _ . / @ + = : -): $2"; }
while (($#)); do
  case "$1" in
    --prod-profiles) (($# >= 2)) || die "$usage"; names aws_prod_profiles "$2"; set_profiles=true; profiles="$2"; shift 2 ;;
    --prod-paths) (($# >= 2)) || die "$usage"; names aws_prod_paths "$2"; set_paths=true; paths="$2"; shift 2 ;;
    --scp) (($# == 1)) && [[ -z "${profiles+x}${paths+x}" ]] || die "$usage"; scp=true; shift ;;
    *) die "$usage" ;;
  esac
done

landspec_cd_root
[[ -f "$LANDSPEC_CONFIG" ]] || die "not a landspec project (no $LANDSPEC_CONFIG); run /landspec:init first"
if [[ -n "${scp:-}" ]]; then
  echo "scp: .specify/extensions/landspec/aws/scp-agent.json"
  echo "attach it in AWS Organizations (Policies, Service control policies) to the accounts the agent uses; landspec never attaches it"
  exit 0
fi

cfg_set aws on
cfg_set aws_agent_role "$(cfg aws_agent_role landspec-agent)"
if $set_profiles; then cfg_set aws_prod_profiles "${profiles:-\"\"}"; fi
if $set_paths; then cfg_set aws_prod_paths "${paths:-\"\"}"; fi
if [[ -z "$(cfg infra_dir "")" ]]; then
  # The folder holding the most *.tf files; a tie goes to the first name.
  d="$(infra_files | awk '/\.tf$/ { sub(/\/?[^\/]*$/, ""); print ($0 == "" ? "." : $0) }' \
       | sort | uniq -c | sort -k1,1nr -k2 | awk 'NR == 1 { print $2 }')"
  cfg_set infra_dir "${d:-infra}"
fi
level="$(landspec_level)"

out="$("$(dirname "$0")/level.sh" "$level" --no-branches)"
printf '%s\n' "$out"
if grep -qE '^kept[: ].* \.mcp\.json( |$)' <<<"$out"; then
  old="$(grep -m1 -oE 'mcp-proxy-for-aws==[^" ]+' .mcp.json || true)"; old="${old#*==}"
  if [[ -z "$old" ]]; then
    echo "add to .mcp.json: \"aws-mcp\": { \"command\": \"uvx\", \"args\": [\"mcp-proxy-for-aws==$MCP_PROXY_VERSION\", \"https://aws-mcp.us-east-1.api.aws/mcp\", \"--metadata\", \"AWS_REGION=us-east-1\"], \"env\": { \"AWS_PROFILE\": \"landspec-agent-dev\" } }"
  elif [[ "$old" != "$MCP_PROXY_VERSION" ]]; then
    echo "pin: .mcp.json has $old, landspec pins $MCP_PROXY_VERSION; delete .mcp.json and run /landspec:aws again"
  fi
fi

# A missing settings file lacks every client entry. Checked by text, never rewritten (JSON has no marker).
s=.claude/settings.json
for e in "${client_entries[@]}"; do
  if ! grep -qF "\"${e#*:}\"" "$s" 2>/dev/null; then echo "add to $s: permissions.${e%%:*} \"${e#*:}\""; fi
done

# One deploy per account kind: dev builds (reads only on lite), prod always reads.
dev_access=build; [[ "$level" == lite ]] && dev_access="read"
kinds="dev:$dev_access"; [[ -n "$(cfg aws_prod_profiles "")" ]] && kinds+=" prod:read"
for k in $kinds; do
  echo "deploy: aws cloudformation deploy --stack-name landspec-agent --template-file .specify/extensions/landspec/aws/agent-role.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Access=${k#*:} TrustMode=sso PermissionSetName=<name> --profile <your ${k%%:*} admin profile>"
done
for k in $kinds; do
  printf 'add to ~/.aws/config:\n[profile landspec-agent-%s]\nrole_arn = arn:aws:iam::<%s account id>:role/%s\nsource_profile = <your sso profile>\n' \
    "${k%%:*}" "${k%%:*}" "$(cfg aws_agent_role landspec-agent)"
done
