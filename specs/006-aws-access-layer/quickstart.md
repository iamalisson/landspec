# Quickstart: validating the AWS layer

Two parts. **Local** runs anywhere, in CI too, with fakes. **Live** needs a throwaway AWS account
(or two: dev and prod) and an admin who deploys the stack; CI has no AWS access, so the maintainer
runs it once before the release and pastes the results in the release PR.

## Local (CI)

Prerequisites: the repository, bash 3.2 or 5, git, the fake `gh`/`aws`/`terraform` from
`tests/helpers.sh`.

| # | Run | Expect |
|---|---|---|
| L1 | `tests/run.sh` | all pass, both CI jobs; the existing checks unchanged (SC-005) |
| L2 | `tests/aws.test.sh` | setup writes `.mcp.json` when missing and keeps it when present, prints the missing settings entries, sets the config keys, adds the Cloud access section for the level; check gives each verdict of data-model "Identity verdict" from a fake `aws sts get-caller-identity` |
| L3 | `tests/guard.test.sh` | every row of contracts/scripts.md "guard.sh, AWS rules" blocked plain, in a chain, in a subshell and behind `timeout`; the read-only forms allowed; with `aws: off` none of them blocked (SC-004) |
| L4 | `tests/tfplan.test.sh` | counts and `STATEFUL` lines from a JSON plan and from a text plan agree; an unreadable plan refused |
| L5 | `tests/pr.test.sh` | standard + `aws: on` + a `.tf` change: refused without a record, body carries the plan with record; lite, or `aws: off`, or no `.tf`: no gate; a new commit voids the record |
| L6 | `tests/static.test.sh` | template and SCP parse; their deny lists equal `denied-actions.txt`; `MCP_PROXY_VERSION` agrees across pins.sh and the scaffold |

Each new check is run once with its rule disabled and seen to fail (constitution); the PR says so.

## Live (maintainer, before release)

Prerequisites: AWS CLI ≥ 2.32, an Identity Center permission set for yourself, an admin profile.

| # | Steps | Expect |
|---|---|---|
| Q1 | In a test project: `/landspec:aws`; run the printed deploy line for dev (`Access=build`) and prod (`Access=read`); add the printed profiles; `aws sso login`; `/landspec:aws` again | stacks `CREATE_COMPLETE`; check prints `IDENTITY=agent` with the right `ACCESS`; under 15 minutes per account (SC-001) |
| Q2 | Dropped with `login` mode (T007, #251); kept for the record. `TrustMode=login` only: assume the role once with an `aws login` session and once with an IAM user's access key | the first succeeds, the second is `AccessDenied`. If the key is not denied, drop `login` mode (research R3) |
| Q3 | `bash .specify/extensions/landspec/scripts/aws.sh check --simulate` with each profile; then one live destructive call per account on a resource the stack made for it (e.g. `aws iam create-user --user-name x`) | every FR-004/FR-005 action `denied`; the live call `AccessDenied` (SC-002) |
| Q4 | Start Claude Code in the project; `/mcp` | `aws-mcp` connected as the agent profile; its tool list matches research R8 (confirms whether `call_aws` is gone) |
| Q5 | With `AWS_PROFILE` set to your admin profile, `/landspec:aws` | `IDENTITY=other-role`, refused with the profile to use |
| Q6 | Delete both stacks | the roles are gone; nothing else was created (SC-003: no user, no key) |
