# Data model: Safe AWS access for Claude Code

No database. The state is a few config keys, two files under `.git`, and an AWS stack the human
owns. Every value is derived again on each run: nothing here is a cache.

## AWS layer config

Flat keys in `.specify/extensions/landspec/landspec-config.yml`, read with `cfg` (lib.sh).

| Key | Values | Default | Set by | Read by |
|---|---|---|---|---|
| `aws` | `on`, `off` | `off` | `aws.sh setup` | `guard.sh`, `pr.sh`, `level.sh`, `aws.sh check` |
| `aws_prod_profiles` | comma-separated AWS CLI profile names | `""` | the developer, asked by `/landspec:aws` | `guard.sh` |
| `aws_prod_paths` | comma-separated folders whose Terraform targets prod (e.g. `infra/envs/prod`) | `""` | the developer | `guard.sh` |
| `aws_agent_role` | role name the check expects | `landspec-agent` | `aws.sh setup` | `aws.sh check` |
| `infra_dir` | folder holding Terraform code | `infra` | `aws.sh setup` (detected from `infra_files`) | `pr.sh` plan gate |

Validation:
- `aws` other than `on`/`off`: treated as `off`, and `aws.sh check` says the value is invalid.
- A prod profile or path list that is empty while `aws: on`: allowed (one account only); the
  check reports "no prod configured" (spec, edge case 1).
- Names are matched exactly; nothing is guessed from a name containing "prod" (FR-011).

## Agent role (in AWS, one per account)

Created by the human deploying `agent-role.yaml` (CloudFormation stack `landspec-agent`).

| Field | Meaning |
|---|---|
| `RoleName` | stack parameter, default `landspec-agent` |
| `Access` | stack parameter: `read` (prod, and every account on level lite) or `build` (dev on standard and full) |
| `TrustMode` | stack parameter: `sso` (default: an IAM Identity Center permission set) or `login` (named IAM users through `aws login`; gated, research R3) |
| `PermissionSetName` / `LoginUserNames` | stack parameters for the chosen mode: the permission set whose `AWSReservedSSO_<name>_*` roles may assume it, or the IAM user names |
| `MaxSessionDuration` | 3600 seconds |
| managed policies | `read`: `ReadOnlyAccess`; `build`: `PowerUserAccess` (R6) |
| inline deny | `read`: secrets and data deny (FR-005); both: destructive and self-edit deny (FR-004) |

Lifecycle: `absent` → `deployed` (stack CREATE_COMPLETE) → `updated` (stack UPDATE_COMPLETE, in
place) → `absent` (stack deleted: everything it created goes with it). landspec never moves it
between states; the human does.

## Identity verdict

Produced by `aws.sh check` from `aws sts get-caller-identity` (and `aws iam get-role` for the
environment tag). Never stored.

| Verdict | When | Exit |
|---|---|---|
| `agent` | the caller ARN is `assumed-role/<aws_agent_role>/…` | 0 |
| `user` | the caller ARN is `user/…`: the developer's own IAM user, through an access key or `aws login` (both show a user ARN, research R1); `AWS_ACCESS_KEY_ID` set without `AWS_SESSION_TOKEN` is named as a long-lived key | 1 |
| `other-role` | any other assumed role (an admin or a human permission set) | 1 |
| `no-credentials` / `no-cli` | the call fails / `aws` missing | 1 |

## Plan record

`<git common dir>/landspec-tfplan/<diff id>` (lib.sh `diff_record landspec-tfplan`), like the scan
record: a new commit makes it a different file, so an old plan never counts (FR-012, scenario 4).

```text
[infra/envs/dev]
create 2
change 1
destroy 2
replace aws_db_instance.main
destroy aws_s3_bucket.logs
[infra/envs/prod]
change 1
```

One section per planned root (the directory `terraform` ran in, from the repo root): recording a
root again replaces its section, another root adds one. The gate needs a section for every root
in `aws_prod_paths` whose `.tf` files, or modules they use under the repo, the diff touches; it
needs at least one section otherwise. The PR body lists every section.

Counts follow Terraform's own `Plan:` line: a replace (`["delete","create"]` or
`["create","delete"]`) counts as one create and one destroy; `["forget"]` and `["no-op"]` count as
neither. The example is one create, one update, one replace and one destroy.

Validation: written only by `tfplan.sh record <planfile>` from `terraform show` of that planfile;
a planfile Terraform cannot read is refused, and so is one older than the last commit (`[[ planfile
-nt $(git rev-parse --git-path logs/HEAD) ]]` fails) or made while a `*.tf` file is uncommitted
(`git status --porcelain -- '*.tf'` not empty). A checkout, rebase or pull after the plan also
rewrites `logs/HEAD`, so the refusal says: `plan again after the last commit, checkout or rebase`. Limit: the record binds to the diff, and Terraform
does not say which tree a plan came from; these two checks refuse the usual stale plan, not a plan
made from another checkout. Resource addresses only; no attribute value
is ever copied (they may hold secrets).

## Relationships

- **Invariant (the agent's reach)**: the agent acts only as itself. It holds no IAM write
  (`PowerUserAccess` excludes `iam:*` but service-linked roles; `ReadOnlyAccess` has none), and its
  inline deny refuses `iam:PassRole`, `sts:AssumeRole*`, `sts:AssumeRoot` and Identity Center writes (`sso-admin:*`,
  `identitystore:*`) in both modes. So it can make no principal, and use none, other than its own
  session, and its explicit deny applies to every call it makes, resource policies included
  (an explicit deny in the caller's identity policy always wins). **Outside the invariant**:
  running code inside an existing workload whose role is stronger (`lambda:UpdateFunctionCode`,
  `ssm:SendCommand`, a CodeBuild override), and updating a CloudFormation stack that has a service
  role (`UpdateStack` runs as the stored role, with no `PassRole` check). The agent's own stack is
  deployed without `--role-arn`, and its `Deny` refuses `cloudformation:UpdateStack`,
  `DeleteStack`, `CreateChangeSet`, `ExecuteChangeSet` and `SetStackPolicy` on
  its own stack (`AWS::StackName`, so a renamed stack or role is still covered). Neither the deny nor the SCP covers it, so a dev
  account must hold no such workload; docs/security.md says so.
- `aws: on` turns on the guard's AWS rules, the plan gate (standard, full) and the constitution's
  "Cloud access" section; `off` turns all three off (SC-005).
- The plan record belongs to one diff id, the same id the review and scan records use.
