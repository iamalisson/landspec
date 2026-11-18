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
check "when a prod profile has a character that would break the config line, then it is refused and nothing is written" \
  'fails_with "aws_prod_profiles takes comma-separated names" "$a" setup --prod-profiles "a|b" && fails_with "aws_prod_paths takes" "$a" setup --prod-paths "x\"y" && ! grep -q "^aws" "$cfgf"'
check "when a flag stands where a value was due, then it is refused and nothing is written" \
  'fails_with "aws_prod_profiles takes" "$a" setup --prod-profiles --prod-paths && fails_with "aws_prod_paths takes" "$a" setup --prod-paths -x && ! grep -q "^aws" "$cfgf"'

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
cp "$cfgf" "$TMP/cfg.before"
out="$("$a" setup --scp)"
check "when setup --scp runs, then it names scp-agent.json and how to attach it, and aws_prod_profiles is still prod (the config byte-for-byte)" \
  '[[ "$out" == "scp: .specify/extensions/landspec/aws/scp-agent.json"$'"'"'\n'"'"'"attach it in AWS Organizations"* ]] && [[ -f "$ROOT/extension/aws/scp-agent.json" ]] && grep -qx "aws_prod_profiles: prod" "$cfgf" && cmp -s "$cfgf" "$TMP/cfg.before"'
check "when --scp comes with another flag, before or after, then it refuses with the usage and changes nothing" \
  'fails_with "usage: aws.sh setup" "$a" setup --scp --prod-profiles x && fails_with "usage: aws.sh setup" "$a" setup --prod-paths x --scp && cmp -s "$cfgf" "$TMP/cfg.before"'
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

# aws.sh check: the identity verdicts, then --simulate.
ln -s "$ROOT/extension/aws" .specify/extensions/landspec/aws # as spec-kit installs it
rm -f "$TMP/aws.calls"
who() { # who <arn>: the caller-identity answer for <arn>, pretty as the CLI prints it
  printf '{\n    "UserId": "AROAEXAMPLE:s",\n    "Account": "111122223333",\n    "Arn": "%s"\n}' "$1"
}
role_tag() { # role_tag <access>: the get-role answer, its landspec:access tag after another tag
  printf '{\n    "Role": {\n        "RoleName": "landspec-agent",\n        "Tags": [\n            {\n                "Key": "env",\n                "Value": "x"\n            },\n            {\n                "Key": "landspec:access",\n                "Value": "%s"\n            }\n        ]\n    }\n}' "$1"
}
# sim <decision> [<action>=<decision>...]: a simulation answer giving each action of the last
# --action-names <decision>, except those named; on one line, as JSON may also come.
sim() {
  local d="$1" a v o; shift
  printf '{"EvaluationResults": ['
  for a in $(sed -n 's/.*--action-names \(.*\) --output json$/\1/p' "$TMP/aws.calls" | tail -n 1); do
    v="$d"; for o in "$@"; do if [[ "${o%%=*}" == "$a" ]]; then v="${o#*=}"; fi; done
    printf '{"EvalActionName": "%s", "EvalResourceName": "*", "EvalDecision": "%s", "MatchedStatements": []},' "$a" "$v"
  done
  printf '{}]}'
}
simcall() { grep "^iam simulate-principal-policy " "$TMP/aws.calls" | tail -n 1; }
export AWS_IDENTITY_JSON AWS_ROLE_JSON AWS_SIM_JSON
AWS_IDENTITY_JSON="$(who arn:aws:sts::111122223333:assumed-role/landspec-agent/s)"; AWS_ROLE_JSON="$(role_tag build)"
r=0; out="$("$a" check 2>&1)" || r=$?
check "when the caller is assumed-role/landspec-agent/s with tag landspec:access=build, then IDENTITY=agent, ACCESS=build, exit 0" \
  '((r == 0)) && grep -qx "IDENTITY=agent" <<<"$out" && grep -qx "ACCOUNT=111122223333" <<<"$out" && grep -qx "ROLE=landspec-agent" <<<"$out" && grep -qx "ACCESS=build" <<<"$out"'
check "then each absent client entry is a missing: line, and .mcp.json (written by setup) is not" \
  'grep -qxF "missing: .claude/settings.json: permissions.deny \"Read(./.env*)\"" <<<"$out" && [[ "$(grep -c "^missing: " <<<"$out")" == 9 ]]'
noprod="PROD=none: no prod configured (one account only; /landspec:aws --prod-profiles <names> adds one)"
cp "$cfgf" "$TMP/cfg.prod"
sed -i.bak '/^aws_prod_profiles:/d' "$cfgf"; rm -f "$cfgf.bak"
r=0; out="$("$a" check 2>&1)" || r=$?
check "when the config has no aws_prod_profiles key, then the line after ACCESS=build is the no-prod one, and exit 0" \
  '((r == 0)) && [[ "$(grep -A1 -x "ACCESS=build" <<<"$out" | tail -n 1)" == "$noprod" ]] && [[ "$(grep -c "^PROD=" <<<"$out")" == 1 ]]'
echo 'aws_prod_profiles: ""' >> "$cfgf"
check "when aws_prod_profiles is \"\" (setup's empty value), then the same no-prod line" \
  'o="$("$a" check)" && grep -qxF "$noprod" <<<"$o"'
sed -i.bak 's/^aws_prod_profiles:.*$/aws_prod_profiles: prod,prod-eu/' "$cfgf"; rm -f "$cfgf.bak"
check "when aws_prod_profiles is prod,prod-eu, then PROD=prod,prod-eu and no no-prod line" \
  'o="$("$a" check)" && grep -qx "PROD=prod,prod-eu" <<<"$o" && [[ "$o" != *"no prod configured"* ]]'
AWS_ROLE_JSON="$(role_tag admin)"
check "when the role tag is neither read nor build, then ACCESS=unknown" 'o="$("$a" check)" && grep -qx "ACCESS=unknown" <<<"$o"'
AWS_ROLE_JSON=""
check "when get-role answers nothing, then ACCESS=unknown and still exit 0" 'o="$("$a" check)" && grep -qx "ACCESS=unknown" <<<"$o"'
mv .mcp.json "$TMP/mcp.keep"
printf '{"permissions": {"allow": ["mcp__aws-mcp__aws___search_documentation", "mcp__aws-mcp__aws___read_documentation", "mcp__aws-mcp__aws___retrieve_skill", "mcp__aws-mcp__aws___list_regions", "mcp__aws-mcp__aws___get_regional_availability"], "ask": ["mcp__aws-mcp__aws___run_script", "mcp__aws-mcp__aws___get_presigned_url"], "deny": ["Read(./.env*)", "Read(**/*.tfstate*)"]}}\n' > .claude/settings.json
check "when every client entry is there but .mcp.json is not, then the only missing: line is the aws-mcp server" \
  '[[ "$("$a" check | grep "^missing: ")" == "missing: .mcp.json: the aws-mcp server" ]]'
mv "$TMP/mcp.keep" .mcp.json

key="AKIA$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)" # built here: no key-shaped literal in this file
AWS_IDENTITY_JSON="$(who arn:aws:iam::111122223333:user/dev)"
r=0; out="$(AWS_ACCESS_KEY_ID="$key" AWS_SESSION_TOKEN="" "$a" check 2>&1)" || r=$?
check "when the caller is user/dev with a long-lived key, then IDENTITY=user, exit 1, the line names the agent profile and the long-lived key, and never the key" \
  '((r == 1)) && grep -qx "IDENTITY=user" <<<"$out" && grep -qx "ROLE=" <<<"$out" && grep -qx "ACCESS=unknown" <<<"$out" && grep -qxF "landspec: this is your own IAM user dev, not landspec-agent; use the profile that assumes landspec-agent (aws sso login --profile landspec-agent-dev)" <<<"$out" && grep -qxF "landspec: it is a long-lived access key: remove it from the environment" <<<"$out" && [[ "$out" != *AKIA* ]]'
check "when the user has a session token too, then there is no long-lived key line" \
  'rc=0; o="$(AWS_ACCESS_KEY_ID="$key" AWS_SESSION_TOKEN=t "$a" check 2>&1)" || rc=$?; ((rc == 1)) && grep -qx "IDENTITY=user" <<<"$o" && [[ "$o" != *long-lived* && "$o" != *AKIA* ]]'
check "when the user has no key in the environment (aws login), then there is no long-lived key line" \
  'rc=0; o="$(env -u AWS_ACCESS_KEY_ID "$a" check 2>&1)" || rc=$?; ((rc == 1)) && grep -qx "IDENTITY=user" <<<"$o" && [[ "$o" != *long-lived* ]]'
sed -i.bak '/^aws_prod_profiles:/d' "$cfgf"; rm -f "$cfgf.bak"
check "when the IAM user has no prod profiles, then the no-prod line is printed and it still refuses with exit 1" \
  'rc=0; o="$(env -u AWS_ACCESS_KEY_ID "$a" check 2>&1)" || rc=$?; ((rc == 1)) && grep -qxF "$noprod" <<<"$o" && grep -qxF "landspec: this is your own IAM user dev, not landspec-agent; use the profile that assumes landspec-agent (aws sso login --profile landspec-agent-dev)" <<<"$o"'
cp "$TMP/cfg.prod" "$cfgf"
AWS_IDENTITY_JSON="$(who arn:aws:sts::111122223333:assumed-role/AWSReservedSSO_Admin_x/me)"
r=0; out="$("$a" check --simulate 2>&1)" || r=$?
check "when the caller is assumed-role/AWSReservedSSO_Admin_x/me, then IDENTITY=other-role, exit 1, and no simulation runs" \
  '((r == 1)) && grep -qx "IDENTITY=other-role" <<<"$out" && grep -qxF "landspec: this is role AWSReservedSSO_Admin_x, not landspec-agent; use the profile that assumes landspec-agent (AWS_PROFILE=landspec-agent-dev)" <<<"$out" && ! grep -q simulate "$TMP/aws.calls"'
AWS_IDENTITY_JSON="$(who arn:aws:sts::111122223333:assumed-role/landspec-agent-old/s)"
check "when the role only starts with the agent role name, then it is other-role" \
  'rc=0; o="$("$a" check 2>&1)" || rc=$?; ((rc == 1)) && grep -qx "IDENTITY=other-role" <<<"$o"'
check "when check gets an unknown flag or an extra argument, then it refuses with its usage" \
  'fails_with "usage: aws.sh check [--simulate]" "$a" check --x && fails_with "usage: aws.sh check" "$a" check --simulate x'

no_scanners; rm -f "$TMP/none/aws" # a PATH with no aws, whatever this machine has installed
git status --porcelain --ignored > "$TMP/before"
check "when aws is missing from PATH, then IDENTITY=no-cli, exit 1, and nothing is written" \
  'rc=0; o="$(PATH="$TMP/none" "$a" check 2>&1)" || rc=$?; ((rc == 1)) && grep -qx "IDENTITY=no-cli" <<<"$o" && grep -q "install AWS CLI v2" <<<"$o" && ! grep -q "^PROD=" <<<"$o" && git status --porcelain --ignored | cmp -s - "$TMP/before"'
check "when the aws call fails, then IDENTITY=no-credentials, exit 1, and nothing is written" \
  'rc=0; o="$(AWS_FAIL=1 "$a" check 2>&1)" || rc=$?; ((rc == 1)) && grep -qx "IDENTITY=no-credentials" <<<"$o" && grep -q "aws sso login" <<<"$o" && ! grep -q "^PROD=" <<<"$o" && git status --porcelain --ignored | cmp -s - "$TMP/before"'

AWS_IDENTITY_JSON="$(who arn:aws:sts::111122223333:assumed-role/landspec-agent/s)"; AWS_ROLE_JSON="$(role_tag build)"; AWS_SIM_JSON=""
"$a" check --simulate >/dev/null 2>&1 || true
check "with --simulate, the role ARN is the agent's and --action-names holds organizations:LeaveOrganization and no *" \
  'c="$(simcall)"; [[ "$c" == *"--policy-source-arn arn:aws:iam::111122223333:role/landspec-agent --action-names "* && " $c " == *" organizations:LeaveOrganization "* && "$c" != *"*"* ]]'
check "with ACCESS=build, --action-names holds no secretsmanager:GetSecretValue" '[[ -n "$(simcall)" && " $(simcall) " != *" secretsmanager:GetSecretValue "* ]]'
check "when the simulation answers no decision for an action, then it says unknown and exits 1" \
  'rc=0; o="$(AWS_SIM_JSON="{\"EvaluationResults\": []}" "$a" check --simulate)" || rc=$?; ((rc == 1)) && grep -qx "unknown s3:DeleteBucket: the simulation gave no decision" <<<"$o"'
check "when simulate-principal-policy fails, then check exits 1 and names the permission it needs" \
  'AWS_FAIL=simulate-principal-policy; export AWS_FAIL; fails_with "iam:SimulatePrincipalPolicy on itself" "$a" check --simulate'
AWS_SIM_JSON="$(sim implicitDeny s3:DeleteBucket=allowed)"
r=0; out="$("$a" check --simulate)" || r=$?
check "when the simulation answers allowed for s3:DeleteBucket, then ALLOWED s3:DeleteBucket and exit 1" \
  '((r == 1)) && grep -qx "ALLOWED s3:DeleteBucket" <<<"$out" && [[ "$(grep -c "^ALLOWED " <<<"$out")" == 1 ]] && grep -qx "denied rds:DeleteDBInstance" <<<"$out"'
AWS_SIM_JSON="$(sim implicitDeny kms:Decrypt=explicitDeny s3:DeleteBucket=explicitDeny)"
r=0; out="$("$a" check --simulate)" || r=$?
check "when every action is implicitDeny or explicitDeny, then every line is denied, one per action, and exit 0" \
  '((r == 0)) && [[ "$(grep -c "^denied " <<<"$out")" == "$(grep -c . "$ROOT/extension/aws/denied-actions.txt")" ]] && ! grep -qE "^(ALLOWED|unknown) " <<<"$out" && grep -qx "denied s3:DeleteBucket" <<<"$out"'
AWS_ROLE_JSON="$(role_tag read)"
"$a" check --simulate >/dev/null 2>&1 || true
check "with ACCESS=read, --action-names holds secretsmanager:GetSecretValue and s3:GetObject (for s3:GetObject*), and no *" \
  'c="$(simcall)"; [[ " $c " == *" secretsmanager:GetSecretValue "* && " $c " == *" s3:GetObject "* && " $c " == *" organizations:LeaveOrganization "* && "$c" != *"*"* ]]'
AWS_SIM_JSON="$(sim explicitDeny)"
check "with ACCESS=read and all denied, then one denied line per action of both lists, exit 0" \
  'o="$("$a" check --simulate)" && [[ "$(grep -c "^denied " <<<"$o")" == "$(cat "$ROOT/extension/aws/denied-actions.txt" "$ROOT/extension/aws/denied-read-actions.txt" | grep -c .)" ]]'
check "the fake records only read calls (sts get-caller-identity, iam get-role, iam simulate-principal-policy)" \
  'grep -q "^iam get-role " "$TMP/aws.calls" && ! grep -vE "^(sts get-caller-identity|iam get-role|iam simulate-principal-policy) " "$TMP/aws.calls"'

exit "$FAIL"
