### Simplicity (KISS, YAGNI)

- Build the smallest thing that fully solves the task. No abstraction, option or "for later" code
  nobody asked for.
- Choose in this order: what the codebase already has → the standard library → an installed
  dependency → a new dependency.

### Secrets

- No secret, token or password in the repository, in logs, or in client-side code. Configuration
  comes from the environment; `.env` files are git-ignored and an `.env.example` documents the keys.

### Accessibility (when the project has a user interface)

- What people see meets WCAG 2.2 AA: text contrast at least 4.5:1 against its background (3:1
  for large text, 24 px or 18.7 px bold, and for icons, borders and focus indicators), a visible
  focus on every control, an accessible name on every control and image. A colour copied from an
  existing page is checked too: the old page may already fail.

### Tests

- Every piece of logic (parsing, validation, money, permissions, sorting) has a test, written as
  "when …, then …".
- A failing test is never deleted, skipped or loosened to make it pass.
- One command runs the whole suite: `{{TEST_COMMAND}}`.

### Way of working

- One feature = one branch = one pull request; landspec creates no GitHub issues. The feature's
  tasks run in parallel, and a task is done when it lands on the feature branch with its review;
  a ticked checkbox alone is not done.
- Features go through specs and tasks. A small fix (a typo, a one-line bug, a dependency bump)
  goes on a normal branch and PR: no spec needed, but the review, hooks and CI still apply.
- Branch flow: `{{BRANCH_FLOW}}`, always through a pull request.
- Each task's diff is reviewed by a fresh reader against the whole repository before it lands
  (`/speckit-landspec-review`); High and Medium findings block it. The feature PR opens as a
  draft (`pr.sh feature`) and is marked ready only after its feature review, recorded for its
  head, and one scan of the feature diff; it merges once. Any other PR goes through `pr.sh fix`:
  its review is recorded for the exact diff and its `## Review` section says what was found and
  done.
