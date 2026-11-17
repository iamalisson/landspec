---
name: aws
description: "Turn on landspec's AWS access layer in a project: asks which AWS profiles and Terraform folders are prod, sets aws: on, writes .mcp.json and the constitution's Cloud access text, and prints the client entries to add and the CloudFormation deploy command per account for the human to run. Never makes an AWS call. Use for /landspec:aws, or when the user wants Claude to work with AWS safely."
---

# AWS access layer

1. If `.specify/extensions/landspec/` does not exist, tell the user to run `/landspec:init` first,
   and stop.
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
   `aws` command, or edit a policy or role yourself.
