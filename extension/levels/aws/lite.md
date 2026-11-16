### Cloud access

- The agent reaches AWS only through the `landspec-agent-<env>` profiles (the `aws-mcp` server in
  `.mcp.json` runs as `landspec-agent-dev`), never through an admin, root or SSO profile.
- It never reads secret values, `.env` files or Terraform state, and never prints a credential.
- The agent only reads: it changes no resource in any account. A human, or the pipeline, makes
  every change.
