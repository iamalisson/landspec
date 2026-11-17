### Cloud access in dev

- The one exception to reading only: in the dev account, the agent may apply a change after the
  human approves its plan. Applies in dev are limited to resources that take no role (no Lambda,
  ECS task, EC2 instance profile or other resource that is handed a role); anything with a role
  goes through the pipeline.
- Every other account stays read only for the agent.
