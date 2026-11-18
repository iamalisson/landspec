# Feature Specification: Safe AWS access for Claude Code

**Feature Branch**: `spec/006-aws-access-layer`

**Created**: 2026-11-16

**Status**: Draft

**Input**: User description: "I have some scripts and things to install into the aws cli, that will create roles, etc so my claude code can access/help me with AWS things in a secure way [iamalisson/helper]. I have this too: the Meridian playbook and meridian-agent-kit. Integrate this in a useful way: a script I can run in my AWS CLI/console that Claude Code can use through landspec, with the best practices." Decisions (user, 2026-11-16): no landspec commands for doing AWS work (AWS's own Agent Toolkit and MCP server do that); one setup and health-check command, `/landspec:aws`; the AWS rules go into landspec's existing guard and PR gate.

## Context

The helper repository is a teaching setup: the agent writes to AWS directly with the CLI, in one
account, with every tool trusted, using temporary tokens minted from long-lived keys. The Meridian
playbook (p.5) calls it that and replaces it with: the agent writes infrastructure as code, a human
approves every apply, production is read-only for the agent, and AWS permissions (role, deny,
organization policy) are the boundary, while hooks and client rules are only safety nets
("Five layers of control", p.4). This feature brings that model into landspec for any project that
uses AWS, without landspec doing the AWS work itself.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set up a safe AWS identity for Claude once (Priority: P1)

A developer wants Claude Code to help with their AWS accounts without handing it their own admin
rights or any long-lived key. They run `/landspec:aws`. landspec gives them a setup template and the
one command to deploy it themselves, from their own credentials, in each account (dev, and prod if
they have one). The template creates the agent's role: in dev it can build, but it cannot create or change
any IAM role, user or policy, and it is denied deleting data, touching audit services or changing
its own access; in
prod it can only read, and cannot read secret values or data. The role can be assumed only by the
developer's own short-lived IAM Identity Center sign-in, never by an access key.
Claude never creates or changes its own role.

**Why this priority**: every other part relies on this identity. AWS permissions are what actually
stop a mistake; everything else is a second line.

**Independent Test**: in a test account, deploy the template, assume the role, and see that a read
succeeds, a dev build call succeeds, a delete of a database or bucket is denied, a change to the
role's own policies is denied, and in prod any write and any secret read is denied.

**Acceptance Scenarios**:

1. **Given** a project with no AWS setup, **When** the developer runs `/landspec:aws`, **Then**
   landspec writes the setup template into the project and shows the deploy command for each
   account, and runs nothing against AWS itself.
2. **Given** the deployed dev role, **When** it tries to delete a database, a bucket, a table or an
   encryption key, stop audit logging, create a user or an access key, or edit its own role,
   **Then** AWS denies it.
3. **Given** the deployed prod role, **When** it tries any write, or reads a secret value, a
   parameter, an object or a table's items, **Then** AWS denies it; describe and list calls succeed.
4. **Given** a developer whose AWS setup uses AWS Organizations, **When** they ask for it, **Then**
   landspec also provides the organization policy (SCP) that denies the same destructive actions to
   the agent role and to any call made through the AWS MCP server, for a human to attach.
5. **Given** the template is deployed again after a change, **When** it updates, **Then** it changes
   the existing role in place, and removing it removes everything it created.

---

### User Story 2 - Check that Claude is using the right identity (Priority: P1)

Before Claude touches AWS, the developer wants to know which identity it will use. Running
`/landspec:aws` again checks the current AWS identity and says, in plain words, whether it is the
agent role (good), an IAM user with access keys (refused, with how to switch), or a broad human or
admin role (refused, with how to switch). It also checks that the project's MCP server entry and
client rules are in place. It can be run any time, like `/landspec:next`.

**Why this priority**: the safest role is useless if Claude quietly runs with the developer's
admin profile or an old access key.

**Independent Test**: run the check with the agent role, with an access-key user and with an admin
role, and see one pass and two refusals that each say what to run.

**Acceptance Scenarios**:

1. **Given** credentials for the agent role, **When** the check runs, **Then** it reports the
   account, the role and the environment (dev or prod) and passes.
2. **Given** credentials from an IAM user's access key, **When** the check runs, **Then** it refuses
   and says how to sign in with short-lived credentials instead.
3. **Given** a role other than the agent role, **When** the check runs, **Then** it refuses and
   names the profile to use.
4. **Given** no AWS CLI or no credentials, **When** the check runs, **Then** it says what is missing
   and what to run, and changes nothing.

---

### User Story 3 - The guard stops dangerous AWS and Terraform commands (Priority: P2)

In a project where the AWS layer is on, landspec's existing command guard also refuses, whatever
the shell form (chains, subshells, prefixes, `sh -c`): destroying infrastructure, applying or
writing to prod, reading secret values, and reading `.env` or Terraform state files into the
conversation. Each refusal says why and what to do instead (for prod: open a PR, the pipeline
applies it).

**Why this priority**: a second line behind IAM, and the first one Claude sees: it stops the
command before it runs and tells Claude why, instead of an AWS access-denied error after the fact.

**Independent Test**: with the layer on, send the guard each refused form, plain and hidden in a
chain, a subshell and a `timeout` prefix, and see each blocked; send read-only commands and see
them allowed; with the layer off, see none of these rules apply.

**Acceptance Scenarios**:

1. **Given** the layer is on, **When** Claude runs `terraform destroy` or `terraform apply -destroy`,
   **Then** it is blocked in every account.
2. **Given** the layer is on, **When** Claude runs `terraform apply` or an AWS write call aimed at
   a prod profile or account, **Then** it is blocked and told that prod changes go through a PR.
3. **Given** the layer is on, **When** Claude reads a secret value or prints a `.env` or Terraform
   state file, **Then** it is blocked.
4. **Given** the layer is on, **When** Claude runs describe, list, get (other than secret values),
   `terraform plan`, `fmt` or `validate`, **Then** it is allowed.
5. **Given** a project where the layer is off, **When** any of these commands runs, **Then** the
   guard behaves exactly as it does today.

---

### User Story 4 - A PR that changes infrastructure shows its plan (Priority: P3)

On levels standard and full, a task PR that changes infrastructure code cannot open until a
Terraform plan summary for its exact diff is recorded: how many resources are created, changed and
destroyed, and which stateful resources are destroyed or replaced. The summary goes in the PR body
so the human approving it sees what will happen. A plan that destroys or replaces a stateful
resource is called out at the top of the body.

**Why this priority**: it turns "a human approves every consequential change" into something the
PR shows, but the review and CI already catch much of this, so it comes last.

**Independent Test**: on level standard, open a PR that changes a file under the infrastructure
folder without a plan record and see it refused; record a plan and see the body carry its summary;
on lite, see no plan required.

**Acceptance Scenarios**:

1. **Given** level standard or full and a task diff that touches infrastructure code, **When**
   `pr.sh` runs without a plan record for that diff, **Then** it refuses and says what to run.
2. **Given** a recorded plan, **When** the PR opens, **Then** its body lists the create, change
   and destroy counts, and any stateful resource destroyed or replaced is named first.
3. **Given** level lite, or a diff that touches no infrastructure code, **When** `pr.sh` runs,
   **Then** no plan is required.
4. **Given** a plan record, **When** a new commit changes the diff, **Then** the record no longer
   counts, the same way a review record does today.

---

### Edge Cases

- A developer with only one AWS account: the template is deployed once as dev; nothing about prod
  is required, and the check reports "no prod configured".
- Claude Code's environment already has `AWS_ACCESS_KEY_ID` set: the check names it as the
  reason the identity is a key, without printing its value.
- The project already has `.claude/settings.json` or `.mcp.json`: landspec does not overwrite them
  (constitution: nothing of the user's is overwritten); it prints the entries to add and the check
  reports which are missing.
- Infrastructure code that is not Terraform (CDK, CloudFormation, Pulumi): the plan gate does not
  apply; the PR body says the plan gate was skipped and why.
- A prod profile that is not named like prod: the prod accounts and profiles are listed in the
  project's landspec config, not guessed from names.
- The AWS MCP server or the Agent Toolkit is not installed: the check prints `missing: .mcp.json:
  the aws-mcp server` (setup prints the entry to add) and `/landspec:aws` says how to add the
  Agent Toolkit; the rest of landspec works without it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: landspec MUST provide one command, `/landspec:aws`, that sets up the AWS layer the
  first time and checks it on every later run. landspec MUST NOT add commands that perform AWS
  operations (creating, changing or deploying resources).
- **FR-002**: The command MUST write a setup template that a human deploys with their own
  credentials, and MUST show the exact deploy command per account. landspec MUST NOT deploy it,
  run any AWS write call, or create or change the agent's role itself.
- **FR-003**: The template MUST create, per account, an agent role assumable only through
  short-lived human sign-in through IAM Identity Center (`aws login` mode was dropped: research R3
  could not be confirmed live, T007), with a session of at most one
  hour, and MUST NOT create IAM users, access keys or console passwords.
- **FR-004**: In dev, the agent role MUST act only as itself: no IAM write (service-linked roles
  aside), no passing a role to a service, no assuming another role, no IAM Identity Center write;
  and it MUST deny deleting databases, snapshots, buckets, tables and encryption keys; stopping or
  deleting audit, threat detection and budget services; creating users or keys; organization and
  account changes; and any change to its own role. IAM changes the project needs (an application's
  role) go through a PR and the project's pipeline, and since the agent cannot pass a role, applies in dev are limited to resources that take no role (no Lambda, ECS task, EC2 instance profile or other resource that is handed a role); anything with a role goes through the pipeline.
- **FR-005**: In prod, the agent role MUST be read-only and MUST deny reading secret values,
  parameters, decrypted data, objects, table items and database connections.
- **FR-006**: When asked, landspec MUST provide the organization policy that applies FR-004's
  denies to the agent role and to every call made through the AWS MCP server, for a human to
  attach.
- **FR-007**: The command's check MUST report the current AWS identity (account, role,
  environment) and MUST refuse, with what to run instead, when the identity is an access-key user
  or a role other than the agent role. It MUST never print a credential.
- **FR-008**: The command MUST add the AWS MCP server entry (pinned to an exact version) and the
  allow/ask/deny client rules only to files that do not exist yet, and otherwise MUST print the
  entries to add; the check MUST report which are missing.
- **FR-009**: The command MUST add a "Cloud access" section to the constitution, sized by level:
  lite, the agent only reads; standard, it may apply in dev after the human approves (applies in dev are limited to resources that take no role (no Lambda, ECS task, EC2 instance profile or other resource that is handed a role); anything with a role goes through the pipeline); full, as
  standard, and prod changes only through the pipeline after an approved PR.
- **FR-010**: When the AWS layer is on, the guard MUST refuse infrastructure destroys, applies and
  AWS write calls aimed at a prod account or profile, reading secret values, and printing `.env` or
  Terraform state files, in every shell form the guard already understands. When the layer is off,
  the guard MUST behave as before.
- **FR-011**: The prod accounts and profiles MUST be declared in the project's landspec config and
  MUST NOT be guessed from names.
- **FR-012**: On levels standard and full, `pr.sh` MUST refuse a task PR whose diff touches
  Terraform code until a plan summary for that exact diff is recorded, and MUST put the summary
  (create, change, destroy counts; stateful resources destroyed or replaced named first) in the PR
  body. A new commit MUST invalidate the record.
- **FR-013**: `docs/security.md` MUST list each new layer with what it checks and whether it can
  be bypassed, and the README and `/landspec:help` MUST describe the command; each GUARDRAILS row
  MUST name its primary source.
- **FR-014**: Each new guard rule and gate MUST ship with a test that was seen to fail when the
  rule is disabled, on bash 3.2 and bash 5.

### Key Entities

- **Agent role**: the AWS identity Claude uses in one account; its environment (dev or prod), its
  permissions, its deny, and who may assume it.
- **Setup template**: the reviewable, updatable and removable description of the agent role and its
  policies, deployed by a human per account.
- **Organization policy**: the optional account-wide deny for the agent role and MCP calls.
- **AWS layer config**: in the project's landspec config: on or off, the infrastructure folder,
  and the prod accounts and profiles.
- **Plan record**: the Terraform plan summary bound to one exact diff, like the review record.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer goes from no AWS setup to a passing `/landspec:aws` check in under 15
  minutes per account, running only the commands the check shows.
- **SC-002**: In a test account, 100% of the denied actions listed in FR-004 and FR-005 are denied
  for the agent role, and its read calls succeed.
- **SC-003**: 0 long-lived AWS credentials are created or required by the setup.
- **SC-004**: Every refused form in User Story 3 is blocked, plain and inside a chain, a subshell
  and a runner prefix; every read-only form listed is allowed.
- **SC-005**: Projects without the AWS layer see no change: the existing test suite passes
  unchanged.
- **SC-006**: Every infrastructure PR on standard and full shows its create, change and destroy
  counts in its body.

## Assumptions

- AWS's own Agent Toolkit and MCP server do the AWS work (API calls, documentation, skills);
  landspec only sets up the identity, guards commands and gates PRs.
- The setup template is CloudFormation: a human can review it as a diff, update it in place, see
  drift, and remove it as one stack. A bash script of CLI calls (as in the helper repository) is not
  used because a failed run leaves partial resources and it cannot be removed as one unit.
- The plan gate covers Terraform only; other infrastructure tools are a later feature.
- The permissions and denies start from the Meridian kit's `guardrails/*.json` and security rules,
  generalized (no project names) and checked against current AWS documentation during planning.
- The helper repository's scripts (`generate-sts-token.sh`, `criar_role_ssm.sh`) are not reused:
  the first relies on long-lived base keys and the second creates an EC2 instance role, not an
  agent identity.
- Running the agent on an EC2 workspace through Session Manager (the Meridian "workspace" option)
  is out of scope; the same role can be its instance role, and the docs say so in one line.
- The guard and hooks remain a second line of defense; the docs say IAM and the organization
  policy are the boundary.
