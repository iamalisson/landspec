---
description: "Tasks for safe AWS access for Claude Code"
---

# Tasks: Safe AWS access for Claude Code

**Input**: Design documents from `specs/006-aws-access-layer/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/scripts.md](contracts/scripts.md), [contracts/template.md](contracts/template.md), [quickstart.md](quickstart.md)

**Tests**: every task ships its checks in the same PR (bash, "when …, then …", through `tests/helpers.sh`), each seen failing with its behavior disabled; the PR says so. The live checks (quickstart Q1–Q6) are T007.

**Organization**: one phase per user story. Nothing here makes AWS calls in CI: `aws` and `terraform` are fakes in `tests/helpers.sh`, like `gh`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (no dependency on an unmerged task)
- `(depends on T00n)`: needs that task merged first
- One task = one issue = one branch = one pull request; ` — #N` is appended automatically.

## Rules every task follows

- After editing `extension/`, sync the installed copy: `specify extension add --dev extension --force`,
  then `git restore .specify/extensions/.registry` when only its timestamp changed; the project copy
  under `.specify/extensions/landspec/` must end identical.
- Bash 3.2 with BSD or busybox tools: no associative arrays, no `sed` `I` flag, no `date -d`;
  config lists split with `IFS=,`.
- **Invariant (data-model "Relationships")**: every new rule, gate, scaffold file and constitution
  section is active only when `cfg aws off` is `on`. Each task that adds one has a check that, with
  `aws: off` (the default), the behavior is exactly today's (SC-005).
- **landspec never makes an AWS write and never prints a credential** (FR-002, FR-007): no task
  calls `aws` other than `sts get-caller-identity`, `iam get-role`, `iam simulate-principal-policy`,
  and `cloudformation describe-stacks`, all read-only.
- Shared files (whichever merges second rebases onto the first): `extension/scripts/guard.sh` and
  `extension/scripts/pr.sh` (also changed by PR #193, which merges first: T005 and T006 start from
  a base that has it, or rebase onto it), `extension/scripts/lib.sh`,
  `tests/helpers.sh` (fake `aws`, fake `terraform`), `docs/reference.md` (config table near `:261`),
  `docs/security.md` (the layers table near `:24`), `README.md`, `skills/help/SKILL.md`, the next
  `docs/releases/<version>.md`.

---

## Phase 3: User Story 1 - Set up a safe AWS identity for Claude once (Priority: P1)

**Goal**: a human can deploy one reviewed template per account that creates the agent role, and `/landspec:aws` sets the project up for it.

**Independent Test**: quickstart L2, L6 (local); Q1, Q3, Q6 (live, T007).

- [ ] T001 [P] [US1] Ship the agent-role template and the two denied-action lists, in extension/aws/agent-role.yaml — #194
  - Comes from: FR-003, FR-004, FR-005, FR-006, SC-003; contracts/template.md; research R2, R4, R5, R6, R7
  - What: new `extension/aws/denied-actions.txt` (FR-004) and `extension/aws/denied-read-actions.txt`
    (FR-005), in the format of contracts/template.md "The action lists" (the action, then the
    concrete action to simulate for a wildcard entry); `extension/aws/agent-role.yaml` (CloudFormation, plain YAML: long-form
    intrinsics `Fn::Sub`, `Fn::If`, `Fn::Equals`, no `!` tags) with the parameters, resources and
    outputs of contracts/template.md: `RoleName` (default `landspec-agent`), `Access`
    (`read`|`build`, default `read`), `TrustMode` (`sso`|`login`, default `sso`),
    `PermissionSetName`, `LoginUserNames`; a `Rules` section that fails the stack when the
    parameter of the chosen mode is empty; trust per research R2 (`Principal: {AWS: account root}`,
    `ArnLike aws:PrincipalArn arn:aws:iam::<acct>:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_<PermissionSetName>_*`)
    or R3 (`login`: `Null aws:SignInSessionArn false` on the named users); `MaxSessionDuration: 3600`;
    tag `landspec:access`; `read` → `ReadOnlyAccess` + inline deny of the FR-005 list
    (contracts/template.md / research R6) + `ReadIam`; `build` → `PowerUserAccess` + `ReadIam`
    (no boundary, no IAM role creation: data-model "Invariant (the agent's reach)"); the `Deny` inline policy (FR-004
    list + self-edit actions on its own ARN) on both.
  - Impact: new kind of file in the extension: `extension/extension.yml` (if it lists shipped
    folders) and `bin/remove.sh` (files under `.specify/extensions/landspec/` go with the
    extension: check it needs nothing); `tests/static.test.sh` (new checks below, pattern: its
    existing JSON checks); `docs/security.md` (one layers row: "AWS agent role", what it denies,
    bypassable: **no**, IAM is the boundary; it says the read role limits, not removes, what prod
    data the agent sees; that applies in dev are limited to resources that take no role (no Lambda, ECS task, EC2 instance profile or other resource that is handed a role); anything with a role goes through the pipeline; and that a dev account must hold no
    workload whose role is stronger than the agent's, and no stack with a service role; the deploy
    line has no `--role-arn`); `docs/GUARDRAILS.md` (one row: an AI agent with
    long-lived keys or admin rights, primary source: the IAM best-practices page and the AWS MCP
    IAM blog of research R7).
  - Completed when: `bash tests/static.test.sh` passes with new checks:
    - when `agent-role.yaml` is parsed (`python3 -c 'import yaml…'` when `python3` and PyYAML are
      present; otherwise a grep that no line starts a value with `!`), then it parses, and it has
      the five parameters with the defaults above;
    - when the template's `Deny` statement and the first
      column of `denied-actions.txt` are compared, then they hold exactly the same action list, and
      the read-mode deny equals `denied-read-actions.txt` (one source each);
    - every wildcard entry of both lists has a concrete second column with no `*`;
    - no allow statement in the template grants an `iam:` write (only `iam:GetRole` and
      `iam:SimulatePrincipalPolicy` on the role's own ARN), and no `AWS::IAM::ManagedPolicy` or
      `PermissionsBoundary` appears; the deny holds `iam:PassRole`, `sts:AssumeRole*`,
      `sts:AssumeRoot` and the stack writes on `${AWS::StackName}` (not a fixed name; failure
      path: add `iam:CreateRole` to an allow, or drop `sts:AssumeRole` from the list, and the check
      names it);
    - the build role's `ReadIam` allows `iam:GetRole` (so `aws.sh check` can read its tag);
    - when the template's trust condition is read, then it uses `/*AWSReservedSSO_` (both region
      forms, research R2), never `sso.amazonaws.com/*/AWSReservedSSO_`;
    - no `AWS::IAM::User` and no `AWS::IAM::AccessKey` resource appears (failure path: SC-003).

- [ ] T002 [P] [US1] Generate `.mcp.json` and the "Cloud access" constitution text when the AWS layer is on, in extension/scripts/level.sh — #195
  - Comes from: FR-008, FR-009, SC-005; contracts/scripts.md "aws.sh setup" (the `.mcp.json` line); research R8
  - What: in `level.sh`, when `cfg aws off` is `on`: a new `mcp_json` generator written through
    `put .mcp.json generated` only when `.mcp.json` does not exist (JSON carries no marker; pattern:
    `security_yaml | put .github/workflows/security.yml generated`, `level.sh:387`, which expands
    pins; the scaffold loop at `:372` copies files as they are, so it could not), with the
    `aws-mcp` server: `uvx mcp-proxy-for-aws==$MCP_PROXY_VERSION`,
    `https://aws-mcp.us-east-1.api.aws/mcp`, `--metadata AWS_REGION=us-east-1`, env
    `AWS_PROFILE=landspec-agent-dev`; and, in the constitution block loop near `:105`, the text of
    new `extension/levels/aws/<l>.md` for each level in `levels` (the "Cloud access" text of
    FR-009 per level; standard and full say: applies in dev are limited to resources that take no role (no Lambda, ECS task, EC2 instance profile or other resource that is handed a role); anything with a role goes through the pipeline). New `MCP_PROXY_VERSION="1.7.0"` in `extension/scripts/pins.sh` (research R8).
  - Impact: `bin/remove.sh` (`.mcp.json` is recorded by `put`, so it is removed only when
    unchanged: check it); `tests/level.test.sh`; `tests/remove.test.sh`; `tests/static.test.sh`
    (`MCP_PROXY_VERSION` agrees between `pins.sh` and the generated `.mcp.json`);
    `docs/reference.md` (`aws` key, and that the PyPI pin is bumped by hand: `bin/check-tools.sh`
    covers GitHub releases only).
  - Completed when: `bash tests/level.test.sh`, `bash tests/remove.test.sh` and
    `bash tests/static.test.sh` pass with new checks:
    - with `aws: on` in the config and no `.mcp.json`, `level.sh standard --no-branches` writes
      `.mcp.json` holding `mcp-proxy-for-aws==1.7.0` (literal) and the constitution has a
      "Cloud access" section;
    - with an existing `.mcp.json`, it is byte-for-byte unchanged (`kept: .mcp.json`);
    - with `aws: off` (the default), no `.mcp.json` and no "Cloud access" (SC-005);
    - `remove.sh` deletes an unchanged generated `.mcp.json` and keeps an edited one.

- [ ] T003 [US1] Add `/landspec:aws` and `aws.sh setup`, which configure the project and print the deploy steps, in extension/scripts/aws.sh (depends on T001, T002) — #196
  - Comes from: FR-001, FR-002, FR-011, FR-013; User Story 1 scenarios 1, 4; contracts/scripts.md "/landspec:aws" and "aws.sh setup"; data-model "AWS layer config"; research R9
  - What: new `extension/scripts/aws.sh` (sources `lib.sh`, `landspec_cd_root`; pattern:
    `extension/scripts/next.sh`) with `setup [--prod-profiles a,b] [--prod-paths p,q]`:
    sets `aws: on` and `aws_agent_role` (`landspec-agent`) with `cfg_set`; sets
    `aws_prod_profiles` and `aws_prod_paths` only for a flag that is given (an omitted flag keeps
    the current value; `--prod-profiles ''` empties it); sets `infra_dir` only when unset (the
    folder with the most `*.tf` files from `infra_files`, `lib.sh:288`; default `infra`); then runs
    `level.sh <current level> --no-branches` (T002 writes `.mcp.json` and "Cloud access") and,
    when `.mcp.json` was kept, prints the `aws-mcp` entry to add, or, when it holds a
    `mcp-proxy-for-aws==` other than `MCP_PROXY_VERSION`, `pin: .mcp.json has <old>, landspec
    pins <new>; delete .mcp.json and run /landspec:aws again` (JSON has no marker, so it is never
    rewritten). When `.claude/settings.json`
    exists, prints `add to .claude/settings.json: <entry>` for each allow/ask/deny entry of
    contracts/scripts.md missing from it (`grep -F`, no rewrite). Prints the `deploy:` line of
    contracts/scripts.md per account kind (`Access=read` for prod and for every account on lite),
    and the `~/.aws/config` profile lines. New `skills/aws/SKILL.md` (pattern: `skills/next/SKILL.md`): first run asks
    for the prod profiles and paths (may be empty), runs `setup`, shows its output as is, and never
    runs the deploy line itself.
  - Impact: `tests/helpers.sh` (new `fake_aws`, pattern: `fake_gh` at `:38`: for now only records
    each call to `$TMP/aws.calls`; T004 adds its answers); `tests/aws.test.sh` (new; pattern:
    `tests/next.test.sh`); `README.md` (the commands
    table near `:99`), `skills/help/SKILL.md` (the commands list at `:23`), `docs/reference.md`
    (the command and the four other config keys in the table near `:261`).
  - Completed when: `bash tests/aws.test.sh` passes with new checks:
    - when `aws.sh setup --prod-profiles prod` runs, then the config has `aws: on` and
      `aws_prod_profiles: prod`, and a `deploy:` line names `CAPABILITY_NAMED_IAM` and
      `Access=read` for prod;
    - when `aws.sh setup --prod-paths infra/prod` runs after that, then `aws_prod_profiles` is
      still `prod`; after `--prod-profiles ''` it is empty;
    - when `.mcp.json` holds `mcp-proxy-for-aws==1.6.0`, then the `pin:` line names 1.6.0 and
      1.7.0, and the file is unchanged;
    - when `.mcp.json` already exists, then the `aws-mcp` entry is printed;
    - when `.claude/settings.json` lacks `Read(./.env*)`, then `add to .claude/settings.json:` names
      it, and the file is byte-for-byte unchanged;
    - on level lite, every `deploy:` line says `Access=read`;
    - when run outside a landspec project, then it exits 1 with the `/landspec:init` hint;
    - no `aws` command is run (`fake_aws` records none).

---

## Phase 4: User Story 2 - Check that Claude is using the right identity (Priority: P1)

**Goal**: `/landspec:aws` run again tells which identity Claude uses and refuses the wrong ones; `--simulate` proves the denies read-only.

**Independent Test**: quickstart L2 (local); Q1, Q3, Q5 (live, T007).

- [ ] T004 [US2] Add `aws.sh check`, which refuses any identity but the agent role, with `--simulate` for the denies, in extension/scripts/aws.sh (depends on T003) — #197
  - Comes from: FR-007, SC-002; User Story 2 scenarios 1–4; contracts/scripts.md "aws.sh check"; data-model "Identity verdict"; research R1, R10
  - What: `aws.sh check` runs `aws sts get-caller-identity --output json` and, for the agent role,
    `aws iam get-role` for its `landspec:access` tag; prints `IDENTITY=`, `ACCOUNT=`, `ROLE=`,
    `ACCESS=` and one `missing: <entry>` per absent `.mcp.json` server or settings entry; verdicts
    and refusal lines exactly as contracts/scripts.md (`agent` exit 0; `user`, `other-role`,
    `no-cli`, `no-credentials` exit 1). `AWS_ACCESS_KEY_ID` set without `AWS_SESSION_TOKEN` adds the
    long-lived-key line; its value is never printed. `--simulate`: `aws iam
    simulate-principal-policy --policy-source-arn <role arn> --action-names <the concrete action of
    each line of denied-actions.txt, plus denied-read-actions.txt when ACCESS=read>` (a wildcard
    entry's second column; the simulator takes no wildcards); prints `denied <action>` or `ALLOWED <action>`;
    any `ALLOWED` exits 1. The skill's second mode runs `check` and shows its output as is; when
    Agent Toolkit skills are missing it shows the install line of research R9.
  - Impact: `tests/helpers.sh` (`fake_aws` of T003 gains answers from
    `AWS_IDENTITY_JSON`, `AWS_ROLE_JSON`, `AWS_SIM_JSON`, records calls, fails on `AWS_FAIL`);
    `tests/aws.test.sh`; `skills/aws/SKILL.md`; `docs/reference.md` (the check and its verdicts).
  - Completed when: `bash tests/aws.test.sh` passes with new checks:
    - when the caller is `arn:aws:sts::111122223333:assumed-role/landspec-agent/s` with tag
      `landspec:access=build`, then `IDENTITY=agent`, `ACCESS=build`, exit 0;
    - when the caller is `arn:aws:iam::111122223333:user/dev`, then `IDENTITY=user`, exit 1, and the
      line names the agent profile; with `AWS_ACCESS_KEY_ID` set to a fake key the test builds at run time (`AKIA` joined to 16 capital letters, never one literal, so the scanner passes the test file) and no session
      token, then it also says long-lived key, and the output never contains `AKIA`;
    - when the caller is `assumed-role/AWSReservedSSO_Admin_x/me`, then `IDENTITY=other-role`, exit 1;
    - when `aws` is missing from `PATH`, or the fake fails, then `no-cli` / `no-credentials`, exit 1,
      and nothing is written;
    - with `--simulate`, the fake records `--action-names` holding `organizations:LeaveOrganization`
      and no `*`; with `ACCESS=build` it holds no `secretsmanager:GetSecretValue`, with `read` it does;
    - when the simulation answers one `allowed` for `s3:DeleteBucket`, then `ALLOWED s3:DeleteBucket`
      and exit 1; all `implicitDeny`/`explicitDeny`, then every line `denied`, exit 0;
    - the fake records only read calls (`sts get-caller-identity`, `iam get-role`,
      `iam simulate-principal-policy`).

---

## Phase 5: User Story 3 - The guard stops dangerous AWS and Terraform commands (Priority: P2)

**Goal**: with `aws: on`, the guard refuses destroys, prod applies and writes, secret reads, and printing `.env` or state files, in every shell form it parses.

**Independent Test**: quickstart L3.

- [ ] T005 [P] [US3] Refuse destroys, prod writes and secret reads in the guard when the AWS layer is on, in extension/scripts/guard.sh — #198
  - Comes from: FR-010, FR-011, SC-004, SC-005; User Story 3 scenarios 1–5; contracts/scripts.md "guard.sh, AWS rules"
  - What: in `check_words`, after the prefix stripping, when `aws` is `on` in the repository the command runs in (read with the prod keys once per
    repository top and cached, like the branch list at `guard.sh:54`; outside a repository the
    rules are off), new branches: `terraform|tofu|*/terraform|*/tofu` → `check_tf`,
    `aws|*/aws` → `check_aws`, and the file readers of contracts/scripts.md → `check_read`, each
    with the refusals and messages of that table. Prod is `aws_prod_profiles` (from `--profile`,
    `--profile=`, or an `AWS_PROFILE=` prefix, which the prefix loop now records instead of
    skipping) and `aws_prod_paths` (the command's directory, `dir`, or `-chdir=`, resolved with
    `resolve`). `.env.example`/`.sample`/`.template`/`.dist` are not refused. In
    `hooks/guard-git.sh:17`, pass the command on when it mentions `git`, `gh`, `aws`, `terraform`,
    `tofu`, `.env` or `.tfstate`; anything else still exits 0 at once.
  - Impact: `guard.sh`'s fast path in `hooks/guard-git.sh:21-25` (a landspec check runs only
    without cd/-C: unchanged); the header comment of `guard.sh`; `tests/guard.test.sh` (pattern: its
    `blocked` helper); `tests/guard-review.test.sh` is unaffected (check); `docs/security.md` (the
    guard row lists the AWS rules, bypassable: best effort, IAM is the boundary; the prod rules see
    only declared names, plan Risks; verbs that change prod without a write prefix, such as
    `ssm send-command`, `lambda invoke`, `sns publish`, `sqs send-message`,
    `dynamodb batch-write-item`, are not refused); `docs/reference.md`.
  - Completed when: `bash tests/guard.test.sh` passes with new checks, in a repo with
    `aws: on`, `aws_prod_profiles: prod` and `aws_prod_paths: infra/envs/prod`:
    - each refused row of contracts/scripts.md is blocked plain, in a chain (`true && …`), in a
      subshell (`( … )`) and behind `timeout 30`: `terraform destroy`, `terraform apply -destroy`,
      `terraform -chdir=infra/envs/prod apply`, `AWS_PROFILE=prod terraform apply`,
      `aws --profile prod s3 rm s3://b/k`, `aws ec2 terminate-instances --profile=prod --instance-ids i-1`,
      `aws secretsmanager get-secret-value --secret-id x`, `aws secretsmanager batch-get-secret-value --secret-id-list x`,
      `aws ssm get-parameter --name x --with-decryption`, `aws ssm get-parameter-history --name x --with-decryption`,
      `cat .env`, `head -5 infra/terraform.tfstate`, `terraform state pull`;
    - allowed: `aws --profile prod ec2 describe-instances`, `aws s3 ls`, `terraform plan -out=tfplan`,
      `terraform -chdir=infra/envs/dev apply`, `cat .env.example`, `aws ssm get-parameter --name x`;
    - with `aws: off`, every command above is allowed (SC-005); and from a repo with `aws: off`,
      `cd <the aws: on repo> && terraform destroy` is blocked (the config of the repo it runs in);
    - `hooks/guard-git.sh` passes `aws s3 rm …` to the guard and still exits 0 at once for `ls -la`.

---

## Phase 6: User Story 4 - A PR that changes infrastructure shows its plan (Priority: P3)

**Goal**: on standard and full with the layer on, a task PR that touches `.tf` files needs a recorded plan for its exact diff, shown in the body.

**Independent Test**: quickstart L4, L5.

- [ ] T006 [P] [US4] Record a Terraform plan per diff and require it in infrastructure PRs, in extension/scripts/tfplan.sh — #199
  - Comes from: FR-012, SC-006; User Story 4 scenarios 1–4; contracts/scripts.md "tfplan.sh record" and "pr.sh, plan gate"; data-model "Plan record"; research R11, R12
  - What: new `extension/scripts/tfplan.sh record <planfile>` (pattern: the scan record of
    `security-scan.sh`): reads `terraform show -json` with `python3` (`resource_changes[].change.actions`:
    `delete` with `create` is a replace, `delete` alone a destroy, `forget` neither), else
    `terraform show -no-color` (the `Plan:` line and `must be replaced` / `will be destroyed`
    lines); `tofu` when `terraform` is missing; refuses a planfile older than the last commit or
    made with an uncommitted `*.tf` file (data-model "Plan record"); writes `diff_record landspec-tfplan` (`lib.sh:194`)
    with the format of data-model "Plan record" (addresses only, never an attribute value); prints
    `PLAN=` and `STATEFUL=` lines; refuses an unreadable plan. `record <planfile> [--chdir <dir>]`
    writes or replaces the section of that root (data-model "Plan record"). A root's modules are
    every `source` starting `./` or `../` in its `*.tf` files, followed recursively, resolved from
    the root; a touched file inside a module counts for every root that uses it. In `pr.sh` (task and fix), next to the
    scan block near `:136-141`: when `cfg aws` is `on`, the level is not lite and the diff touches a
    `*.tf` file, no record, or no section for a touched root in `aws_prod_paths` → the `die` of
    contracts/scripts.md; otherwise the `## Terraform plan` section, one block per root
    (STATEFUL lines first). The refusal names `infra_dir` as the directory to plan in.
  - Impact: `extension/scripts/pr.sh` (the body assembly; `fix/review-findings` also edits pr.sh
    near `:77`, merged before this task starts or rebased onto); `extension/commands/pr.md` (the
    step that runs the scan: add the plan record step when the gate applies); `tests/helpers.sh`
    (new `fake_terraform` answering `show -json` from `TF_PLAN_JSON` and `show -no-color` from
    `TF_PLAN_TEXT`); new `tests/tfplan.test.sh`; `tests/pr.test.sh`; `docs/reference.md`.
  - Completed when: `bash tests/tfplan.test.sh` and `bash tests/pr.test.sh` pass with new checks:
    - when a JSON plan has one create, one update, a `["delete","create"]` on `aws_db_instance.main`
      and a `["delete"]` on `aws_s3_bucket.logs`, then `PLAN=create 2 change 1 destroy 2` (a replace
      counts as one create and one destroy, as Terraform's `Plan:` line does; data-model), and `STATEFUL=replace aws_db_instance.main`,
      `STATEFUL=destroy aws_s3_bucket.logs`; the same plan as text (no `python3` on `PATH`) gives
      the same lines;
    - when the plan holds a sensitive attribute value `hunter2hunter2`, then the record and the
      output never contain it;
    - when the plan file is unreadable, then it exits 1 and writes no record; when it is older
      than the last commit (`touch -t 200001010000`), or a `.tf` file is uncommitted, then it
      exits 1 and the message says `plan again after the last commit, checkout or rebase`; the
      passing checks `touch` the planfile 2 seconds past the commit (bash 3.2 compares whole
      seconds);
    - with `aws_prod_paths: infra/envs/prod` and a diff in `infra/modules/db/main.tf` used by both
      roots: after recording dev only, `pr.sh task` refuses naming `infra/envs/prod`; after both,
      the body has two blocks; recording dev again replaces its block, not adds one;
    - level standard, `aws: on`, a task diff with `infra/main.tf`: `pr.sh task` refuses with
      `no Terraform plan recorded for this diff`; after `tfplan.sh record`, the body has
      `## Terraform plan` with the stateful lines first; a new commit makes it refuse again;
    - level lite, or `aws: off`, or a diff without `.tf`: no refusal, no section (SC-005).

---

## Phase 7: Live verification

**Goal**: the parts the fakes cannot prove, checked once in a real account before release.

- [ ] T007 [US1] Verify the template, the check and the trust modes in a real AWS account, and drop `login` mode if it fails, in extension/aws/agent-role.yaml (depends on T004, T008) — #200
  - Comes from: SC-001, SC-002, SC-003; quickstart Q1–Q6; research R3, R8
  - What: the maintainer runs quickstart Q1–Q6 in a throwaway account (never one with real data):
    deploy dev (`Access=build`) and prod (`Access=read`) stacks, `aws.sh check` and
    `check --simulate` with each profile (`ACCESS=build` for dev, `ACCESS=read` for prod), with
    the dev agent: `iam:CreateRole`, `iam:PassRole` of a pre-existing role to a Lambda,
    `sts:AssumeRole` into a pre-existing role trusting the account, and a bucket policy granting the
    agent's own session `s3:DeleteBucket` followed by that delete (all `AccessDenied`, data-model
    "Invariant (the agent's reach)"), `cloudformation:UpdateStack` on the `landspec-agent` stack
    (`AccessDenied`); then create an ALB (works: the service-linked role); attach `scp-agent.json`
    to the throwaway account's OU and repeat one FR-004 call through the MCP server (`AccessDenied`
    by the SCP), then detach it, one live denied call per account, `/mcp` tool list, Q5,
    then delete both stacks. If Q2 shows a key-signed `sts:AssumeRole` is not denied in
    `TrustMode=login`, remove `login` from the template's allowed values, the `LoginUserNames`
    parameter and its docs, and say Identity Center is required. If Q4 shows the MCP tool names
    differ from research R8, update the allow/ask entries in `aws.sh` and `docs/reference.md`.
  - Impact: `extension/aws/agent-role.yaml`, `extension/scripts/aws.sh`, `tests/static.test.sh`
    (if `login` goes), `docs/security.md`, `docs/reference.md`; nothing else.
  - Completed when: the PR body pastes, redacted of account ids: both `CREATE_COMPLETE` stack
    events, `IDENTITY=agent` with the right `ACCESS=` for each profile, the denied-reach results, the stack update, the ALB, the SCP-denied MCP call, every `--simulate` line `denied`, the `AccessDenied`
    of the live call, Q2's two results (or "login mode removed"), Q4's tool list, Q5's refusal, and
    the stack deletions; `bash tests/run.sh` passes. Failure path: a step that does not give its
    expected result is written in the PR and blocks the release.

---

- [ ] T008 [US1] Ship the optional organization policy and `aws.sh setup --scp`, which prints how to attach it, in extension/aws/scp-agent.json (depends on T001, T003) — #201
  - Comes from: FR-006; contracts/template.md "scp-agent.json"; research R7
  - What: new `extension/aws/scp-agent.json`: the three `Deny` statements of contracts/template.md
    (the first column of `denied-actions.txt` for `aws:PrincipalArn` `role/landspec-agent*`, the
    same for `Bool aws:ViaAWSMCPService true`, and the self-edit actions on
    `role/landspec-agent*`). `aws.sh setup --scp` prints its path and one line: attach it in AWS
    Organizations to the accounts the agent uses; it keeps every config key as it is.
  - Impact: `tests/static.test.sh`; `tests/aws.test.sh`; `docs/security.md` (the AWS row: the SCP
    adds the deny at the organization level for the agent and MCP calls; it does not cover code run
    inside a stronger existing workload); `docs/reference.md` (the flag).
  - Completed when: `bash tests/static.test.sh` and `bash tests/aws.test.sh` pass with new checks:
    - `scp-agent.json` is valid JSON (`python3 -m json.tool`, or `jq`) with three `Deny`
      statements, one conditioned on `aws:ViaAWSMCPService`;
    - its action list equals the first column of `denied-actions.txt` (failure path: add one
      action to the file only, and the check fails);
    - `aws.sh setup --prod-profiles prod`, then `aws.sh setup --scp`: the output names
      `scp-agent.json`, and `aws_prod_profiles` is still `prod`.

---

## Phase 8: Gaps of the whole-feature check

- [ ] T009 [US4] Say in the PR body that the plan gate was skipped when the diff changes infrastructure code that is not Terraform, in extension/scripts/tfplan.sh — #252
  - Comes from: the whole-feature check's feature review, `not met`: spec.md Edge Cases "Infrastructure code that is not Terraform (CDK, CloudFormation, Pulumi): the plan gate does not apply; the PR body says the plan gate was skipped and why"
  - What: in `tfplan.sh gate` (`extension/scripts/tfplan.sh`, the `gate)` branch), when `aws: on`, the level is not lite and the diff (`git diff --name-only --no-renames "$(diff_base)" HEAD`) touches no `*.tf` file but touches non-Terraform infrastructure code, print a `## Terraform plan` section with one line instead of exiting silently: `Skipped: this diff changes infrastructure code that is not Terraform (<up to 3 paths, then "and <n> more">); the plan gate covers Terraform only.` Non-Terraform infrastructure code is a path matching `(^|/)cdk\.json$`, `(^|/)Pulumi(\.[^/]+)?\.ya?ml$` or `\.template\.(json|ya?ml)$` (the CloudFormation naming the CDK and SAM tools write); this list only, never a folder (`infra_dir` may be `.`), so Terraform's own companions (`*.tfvars`, `.terraform.lock.hcl`, `*.tf.json`) never get the line. `pr.sh` already appends the gate's non-empty output to the body (`extension/scripts/pr.sh:152-153`), so it is unchanged. A diff with a `*.tf` file keeps today's behaviour; with neither, the gate still prints nothing.
  - Impact: `extension/scripts/tfplan.sh` (the `gate` branch and its header comment at `:12-14`) and its `.specify/extensions/landspec/scripts/` copy (kept identical); `tests/tfplan.test.sh`; `tests/pr.test.sh` (the plan gate block near `:525-552`); `docs/reference.md` (the plan gate paragraph near `:262-270`); `specs/006-aws-access-layer/contracts/scripts.md` "pr.sh (task and fix), plan gate" gets the skipped line; nothing else.
  - Completed when: `bash tests/tfplan.test.sh` and `bash tests/pr.test.sh` pass with new checks:
    - level standard, `aws: on`, a task diff with only `cdk/cdk.json`: `pr.sh task` opens the PR and the body has `## Terraform plan` and the line `Skipped: this diff changes infrastructure code that is not Terraform (cdk/cdk.json); the plan gate covers Terraform only.`;
    - the same with `stack/Pulumi.dev.yaml` and with `deploy/app.template.yaml`, each named in the line;
    - five matching files: the line names the first 3 in `git diff` order, then `and 2 more`;
    - a diff with `infra/main.tf` and `cdk.json`, no plan recorded: still refused with `no Terraform plan recorded for this diff` (failure path: the skipped line must not stand in for a plan);
    - a diff with only `src/app.py` (also with `infra_dir: .`), or only `infra/terraform.tfvars` or `infra/.terraform.lock.hcl`, or `aws: off`, or level lite: no `## Terraform plan` section.

- [ ] T010 [US2] Report "no prod configured" from `aws.sh check` when the project lists no prod profile, in extension/scripts/aws.sh — #255
  - Comes from: the whole-feature check's feature review, `not met`: spec.md Edge Cases "A developer with only one AWS account: the template is deployed once as dev; nothing about prod is required, and the check reports \"no prod configured\""; data-model "A prod profile or path list that is empty while `aws: on`: allowed (one account only); the check reports \"no prod configured\""
  - What: in `aws.sh check` (`extension/scripts/aws.sh`, after the `ACCESS=` line at `:61`, before the `missing:` lines), when `cfg aws_prod_profiles ""` is empty, print the line `PROD=none: no prod configured (one account only; /landspec:aws --prod-profiles <names> adds one)`; when it is set, print `PROD=<the configured list as is>`. It is information only: it never changes the verdict or the exit code, and `--simulate` is unchanged. The refusals (`user`, `other-role`, `no-cli`, `no-credentials`) keep their output; the `PROD=` line is printed only on the path that prints `ACCESS=` (so not for `no-cli` or `no-credentials`).
  - Impact: `extension/scripts/aws.sh` (the check branch and its header comment near `:25-29`) and its `.specify/extensions/landspec/scripts/` copy (kept identical); `tests/aws.test.sh` (the check block near `:118-160`); `docs/reference.md` (the `aws.sh check` paragraph near `:361-364`); `specs/006-aws-access-layer/contracts/scripts.md` "aws.sh check" (the printed lines); `skills/aws/SKILL.md` step 6 (the lines it shows: `IDENTITY=`, `ACCOUNT=`, `ROLE=`, `ACCESS=`); nothing else.
  - Completed when: `bash tests/aws.test.sh` passes with new checks:
    - the agent caller (tag `build`) with no `aws_prod_profiles` key: output has the exact line `PROD=none: no prod configured (one account only; /landspec:aws --prod-profiles <names> adds one)`, after `ACCESS=build`, and exit 0;
    - the same with `aws_prod_profiles: ""` (setup's empty value): the same line;
    - with `aws_prod_profiles: prod,prod-eu`: the line `PROD=prod,prod-eu` and no `no prod configured`;
    - an IAM user caller with no prod profiles: still exit 1 with its refusal, and the `PROD=` line printed (failure path: the line never turns a refusal into a pass);
    - `no-credentials`: no `PROD=` line;
    - the existing check, `--simulate` and setup checks pass unchanged.

---

## Dependencies & order

- Start at once: T001, T002, T005, T006 (`/landspec:implement 006`).
- T008 after T001 and T003 (the list and the `setup` flags).
- T003 after T001 and T002 (prints the template path, runs `level.sh`); T004 after T003 (same
  script, the skill's second mode); T007 after T004 and T008 (needs all of US1 and US2, and the SCP).
- MVP: T001–T004 (a safe role, the project set up for it, and a check that refuses the wrong
  identity).
