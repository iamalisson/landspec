# Project guidelines

How `/landspec:new` sets a project up, and what its first spec should cover. `/landspec:new`
reads this file. On later features the agent follows the project's constitution, so `new` and
`adopt` copy the rules that matter for this project into its "Project principles". They are short on purpose. If a rule doesn't help, drop it. The
mistakes to catch are in `GUARDRAILS.md`. Before deciding anything on a listed topic, check its
primary source in `references.yaml`.

**Start simple, well done and secure. Add complexity only when a real need shows up, and write
that need down.**

## Architecture

- **One deployable unit until there is a reason for two.** A modular monolith is the default.
  Split out a service only for a different scaling profile, a different team, or a hard
  isolation requirement. Never split for "cleanliness".
- **Modules by feature, not by layer.** `src/orders/`, `src/billing/`, not `controllers/`,
  `services/`, `models/`. Each module owns its routes, logic and storage, and exposes a small
  interface. Other modules use that interface, never its internals.
- **Keep the edges thin.** HTTP handlers parse and validate input, call one function, and map the
  result to a response. Business rules live in plain functions you can test without a server.
- **Add a layer when it pays for itself.** A trait or interface is worth it once there are two
  real implementations, or a slow or external dependency to fake in tests. Not before.
- **When to add what.** Each row is a trigger, not a default:

  | Add | Only when |
  |---|---|
  | a database | the data must outlive a restart or be shared between instances |
  | a cache | a measured hot path is too slow and the data can be stale |
  | a queue or background jobs | work is slow, retryable, or must not block a request |
  | a second service | see "one deployable unit" above |
  | private subnets and NAT | compliance or data sensitivity asks for it |
  | multiple environments | someone other than the developer depends on the running service |

  Record each one with `/speckit-plan` (the plan's Complexity Tracking), so the reason survives.
  "Design for scale from day one" and "event-driven/CQRS by default" are the opposite of this
  rule. Scale what you've measured; use CQRS or event sourcing only where reads and writes really
  diverge.
- **Write decisions down.** A decision that is hard to reverse (stack, database, a new service,
  a public API shape) gets a few lines: context, decision, consequences. Put them in the
  feature's `plan.md` or `docs/decisions/NNNN-title.md`.
- **Contracts at the boundary.** A public API gets a schema (OpenAPI or the framework's
  validation schemas) and is versioned (`/v1`) once someone outside the team calls it.

## Code

- **Clear beats clever.** Names say what a thing is. Functions do one thing. Keep nesting shallow
  by returning early.
- **Errors are values.** Return them, add context, and handle them once at the edge. Clients see a
  safe message and the right status; internals go to the log. Never swallow an error.
- **Configuration from the environment**, read and validated once at startup. Bad config stops
  the process with a clear message. No scattered `getenv` calls.
- **No dead code, no "for later" code.** Version control remembers. Delete beats comment out.
- **Dependencies:** standard library first, then a well-known library, then your own code. Every
  new dependency is a decision: maintained? license? what does it pull in? Pin with a lockfile.

## Algorithms and data

- **Pick the data structure first.** Lookups go in a map or set, ordered data in a sorted
  structure or an index. Most performance bugs are a list scanned inside a loop (O(n²)).
- **Let the database do database work.** Filter, sort and paginate in the query, behind an
  index, not in application memory. Always paginate lists, and cap page sizes.
- **Bound everything:** request body size, timeouts on every outbound call, page sizes, retries
  (with backoff), queue lengths. Unbounded means a denial of service waiting to happen.
- **Measure before optimizing.** State a target (like SC-001 "under 200 ms") and test it.

## Security (always, from day one)

- Validate every input at the boundary: type, range, length, format. Reject; don't "fix".
- Parameterized queries only. Never build SQL, shell commands or paths from user input.
- Secrets come from the environment or a secret manager, never from code or git. landspec's
  hooks refuse them at commit and push.
- Least privilege everywhere: IAM roles allow only what the code calls, security groups open
  only the ports needed, containers run as non-root on minimal images.
- Logs are structured (JSON) and never contain secrets, tokens or personal data.
- HTTPS for anything real. TLS 1.2 or newer.

## When you add a database

- **Migrations** are SQL files named by timestamp (`20261104T1530-add-orders.sql`), forward
  only, run by an explicit command. Never on app startup, where two instances would race. Name
  the target environment, and refuse production unless that's explicitly asked for.
- **Transactions are explicit:** the caller opens one and passes it to the functions that must
  share it. Writes that must happen together (an order and its audit row) go in the same one.
- **Money and counters** use `SERIALIZABLE` (or a row lock) with a bounded retry on
  serialization failures. Amounts are integers in the smallest unit (cents), never floats.
- **Queries are parameterized**, filter and paginate in SQL, and avoid N+1 (one query with a join
  or `IN`, not one query per row). A list endpoint caps its page size.
- **The health check pings the database** and returns 503 when it can't reach it, without
  exposing versions or connection counts.
- **Integration tests use a real database:** a container in CI and in `compose.yaml`, reset per
  test file, with a guard that refuses to run unless the environment is `test`.
- **Personal data:** store as little as the spec needs, and say where it lives (a table list or
  data map kept next to the code).
- **Logins:** one generic error for a wrong user or password, with the same response time for
  both, so nobody can find out which accounts exist. Passwords are hashed with Argon2id or
  bcrypt. Session tokens are stored hashed, never as plain text.

## Running it

- **Observable from the first deploy:** structured logs with a request ID, a health check, and
  the errors that matter. Add metrics and tracing (OpenTelemetry) when there is more than one
  service or a latency target to watch.
- **Fail gracefully.** Every outbound call has a timeout. Retries have backoff and a limit, and
  only retry what is safe to repeat (idempotent operations). Work that keeps failing goes
  somewhere visible (a dead-letter queue, a failures folder, a log line with the input), never
  silently dropped.

## Features that use AI (LLMs, models)

Most AI work is never validated (Esposito et al., 2025, a review of 46 studies). Don't be that
project:

- **An evaluation set before the feature:** fixed inputs with expected outputs or checks, run in
  CI like tests. A prompt or model change that lowers the score doesn't merge.
- **Version prompts and model IDs** in the code, as config, not in someone's dashboard.
- **Check outputs before acting on them:** schema-validate structured output, and treat model
  output as untrusted input (no SQL, shell or HTML from it unescaped).
- **A human approves consequential actions:** payments, deletions, messages sent on someone's
  behalf.
- **Log inputs and outputs only under a privacy rule:** no personal data or secrets, or a
  retention limit.

## Tests

A test is evidence that the code does what the spec says. A test that can't fail is worse than
none: it makes people trust the code.

- **Test behavior, not implementation.** Test through the public interface: an HTTP call in
  memory, a module function, the real program for end-to-end checks. Refactors shouldn't break
  tests.
- **Every task's *Completed when* is a test** or a command that proves it.
- **Both sides of every limit:** the last allowed value and the first refused one (exactly 64 KiB
  accepted, one byte more refused; port 1 and 65535 valid, 0 and 65536 not). Then the error path,
  and that nothing extra leaks out (compare whole bodies, not one field).
- **Expected values are literals in the test.** A test that imports the limit, the price or the
  list from the code under test moves with the bug and can never catch it.
- **Never weaken a test to get green.** No loosened assertion, no "200 or 405", no retry or
  skip. Fix the code, or change the spec first. A changed test needs a written reason in the PR
  (landspec refuses the PR without a `## Test changes` section).
- **Fast and deterministic:** no fixed sleeps (poll with a deadline), no real network, no shared
  state. Time-based code is tested with a paused or injected clock.
- **Three layers, mostly the first:** unit tests for logic; integration tests through the real
  interface (in-memory HTTP, a real database in CI when there is one); a few end-to-end tests of
  the real program (start it, call it over a real port, stop it with SIGTERM).
- **Prove the tests work with mutation testing.** cargo-mutants (Rust), mutmut (Python) or
  Stryker (JS/TS) changes the code (`>` to `>=`, a deleted line) and reruns the tests. Every
  change that no test notices is a behavior nobody checks. Kill it with a test, or write down why
  it changes nothing observable.

## Working in parallel

- **One branch and one PR per feature; tasks in parallel on it.** `/landspec:implement` builds
  every task whose dependencies are done at the same time, each on its own local task ref in its
  own copy, and lands each one on the feature branch once its review passes. Tasks marked `[P]`
  don't touch the same files, so they rarely conflict when they land. landspec's analysis and
  security reports live in the shared git directory, so every copy sees them.
- **Develop in a container when the team is more than one person:** a `.devcontainer/` gives
  everyone the same toolchain, and `compose.yaml` runs the production image with production's
  restrictions.

## Infrastructure

- **Everything as code** (Terraform), remote state with locking, one state per environment.
- Managed services over self-run ones: containers on a managed runtime, a managed database.
- Immutable images tagged by commit SHA. Deployments roll back on their own when unhealthy.
- CI/CD with short-lived credentials (OIDC), every third-party action pinned to a commit SHA.

## Starter checklist

`/landspec:new` writes **no application code**. Every line of behavior arrives through a spec,
like any feature. It does two things:

### 1. Project setup (what `/landspec:new` does)

The tooling, so the first spec starts on a green, safe base:
- **the stack's own project tool** (`cargo init`, `uv init --app --package`, `pnpm init`, `go mod
  init`) with the current stable or LTS version pinned (`rust-toolchain.toml`,
  `.python-version`, `.node-version`, `go.mod`). Pick the newest version that the key tools and
  libraries already support, not a release from the last few weeks: new language versions take
  time to get wheels, binaries and linter support. Remove the tool's placeholder code ("Hello
  from …") down to an empty entry point, and say in the README that features come with specs;
- **dev tools, current and idiomatic:** formatter, linter (warnings are errors), type checker,
  test runner, mutation-testing tool, dependency audit; each one configured, none of them
  replaced by an outdated habit (see `references.yaml`);
- **supply chain:** a committed lockfile installed `--locked`/`--frozen-lockfile`, a release
  cooldown where the package manager supports one, and no dependency that isn't needed yet;
- **CI** (`.github/workflows/ci.yml`): format, lint, types, tests, the audit, a job timeout,
  stale runs cancelled, every action pinned to a commit SHA, and a check that the tests left no
  files behind;
- **a `.devcontainer/`** with a pinned image and no unverified third-party features;
- **for a service only:** a multi-stage Dockerfile on a minimal non-root base with an explicit
  `USER`, and a `compose.yaml` binding to `127.0.0.1` with `read_only`, `cap_drop: [ALL]` and
  `no-new-privileges`;
- **a README** with a **Check** section: read-only commands that exit, the same ones CI runs;
- **`.gitignore`** for the stack, `.env` and every tool's output folder.

The checks run once, on the empty project, so the setup itself is proven to work.

### 2. The foundation spec (suggested as the first `/speckit-specify`)

What every project needs before its first real feature. It is written as a spec, so it gets
tasks, reviewed tasks, its PR and tests like everything else:
- **config** from the environment, validated once at startup (bad config exits 1 and names the
  variable); graceful shutdown on SIGTERM and Ctrl-C;
- **one error type** with a single mapping to the outside: client errors keep their message;
  anything else is logged in full under a fresh `error_id`, and the caller gets only "internal
  error" plus that ID;
- **structured logs** (JSON): a request ID taken from the caller's `x-request-id` or generated,
  then echoed back; one line per request at info; credentials and personal data redacted;
- **limits:** a body size limit (413), a handler timeout that answers 503 (not 408, which clients
  may retry), and timeouts on every outbound call;
- **a health check** (for a service);
- **tests at three levels** (see Tests): logic, the interface in memory, and the real program end
  to end, with every surviving mutant killed or explained;
- **infrastructure, only if the user deploys now:** remote state with locking, one name tying
  resources, registry and state key together, deploys through OIDC (no stored keys), and a
  reviewed plan applied as is.

**Pitfalls found the hard way** (check `references.yaml` for the current details):
- **Rust (axum/tower):** layers apply only to routes added before `.layer()`. `TraceLayer` logs
  requests at DEBUG unless told otherwise. Deny `unwrap_used`, `panic`, `todo` and `dbg_macro`
  outside tests, and allow them in tests through `clippy.toml`. Turn on `overflow-checks` in
  release.
- **Node:** `Number()` accepts `"1e3"`, `" 80"` and `"0x50"`, so validate digits with a regex.
  Fastify's `requestTimeout` only covers *receiving* the request; the handler needs its own
  timeout. Node runs `.ts` directly, so there are no enums or parameter properties
  (`erasableSyntaxOnly`). Corepack no longer ships with Node.
- **Python (uv):** `pyproject.toml` with `uv_build`, `[dependency-groups]`, and `uv.lock`; never
  `requirements.txt`. `exclude-newer = "7 days"` will refuse a release that's days old: that's
  the cooldown working, so widen the version range, don't drop the cooldown.
  `os.replace`/`Path.replace` silently overwrite, so move with a hard link or an `O_EXCL`
  create. A folder watcher must handle renamed-in files (that's how downloads finish), skip
  partial and empty files, and never die on one bad file.
- **Browser automation:** sync Playwright, no sleeps, and traces only on failure (they contain
  page data). PyAutoGUI is X11-only, so put it behind an interface and refuse Wayland.
- **Mutation testing:** a test that imports the limit it checks can never catch a wrong limit.
  StrykerJS needs `tsconfigFile` pointed away from `tsconfig.json` until TypeScript 7.1.
- **Docker:** distroless `:nonroot` already runs as 65532, but scanners only trust an explicit
  `USER`.
- **Terraform on AWS:** ECR immutable tags mean a re-run must reuse the image, not push again.
  Planning with S3 native locking needs write access to the `.tflock` key.
