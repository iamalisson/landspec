#!/usr/bin/env bash
# The AWS access layer: configure the project and print what the human deploys. Never calls aws.
#   aws.sh setup [--prod-profiles a,b] [--prod-paths p,q]
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

usage="usage: aws.sh setup [--prod-profiles a,b] [--prod-paths p,q]"
[[ "${1:-}" == setup ]] || die "$usage"; shift
set_profiles=false; set_paths=false
while (($#)); do
  case "$1" in
    --prod-profiles) (($# >= 2)) || die "$usage"; set_profiles=true; profiles="$2"; shift 2 ;;
    --prod-paths) (($# >= 2)) || die "$usage"; set_paths=true; paths="$2"; shift 2 ;;
    *) die "$usage" ;;
  esac
done

landspec_cd_root
[[ -f "$LANDSPEC_CONFIG" ]] || die "not a landspec project (no $LANDSPEC_CONFIG); run /landspec:init first"

cfg_set aws on
cfg_set aws_agent_role "$(cfg aws_agent_role landspec-agent)"
# A quote, | or & in a name would break the config line (cfg_set is a sed s|||).
list() { [[ "$2" =~ ^[A-Za-z0-9_.,/@+=:-]*$ ]] || die "$1 takes comma-separated names (letters, digits and _ . / @ + = : -): $2"; cfg_set "$1" "${2:-\"\"}"; }
if $set_profiles; then list aws_prod_profiles "$profiles"; fi
if $set_paths; then list aws_prod_paths "$paths"; fi
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

# The client entries; the Read denies matter because the guard sees Bash only. A missing
# settings file lacks them all. Checked by text, never rewritten (JSON has no marker).
s=.claude/settings.json
for e in allow:mcp__aws-mcp__aws___search_documentation allow:mcp__aws-mcp__aws___read_documentation \
         allow:mcp__aws-mcp__aws___retrieve_skill allow:mcp__aws-mcp__aws___list_regions \
         allow:mcp__aws-mcp__aws___get_regional_availability \
         ask:mcp__aws-mcp__aws___run_script ask:mcp__aws-mcp__aws___get_presigned_url \
         'deny:Read(./.env*)' 'deny:Read(**/*.tfstate*)'; do
  if ! grep -qF "\"${e#*:}\"" "$s" 2>/dev/null; then echo "add to $s: permissions.${e%%:*} \"${e#*:}\""; fi
done

# One deploy per account kind: dev builds (reads only on lite), prod always reads.
dev_access=build; [[ "$level" == lite ]] && dev_access=read
kinds="dev:$dev_access"; [[ -n "$(cfg aws_prod_profiles "")" ]] && kinds+=" prod:read"
for k in $kinds; do
  echo "deploy: aws cloudformation deploy --stack-name landspec-agent --template-file .specify/extensions/landspec/aws/agent-role.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Access=${k#*:} TrustMode=sso PermissionSetName=<name> --profile <your ${k%%:*} admin profile>"
done
for k in $kinds; do
  printf 'add to ~/.aws/config:\n[profile landspec-agent-%s]\nrole_arn = arn:aws:iam::<%s account id>:role/%s\nsource_profile = <your sso profile>\n' \
    "${k%%:*}" "${k%%:*}" "$(cfg aws_agent_role landspec-agent)"
done
