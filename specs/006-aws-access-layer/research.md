# Research: Safe AWS access for Claude Code

Checked against primary sources on 2026-11-16. No AWS call was made.

## R1. How the developer signs in, and what identity Claude ends up with

- **Decision**: Claude always runs as the agent role, through an `~/.aws/config` profile
  (`role_arn` + `source_profile`) whose source is the developer's IAM Identity Center profile
  (`aws sso login`). `aws login` (AWS CLI ≥ 2.32.0) is a second, gated path (R3).
- **Rationale**: `aws login` works for root, IAM users and federated console sessions, not for
  Identity Center users, and its profile keeps the IAM user's own ARN (`login_session =
  arn:aws:iam::<acct>:user/<name>`), so `get-caller-identity` shows `user/…` both for `aws login`
  and for an access key. The check therefore passes only `assumed-role/<agent role>/…` and refuses
  any `user/…`, naming a long-lived key only when `AWS_ACCESS_KEY_ID` is set with no session token.
- **Alternatives**: the helper repository's `generate-sts-token.sh` (temporary tokens minted from a
  profile that still holds long-lived keys: the key stays on disk); an EC2 instance role (Meridian's
  workspace: out of scope, the same role works as its instance role).
- Sources: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html,
  https://docs.aws.amazon.com/signin/latest/userguide/command-line-sign-in.html

## R2. Trust policy for Identity Center

- **Decision**: `Principal: {"AWS": "arn:aws:iam::<acct>:root"}` with
  `ArnLike aws:PrincipalArn: arn:aws:iam::<acct>:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_<PermissionSet>_*`.
- **Rationale**: wildcards are not allowed in `Principal`; the match goes in the condition, on the
  role ARN (not the session ARN). The region segment is absent when Identity Center lives in
  us-east-1, so `sso.amazonaws.com/*/AWSReservedSSO_…` would miss it; `/*AWSReservedSSO_` covers
  both. The trailing `*` is required (the suffix changes when the set is reassigned). Roles cannot
  hold access keys, so key callers are excluded by construction.
- Source: https://docs.aws.amazon.com/singlesignon/latest/userguide/referencingpermissionsets.html

## R3. Refusing long-term access keys on the `aws login` path

- **Decision**: `TrustMode=login` trusts the named IAM users only with
  `"Null": {"aws:SignInSessionArn": "false"}`. It ships **only if** quickstart scenario Q2 shows, in
  a real account, that the key reaches `sts:AssumeRole` (a key-signed assume is denied, an
  `aws login` one allowed). If not, `login` mode is removed before release and the docs say
  Identity Center is required.
- **Rationale**: `aws:SignInSessionArn` is set only on Sign-In OAuth sessions (`aws login`, the AWS
  MCP server). `aws:MultiFactorAuthPresent` is absent for SSO too; `aws:TokenIssueTime` is defeated
  by `GetSessionToken`; `aws:PrincipalType` does not tell keys from temporary credentials. The docs
  do not say whether `SignInSessionArn` is in the AssumeRole request context: unverified.
- Source: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html

## R4. Session length

- **Decision**: `MaxSessionDuration: 3600`.
- **Rationale**: going from an `AWSReservedSSO_*` session to the agent role is role chaining,
  capped at 1 hour anyway; the CLI refreshes `source_profile` chains on its own.
- Source: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use.html

## R5. The template format and its deploy

- **Decision**: one CloudFormation template, `extension/aws/agent-role.yaml`, deployed by the
  human with `aws cloudformation deploy … --capabilities CAPABILITY_NAMED_IAM --parameter-overrides
  …`, stack `landspec-agent`, in one region per account. Intrinsics written in long form
  (`Fn::Sub`), so the file stays plain YAML a test can parse.
- **Rationale**: reviewable as a diff, updated in place, drift-detectable, removed as one unit.
  Named IAM resources need `CAPABILITY_NAMED_IAM`; named roles are account-global, so the template
  must not be deployed in two regions (the deploy line pins `--region`).
- **Alternatives**: a bash script of CLI calls (the helper's `criar_role_ssm.sh`: a failed run
  leaves partial resources, no single removal); Terraform (needs its own state bucket first:
  a bootstrap problem for the very role that would run it).
- Source: https://docs.aws.amazon.com/cli/latest/reference/cloudformation/deploy.html

## R6. Permissions: build role, read role

- **Decision**:
  - `Access=read`: `ReadOnlyAccess` + inline deny of `secretsmanager:GetSecretValue`,
    `ssm:GetParameter*`, `kms:Decrypt`, `s3:GetObject*`, `dynamodb:GetItem/BatchGetItem/Query/Scan`,
    `rds-db:connect`, `rds-data:ExecuteStatement`, `logs:StartLiveTail` (Meridian
    `agent-prod-readonly-deny.json`), plus reads that return data or secret values:
    `lambda:GetFunction`, `lambda:GetFunctionConfiguration` (environment variables),
    `logs:GetLogEvents`, `logs:FilterLogEvents`, `logs:GetQueryResults`, `athena:GetQueryResults`,
    `kinesis:GetRecords`, `sqs:ReceiveMessage`. Known, not complete: docs/security.md says the
    read role limits, not removes, what prod data the agent can see.
  - `Access=build`: `PowerUserAccess` (every service but IAM, Organizations and Account, plus
    service-linked roles, so a first ALB or ECS cluster still works) + `ReadIam` + the inline deny
    of the FR-004 list, which also refuses `iam:PassRole`, `sts:AssumeRole*` and Identity Center
    writes. No permissions boundary and no IAM role creation.
- **Rationale**: three review rounds showed that letting the agent create roles, even under a
  boundary that carries itself, leaves a path out: a boundary does not limit a same-account
  resource policy that names a created role's session, so that session can delete a bucket or a
  key the agent itself is denied. With no IAM write, no `PassRole` and no `AssumeRole`, the agent
  only ever acts as itself, and an explicit deny in its own policy wins over any resource policy.
  The cost: Terraform that adds IAM (an application's role) goes through a PR and the pipeline,
  and with `PassRole` denied, applies in dev are limited to resources that take no role (no Lambda, ECS task, EC2 instance profile or other resource that is handed a role); anything with a role goes through the pipeline.
- Source: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html,
  https://docs.aws.amazon.com/aws-managed-policy/latest/reference/PowerUserAccess.html

## R7. Organization policy (optional)

- **Decision**: `extension/aws/scp-agent.json`: the FR-004 denies for
  `aws:PrincipalArn ArnLike arn:aws:iam::*:role/landspec-agent*` and, separately, for
  `aws:ViaAWSMCPService = true` (Boolean; `aws:CalledViaAWSMCP` holds the server's principal,
  e.g. `aws-mcp.amazonaws.com`). Printed only with `--scp`; a human attaches it.
- Source: https://aws.amazon.com/blogs/security/understanding-iam-for-managed-aws-mcp-servers

## R8. The MCP server entry

- **Decision**: `uvx mcp-proxy-for-aws==1.7.0` (released 2026-09-15), pinned as
  `MCP_PROXY_VERSION` in `extension/scripts/pins.sh`; `static.test.sh` checks it agrees with the
  generated `.mcp.json`. `bin/check-tools.sh` covers GitHub releases only, so this PyPI pin is
  bumped by hand (docs/reference.md says so).
- **Rationale**: 1.8.0 (2026-11-03) is under three weeks old; pins move only to releases that have
  been out a few weeks (pins.sh rule). AWS's quick start uses `mcp-proxy-for-aws-cli@latest`: an
  unpinned `@latest` is what the pins rule exists to avoid. The current tools are `aws___run_script`,
  `aws___search_documentation`, `aws___read_documentation`, `aws___retrieve_skill`,
  `aws___list_regions`, `aws___get_regional_availability`, `aws___get_presigned_url`,
  `aws___get_tasks`; `aws___call_aws` is no longer listed (to confirm with a live `tools/list` in Q4).
- Sources: https://pypi.org/project/mcp-proxy-for-aws/,
  https://docs.aws.amazon.com/agent-toolkit/latest/userguide/understanding-mcp-server-tools.html

## R9. Agent Toolkit

- **Decision**: landspec does not install it; the check says how when skills are missing:
  `/plugin install aws-core@claude-plugins-official` in Claude Code, or `aws configure
  agent-toolkit` (CLI ≥ 2.35.0; installs skills globally and writes its own MCP config, which the
  developer should point at the agent profile).
- Source: https://docs.aws.amazon.com/agent-toolkit/latest/userguide/quick-start.html

## R10. Proving the denies without touching anything

- **Decision**: `aws.sh check --simulate` runs `aws iam simulate-principal-policy
  --policy-source-arn <agent role ARN>` over the FR-004 / FR-005 action lists. That gives SC-002
  a repeatable, read-only test the developer can run in their own account.
- **Rationale**: it evaluates the role's policies, its boundary and SCPs (not RCPs or resource
  policies), performs no operation, and a role can simulate itself: `ReadOnlyAccess` grants
  `iam:Simulate*`. The build role gets `iam:SimulatePrincipalPolicy` on its own ARN in the
  template. Results can differ from live calls in edge cases (role chaining, endpoint policies):
  Q2 still does one live denied call per mode.
- Sources: https://docs.aws.amazon.com/IAM/latest/APIReference/API_SimulatePrincipalPolicy.html,
  https://docs.aws.amazon.com/aws-managed-policy/latest/reference/ReadOnlyAccess.html

## R11. Reading the Terraform plan

- **Decision**: `tfplan.sh` reads `terraform show -json <planfile>` when `python3` is present
  (`resource_changes[].change.actions`: any `delete` with `create` is a replace, `delete` alone a
  destroy; `forget` counts as neither), and otherwise the text form (`Plan: X to add, Y to change,
  Z to destroy.` and the `# <address> must be replaced` / `will be destroyed` lines).
- **Rationale**: the JSON is the stable interface; `python3` is optional in landspec (constitution),
  so the text form is the fallback, and a test covers both. Stateful types: `aws_db_instance`,
  `aws_rds_cluster`, `aws_s3_bucket`, `aws_dynamodb_table`, `aws_kms_key`, `aws_efs_file_system`,
  `aws_elasticache_*`, `aws_ebs_volume`, `aws_secretsmanager_secret`, `aws_cognito_user_pool`.
- Source: https://developer.hashicorp.com/terraform/internals/json-format

## R12. Who turns which rule on

- **Decision**: the guard rules, the plan gate and the constitution section all depend on
  `aws: on`. The plan gate is not added for every Terraform project.
- **Rationale**: SC-005: projects without the layer see no change; a Terraform project on
  standard would otherwise get a new refusal on upgrade.
