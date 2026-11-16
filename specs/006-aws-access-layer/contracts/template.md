# Contract: `extension/aws/agent-role.yaml` and `scp-agent.json`

Deployed by a human, one stack per account, one region (research R5). Plain YAML: intrinsics in
long form (`Fn::Sub`, `Fn::If`), so `tests/static.test.sh` can parse it.

## Parameters

| Name | Allowed | Default | Notes |
|---|---|---|---|
| `RoleName` | `[A-Za-z0-9+=,.@_-]{1,56}` | `landspec-agent` | the guard's SCP pattern and the check expect the `landspec-agent` prefix |
| `Access` | `read`, `build` | `read` | `build` only for dev on standard and full |
| `TrustMode` | `sso`, `login` | `sso` | `login` exists only if quickstart Q2 passes (research R3) |
| `PermissionSetName` | permission-set name | `""` | required when `TrustMode=sso` (a rule fails the stack otherwise) |
| `LoginUserNames` | comma-separated IAM user names | `""` | required when `TrustMode=login` |

## Resources

| Logical id | Type | When | What |
|---|---|---|---|
| `AgentRole` | `AWS::IAM::Role` (name `RoleName`) | always | trust per R2 (sso) or R3 (login); `MaxSessionDuration: 3600`; tag `landspec:access=<read|build>` (read by `aws.sh check`) |
| managed policies on `AgentRole` | — | — | `read`: `arn:aws:iam::aws:policy/ReadOnlyAccess`; `build`: `arn:aws:iam::aws:policy/PowerUserAccess` |
| `ReadIam` | inline policy | `build` | `iam:GetRole` and `iam:SimulatePrincipalPolicy` on its own ARN (`aws.sh check` reads its tag and simulates; `PowerUserAccess` grants neither) |
| `ReadIam` | inline policy | `read` | `iam:SimulatePrincipalPolicy` on its own ARN (`ReadOnlyAccess` already grants `iam:GetRole`) |
| `Deny` | inline policy | always | FR-004 list (which holds `iam:PassRole`, `sts:AssumeRole*`, `sts:AssumeRoot` and the Identity Center writes) + self-edit on its own ARN + the stack writes on its own stack (`Fn::Sub` `arn:${AWS::Partition}:cloudformation:${AWS::Region}:${AWS::AccountId}:stack/${AWS::StackName}/*`, whatever the stack is named) (data-model "Outside the invariant"); plus, when `read`, the FR-005 list (`denied-read-actions.txt`) |

## Outputs

`RoleArn`, and `ProfileSnippet`: the `~/.aws/config` lines `aws.sh setup` also prints.

## `scp-agent.json`

Two statements, both `Effect: Deny`, `Resource: *`, the FR-004 action list:
1. condition `ArnLike aws:PrincipalArn arn:aws:iam::*:role/landspec-agent*`;
2. condition `Bool aws:ViaAWSMCPService true`.

A third denies the self-edit actions on `arn:aws:iam::*:role/landspec-agent*` for that same principal.

## The action lists (one place each: `extension/aws/denied-actions.txt`, `extension/aws/denied-read-actions.txt`)

One entry per line: the action as the policies write it, then, for a wildcard entry, a space and
one concrete action that `aws.sh check --simulate` simulates instead (the simulator takes no
wildcards in action names): `organizations:* organizations:LeaveOrganization`,
`account:* account:CloseAccount`, `ssm:GetParameter* ssm:GetParameter`, `s3:GetObject* s3:GetObject`.

FR-004 (`denied-actions.txt`):

`rds:DeleteDBInstance`, `rds:DeleteDBCluster`, `rds:DeleteDBSnapshot`, `rds:DeleteDBClusterSnapshot`,
`s3:DeleteBucket`, `dynamodb:DeleteTable`, `kms:ScheduleKeyDeletion`, `kms:DisableKey`,
`cloudtrail:StopLogging`, `cloudtrail:DeleteTrail`, `guardduty:DeleteDetector`,
`budgets:DeleteBudget`, `config:StopConfigurationRecorder`, `config:DeleteConfigurationRecorder`,
`iam:CreateUser`, `iam:CreateAccessKey`, `iam:CreateLoginProfile`, `iam:AttachUserPolicy`,
`organizations:*`, `account:*`, `iam:PassRole`, `sts:AssumeRole* sts:AssumeRole`, `sts:AssumeRoot`,
`sso-admin:* sso-admin:CreatePermissionSet`,
`identitystore:* identitystore:CreateUser`. (The `sts:AssumeRole` entries refuse the agent assuming
another role; how the human assumes the agent role is unaffected.)

FR-005 (`denied-read-actions.txt`, `read` only): `secretsmanager:GetSecretValue`,
`secretsmanager:BatchGetSecretValue`, `ssm:GetParameter*`, `kms:Decrypt`, `s3:GetObject*`,
`dynamodb:GetItem`, `dynamodb:BatchGetItem`, `dynamodb:Query`, `dynamodb:Scan`, `rds-db:connect`,
`rds-data:ExecuteStatement`, `logs:StartLiveTail`, `lambda:GetFunction`,
`lambda:GetFunctionConfiguration`, `logs:GetLogEvents`, `logs:FilterLogEvents`,
`logs:GetQueryResults`, `athena:GetQueryResults`, `kinesis:GetRecords`, `sqs:ReceiveMessage`.
Known, not complete (other reads return values too, such as task-definition environments): the
read role limits, not removes, what prod data the agent sees.

`tests/static.test.sh` checks that the template's deny statements and the SCP hold exactly the
first column of these files, and `aws.sh check --simulate` reads the files themselves (one source,
no drift).
