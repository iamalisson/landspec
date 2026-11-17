### Cloud access in prod

- Prod changes only through the pipeline, after an approved pull request: the agent never applies,
  deploys or makes an AWS write call in a prod account.
