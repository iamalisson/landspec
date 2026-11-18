# Contracts: scripts and the command

All scripts source `lib.sh`, start with `landspec_cd_root`, refuse with one `die` line that says
what to run, and never print a credential.

## `/landspec:aws` (skills/aws/SKILL.md)

One command, two modes chosen by state, never an AWS write:

1. `aws: off` (first run): asks for the prod profiles and paths (may be empty), runs
   `aws.sh setup`, shows what it printed (files created or kept, entries to add by hand, the deploy
   command per account), then runs `aws.sh check`.
2. `aws: on` (every later run): runs `aws.sh check` and shows its verdict and what to fix.

It never runs the deploy command itself, and never edits a policy or role (FR-002).

## `aws.sh setup [--prod-profiles a,b] [--prod-paths p,q]`

- Sets `aws: on`, the prod keys, `aws_agent_role`, and `infra_dir` (the folder holding the most
  `*.tf` files from `infra_files`, default `infra`; used in the plan gate's refusal text). A flag
  left out keeps the key's current value (a rerun with `--scp` alone never empties the prod lists);
  an empty value given on purpose (`--prod-profiles ''`) empties it.
- Writes `.mcp.json` only when it does not exist, through `level.sh`'s `put` (a generator like `security_yaml`, so the pin expands;
  recorded for `remove.sh`): `uvx mcp-proxy-for-aws==<MCP_PROXY_VERSION from pins.sh>
  https://aws-mcp.us-east-1.api.aws/mcp --metadata AWS_REGION=<region>`, with
  `AWS_PROFILE=landspec-agent-dev` in its env. Otherwise prints the `aws-mcp` entry to add.
- The client entries: allow `mcp__aws-mcp__aws___search_documentation`, `…read_documentation`,
  `…retrieve_skill`, `…list_regions`, `…get_regional_availability`; ask `mcp__aws-mcp__aws___run_script`,
  `…get_presigned_url`; deny `Read(./.env*)` (templates aside), `Read(**/*.tfstate*)`. The Read
  denies matter: the guard sees Bash only.
- Never writes an existing `.claude/settings.json`; prints the allow, ask and deny entries that
  are missing from it (checked with `grep -F`, no JSON rewrite).
- Re-renders the constitution block through `level.sh <current level> --no-branches`, which adds
  the "Cloud access" section.
- Prints, per account kind, one line:
  `aws cloudformation deploy --stack-name landspec-agent --template-file .specify/extensions/landspec/aws/agent-role.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides Access=<read|build> TrustMode=sso PermissionSetName=<name> --profile <your admin profile>`
  and the `~/.aws/config` profile to add: `[profile landspec-agent-<env>]` with `role_arn` and
  `source_profile = <your sso profile>`.
  (`Access=read` for prod and for every account on level lite).
- Prints the path of `scp-agent.json` and one line on attaching it, only when asked (`--scp`).
- Output lines: `created: <path>`, `kept: <path>`, `add to <file>: <entry>`, `deploy: <command>`.
- Exit 0; exit 1 when not in a landspec project.

## `aws.sh check`

- Prints `IDENTITY=<verdict>` (data-model, "Identity verdict"), `ACCOUNT=<id>`, `ROLE=<name>`,
  `ACCESS=<read|build|unknown>`, `PROD=<aws_prod_profiles as is>` or, when that key is empty or
  absent, `PROD=none: no prod configured (one account only; /landspec:aws --prod-profiles <names> adds one)`
  (information only: it never changes the verdict or the exit code; not printed for `no-cli` or
  `no-credentials`), then `missing: <entry>` lines for absent MCP or client entries.
- Refusals (exit 1), one line each:
  - `user`: `landspec: this is your own IAM user <name>, not <role>; use the profile that assumes <role> (aws sso login --profile <p>)`, plus `it is a long-lived access key: remove it from the environment` when `AWS_ACCESS_KEY_ID` is set without a session token
  - `other-role`: `landspec: this is role <name>, not <role>; use the profile that assumes <role> (AWS_PROFILE=<profile>)`
  - `no-cli`, `no-credentials`: what to install or run.
- With `--simulate`: runs `aws iam simulate-principal-policy` for the role against
  `denied-actions.txt` and, when `ACCESS=read`, `denied-read-actions.txt` (a wildcard entry is
  simulated through its concrete action, contracts/template.md) and prints `denied <action>` / `ALLOWED <action>`; any `ALLOWED` exits 1.
  Read-only (research R10).

## `tfplan.sh record <planfile>`

- Runs `terraform show -json <planfile>` and reads it with `python3`; without `python3`,
  `terraform show -no-color <planfile>` (research R11). `tofu` when `terraform` is missing.
- Writes or replaces the planned root's section of the plan record for the current diff
  (data-model, "Plan record"); `record <planfile> [--chdir <dir>]`, the root defaulting to the
  planfile's directory.
- Prints `PLAN=create <n> change <n> destroy <n>` and one `STATEFUL=<replace|destroy> <address>` per
  stateful resource destroyed or replaced.
- Refuses when the planfile cannot be read, or the output has neither a `Plan:` line nor
  `No changes.`

## `pr.sh` (task and fix), plan gate

Only when `aws: on`, the level is standard or full, and the diff touches a `*.tf` file:
- No record for this diff, or none for a touched root in `aws_prod_paths`: `die "no Terraform plan recorded for this diff; run terraform plan -out=tfplan in <dir>, then bash .specify/extensions/landspec/scripts/tfplan.sh record tfplan"`.
- With a record: the body gets `## Terraform plan` with the counts; `STATEFUL` lines first, under
  `**Destroys or replaces stateful resources:**`.
- With `aws: on` and a level other than lite, a diff with no `*.tf` file but a path matching
  `(^|/)cdk\.json$`, `(^|/)Pulumi(\.[^/]+)?\.ya?ml$` or `\.template\.(json|ya?ml)$`: no refusal; the
  body gets `## Terraform plan` with one line, `Skipped: this diff changes infrastructure code that
  is not Terraform (<up to 3 paths in git diff order, then "and <n> more">); the plan gate covers
  Terraform only.`

## `guard.sh`, AWS rules (only when `cfg aws` is `on`)

Checked in `check_words`, after the existing prefix stripping, for `terraform`/`tofu`, `aws`, and
file readers. Each refusal exits 2 with one line. `aws`, `aws_prod_profiles` and `aws_prod_paths`
are read from the repository the command runs in (after a `cd` or `-C`), cached per repository
top like the branch list (`guard.sh:54`); outside any repository the rules are off.

| Command (any shell form the guard parses) | Refused when | Message names |
|---|---|---|
| `terraform destroy`, `terraform apply -destroy`, `terraform apply` with `-destroy` anywhere | always | destroys go through a reviewed PR and a human |
| `terraform apply` | the directory (cwd, `-chdir=`) is in `aws_prod_paths`, or `AWS_PROFILE=` is a prod profile | prod changes go through a PR; the pipeline applies them |
| `aws <service> <verb>` with a write verb (`create-*`, `delete-*`, `put-*`, `update-*`, `modify-*`, `terminate-*`, `run-*`, `start-*`, `stop-*`, `attach-*`, `detach-*`, `associate-*`, `disassociate-*`, `register-*`, `deregister-*`, `reboot-*`, `restore-*`, `s3 rm/mv/cp/sync/rb`) | `--profile <p>` or `AWS_PROFILE=<p>` names a prod profile | the same |
| `aws secretsmanager get-secret-value` or `batch-get-secret-value`, `aws ssm get-parameter`, `get-parameters`, `get-parameters-by-path` or `get-parameter-history` with `--with-decryption` | always | secret values stay out of the conversation |
| `cat`, `less`, `more`, `head`, `tail`, `bat`, `grep`, `sed`, `awk`, `strings`, `xxd` on a `.env*` (not `.env.example`/`.sample`/`.template`/`.dist`) or `*.tfstate*` file, and `terraform state pull`, `terraform show` of a state file | always | the same |

Read-only forms stay allowed: `aws … describe-*/list-*/get-*` (other than the secret reads),
`terraform plan/fmt/validate/init/show <planfile>/output`.

The plugin hook (`hooks/guard-git.sh`) passes a command to the guard when it mentions `git`, `gh`,
`aws`, `terraform`, `tofu`, `.env` or `.tfstate`; anything else still exits 0 at once.
