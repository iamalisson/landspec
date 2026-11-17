#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # checks are strings evaluated by check()
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
fake_aws
a="$SCRIPTS/aws.sh"
cfgf=.specify/extensions/landspec/landspec-config.yml
deploy_dev='deploy: aws cloudformation deploy --stack-name landspec-agent --template-file .specify/extensions/landspec/aws/agent-role.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Access=build TrustMode=sso PermissionSetName=<name> --profile <your dev admin profile>'
deploy_prod='deploy: aws cloudformation deploy --stack-name landspec-agent --template-file .specify/extensions/landspec/aws/agent-role.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Access=read TrustMode=sso PermissionSetName=<name> --profile <your prod admin profile>'

mkdir -p "$TMP/plain" && cd "$TMP/plain" && git init --quiet
check "when run outside a landspec project, then it exits 1 with the /landspec:init hint" \
  'rc=0; out="$("$a" setup 2>&1)" || rc=$?; ((rc == 1)) && [[ "$out" == *"run /landspec:init first"* ]] && [[ ! -e .specify ]]'
cd "$TMP"
check "when run outside a git repository, then it exits 1" 'fails_with "not inside a git repository" "$a" setup'

new_repo standard
mkdir -p infra/envs/prod modules/net
touch infra/envs/prod/main.tf infra/envs/prod/vars.tf modules/net/a.tf
check "when the subcommand is missing or a flag is unknown, then it refuses with the usage and changes nothing" \
  'fails_with "usage: aws.sh setup" "$a" && fails_with "usage: aws.sh setup" "$a" setup --scp-x && fails_with "usage: aws.sh setup" "$a" setup --prod-profiles && ! grep -q "^aws:" "$cfgf"'
check "when a prod profile has a character that would break the config line, then it is refused" \
  'fails_with "aws_prod_profiles takes comma-separated names" "$a" setup --prod-profiles "a|b" && fails_with "aws_prod_paths takes" "$a" setup --prod-paths "x\"y"'
sed -i.bak '/^aws:/d' "$cfgf"

out="$("$a" setup --prod-profiles prod)"
check "when setup --prod-profiles prod runs, then the config has aws: on and aws_prod_profiles: prod" \
  'grep -qx "aws: on" "$cfgf" && grep -qx "aws_prod_profiles: prod" "$cfgf" && ! grep -q "^aws_prod_paths:" "$cfgf"'
check "then aws_agent_role is landspec-agent" 'grep -qx "aws_agent_role: landspec-agent" "$cfgf"'
check "then a deploy line names CAPABILITY_NAMED_IAM and Access=read for prod, and dev builds on standard" \
  'grep -qxF "$deploy_prod" <<<"$out" && grep -qxF "$deploy_dev" <<<"$out" && [[ "$(grep -c "^deploy: " <<<"$out")" == 2 ]]'
check "then the ~/.aws/config profile lines are printed for each account" \
  'grep -A3 -xF "add to ~/.aws/config:" <<<"$out" | grep -qxF "[profile landspec-agent-prod]" && grep -qxF "role_arn = arn:aws:iam::<dev account id>:role/landspec-agent" <<<"$out" && grep -qxF "source_profile = <your sso profile>" <<<"$out"'
check "then infra_dir is the folder with the most *.tf files" 'grep -qx "infra_dir: infra/envs/prod" "$cfgf"'
check "then level.sh wrote .mcp.json and the Cloud access text, with no pin or add-to-.mcp.json line" \
  'grep -qxF "created: .mcp.json" <<<"$out" && grep -q "Cloud access" .specify/memory/constitution.md && ! grep -qE "^(pin:|add to .mcp.json)" <<<"$out"'
check "then with the scaffold's .claude/settings.json every client entry is named, and the file stays the scaffold's" \
  '[[ "$(grep -c "^add to .claude/settings.json: " <<<"$out")" == 9 ]] && grep -qxF "add to .claude/settings.json: permissions.ask \"mcp__aws-mcp__aws___run_script\"" <<<"$out" && cmp -s .claude/settings.json "$ROOT/extension/scaffold/lite/.claude/settings.json"'

"$a" setup --prod-paths infra/prod >/dev/null
check "when setup --prod-paths runs after that, then aws_prod_profiles is still prod" \
  'grep -qx "aws_prod_profiles: prod" "$cfgf" && grep -qx "aws_prod_paths: infra/prod" "$cfgf"'
out="$("$a" setup --prod-profiles '')"
check "after --prod-profiles '' it is empty, the paths are kept, and no prod deploy line is printed" \
  'grep -qx "aws_prod_profiles: \"\"" "$cfgf" && grep -qx "aws_prod_paths: infra/prod" "$cfgf" && ! grep -qF "Access=read" <<<"$out" && grep -qxF "$deploy_dev" <<<"$out"'

set_cfg infra_dir custom; set_cfg aws_agent_role my-agent
out="$("$a" setup)"
check "when infra_dir and aws_agent_role are set, then a rerun keeps them" \
  'grep -qx "infra_dir: custom" "$cfgf" && grep -qx "aws_agent_role: my-agent" "$cfgf" && grep -qF ":role/my-agent" <<<"$out"'
check "when .mcp.json pins the current proxy, then neither a pin nor an add-to-.mcp.json line is printed" \
  'grep -qE "^kept: +\.mcp\.json$" <<<"$out" && ! grep -qE "^(pin:|add to .mcp.json)" <<<"$out"'

sed 's/1\.7\.0/1.6.0/' .mcp.json > "$TMP/mcp.old" && cp "$TMP/mcp.old" .mcp.json
out="$("$a" setup)"
check "when .mcp.json holds mcp-proxy-for-aws==1.6.0, then the pin: line names 1.6.0 and 1.7.0, and the file is unchanged" \
  'grep -qxF "pin: .mcp.json has 1.6.0, landspec pins 1.7.0; delete .mcp.json and run /landspec:aws again" <<<"$out" && cmp -s .mcp.json "$TMP/mcp.old" && ! grep -q "^add to .mcp.json" <<<"$out"'

printf '{ "mcpServers": {} }\n' > .mcp.json; cp .mcp.json "$TMP/mcp.mine"
out="$("$a" setup)"
check "when .mcp.json already exists without aws-mcp, then the aws-mcp entry is printed and the file is unchanged" \
  'grep -qxF "add to .mcp.json: \"aws-mcp\": { \"command\": \"uvx\", \"args\": [\"mcp-proxy-for-aws==1.7.0\", \"https://aws-mcp.us-east-1.api.aws/mcp\", \"--metadata\", \"AWS_REGION=us-east-1\"], \"env\": { \"AWS_PROFILE\": \"landspec-agent-dev\" } }" <<<"$out" && cmp -s .mcp.json "$TMP/mcp.mine" && ! grep -q "^pin:" <<<"$out"'

mkdir -p .claude
cat > .claude/settings.json <<'EOF'
{ "permissions": {
  "allow": ["mcp__aws-mcp__aws___search_documentation", "mcp__aws-mcp__aws___read_documentation", "mcp__aws-mcp__aws___retrieve_skill", "mcp__aws-mcp__aws___list_regions", "mcp__aws-mcp__aws___get_regional_availability"],
  "ask": ["mcp__aws-mcp__aws___run_script", "mcp__aws-mcp__aws___get_presigned_url"],
  "deny": ["Read(**/*.tfstate*)"] } }
EOF
cp .claude/settings.json "$TMP/settings.mine"
out="$("$a" setup)"
check "when .claude/settings.json lacks Read(./.env*), then add to .claude/settings.json: names only it, and the file is byte-for-byte unchanged" \
  '[[ "$(grep "^add to .claude/settings.json: " <<<"$out")" == "add to .claude/settings.json: permissions.deny \"Read(./.env*)\"" ]] && cmp -s .claude/settings.json "$TMP/settings.mine"'

cd "$TMP" && rm -rf repo origin.git
new_repo lite
out="$("$a" setup --prod-profiles prod,prod-eu)"
check "on level lite, every deploy line says Access=read" \
  '[[ "$(grep -c "^deploy: " <<<"$out")" == 2 && "$(grep "^deploy: " <<<"$out" | grep -c "Access=read ")" == 2 ]] && grep -qx "aws_prod_profiles: prod,prod-eu" "$cfgf"'
check "then the level stays lite and, with no *.tf file, infra_dir is infra" 'grep -qx "level: lite" "$cfgf" && grep -qx "infra_dir: infra" "$cfgf"'
touch main.tf; set_cfg infra_dir ""; "$a" setup >/dev/null
check "when the only *.tf file is at the root, then infra_dir is ." 'grep -qx "infra_dir: \." "$cfgf"'

check "no aws command is run (fake_aws records none)" '[[ "$(command -v aws)" == "$TMP/bin/aws" && ! -e "$TMP/aws.calls" ]] && aws sts get-caller-identity && [[ -s "$TMP/aws.calls" ]]'

exit "$FAIL"
