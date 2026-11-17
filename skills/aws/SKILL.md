---
name: aws
description: "Turn on landspec's AWS access layer in a project: asks which AWS profiles and Terraform folders are prod, sets aws: on, writes .mcp.json and the constitution's Cloud access text, and prints the client entries to add and the CloudFormation deploy command per account for the human to run; on a later run, checks that Claude runs as the agent role (aws.sh check). Never makes an AWS write. Use for /landspec:aws, or when the user wants Claude to work with AWS safely."
---

# AWS access layer

1. If `.specify/extensions/landspec/` does not exist, tell the user to run `/landspec:init` first,
   and stop.
   If the config already has an `aws: on` line and the user asked to change no prod profile or
   path, go straight to step 6.
2. If the config (`.specify/extensions/landspec/landspec-config.yml`) has no `aws: on` line (first
   run), ask once, both in one question, and say either may be empty (one account only):
   - the AWS CLI profiles that reach a prod account, comma separated (matched exactly; nothing is
     guessed from a name containing "prod");
   - the folders whose Terraform targets prod, comma separated (e.g. `infra/envs/prod`).
3. Run `bash .specify/extensions/landspec/scripts/aws.sh setup --prod-profiles <profiles> --prod-paths <paths>`,
   passing `''` for an empty answer. On a later run (`aws: on` already), pass only a flag the user
   asked to change: a flag left out keeps its current value.
   - If it stops with `takes comma-separated names`, show the message, ask again, and rerun.
4. Show what it printed, as is: the files created or kept, each `add to <file>:` entry (the user
   adds them by hand; landspec never rewrites an existing `.mcp.json` or `.claude/settings.json`),
   a `pin:` line, each `deploy:` line, and the `~/.aws/config` profile lines.
5. Tell the user to run each `deploy:` line themselves, with their own admin profile, once per
   account, then add the profile lines with that account's id. Never run a `deploy:` line, any
   other `aws` command, or edit a policy or role yourself.
6. Run `bash .specify/extensions/landspec/scripts/aws.sh check` (after setup, once the user
   says the stack is deployed and the profile is in use) and show its output as is:
   `IDENTITY=`, `ACCOUNT=`, `ROLE=`, `ACCESS=`, each `missing:` entry and the refusal line, which
   says what to fix. It makes read calls only and never prints a key. When the user asks to prove
   the denies, run it with `--simulate` and show each `denied` / `ALLOWED` line; an `ALLOWED` line
   means the role grants an action it must not: the user fixes the stack, never you.
7. If you have no AWS Agent Toolkit skills, say how to add them: `/plugin install
   aws-core@claude-plugins-official` in Claude Code, or `aws configure agent-toolkit` (AWS CLI
   2.35.0 or later; it writes its own MCP config, which should use the `landspec-agent-dev`
   profile).
