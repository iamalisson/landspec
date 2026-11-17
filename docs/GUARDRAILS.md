# Guardrails

The agent's checklist when someone starts or shapes a project. People don't skip tests, logging
or error handling on purpose; they skip them because nobody told them. The agent's job is to
notice when something important is missing or risky, say so in one plain sentence with the
reason, and recommend the fix. The decision stays with the person.

Every rule here is backed by evidence (sources at the end). Over-engineering counts as a mistake
too: "start simple, well done and secure" (`GUIDELINES.md`).

## 1. Ask before choosing (only what the person hasn't already said)

1. **Who uses it:** just you, a team, or the public? Roughly how many in the first 6 months?
2. **Personal data:** names, emails, documents, health data, children's data? Which law
   applies (GDPR, LGPD…)?
3. **Money or credentials:** payments, accounts, logins?
4. **Load:** requests or jobs per second, and latency needs. Assume small unless told otherwise.
5. **People:** team size and experience. Who fixes it when it breaks?
6. **Where it runs:** a laptop, a PaaS, AWS, a VM? What's the budget?
7. **Data loss:** how much can you afford to lose (minutes, a day), and how fast must it come back?
8. **Accounts and tenants:** is there auth? Does one customer's data need to be walled off from
   another's?
9. **AI features:** does it call an LLM? What can the model do: read only, or also write, send
   or pay?
10. **Lifespan:** a throwaway prototype or a product?

The answers decide the landspec level: money, personal data or many users → `full`; a
throwaway → `lite`; otherwise `standard`.

## 2. Stop and confirm

Don't proceed silently. Explain the risk in one or two sentences, offer the fix, and continue
only on an explicit "yes, I accept this". Record the decision in `plan.md` or
`docs/decisions/`.

| If you see | Why it matters | Offer instead |
|---|---|---|
| Secrets in a tracked file, or `.env` not git-ignored | 23.8M secrets leaked on public GitHub in 2024; 70% of those leaked in 2022 still worked [GG] | environment variables or a secret manager, `.env.example`, gitleaks (landspec's hooks do this) |
| Passwords stored in plain text, or hashed with MD5/SHA-1/SHA-256, or a homemade login/JWT/crypto scheme | OWASP A04/A07:2025 [OW] | Argon2id or bcrypt through a maintained library, or an identity provider |
| SQL, shell or HTML built from input by string concatenation; `eval`; `shell=True` | XSS, SQL injection, command and code injection are 4 of the CWE Top 25 [CWE] | parameterized queries, argument arrays, auto-escaping templates |
| Personal data, money or multiple tenants with no authorization plan ("auth later") | Broken access control is OWASP #1 [OW]; missing authorization is CWE #4 [CWE] | deny by default, an ownership check on every object, a test that one tenant can't read another's data |
| A production database with no backups, or backups never restored | GitLab 2017: backups silently failing, 6 hours of data lost for ~5,000 projects [GL] | automated backups, an alert on failure, one restore drill |
| Debug mode, `CORS *`, default credentials or public storage in production | Misconfiguration is OWASP #2 [OW] | secure production defaults; debug only locally |
| An LLM that can write, delete, send or pay, or whose output runs as code/SQL/shell | OWASP LLM01 prompt injection, LLM06 excessive agency [LLM] | read-only tools, validated output, human approval for consequential actions |
| An AI agent working in AWS with long-lived access keys or admin rights | AWS: use temporary credentials and least privilege, not long-term keys [IAMBP]; an agent's calls carry the caller's own permissions, so its role is the limit [MCP] | a role assumed from a short-lived sign-in (landspec ships `agent-role.yaml`), with no IAM write, read-only in prod |
| A package nobody can verify (few downloads, days old, or suggested by an AI) | AI assistants invent package names, at least 5.2% of suggestions for commercial models, 21.7% for open models [SP] | check it exists, is maintained and is widely used; prefer the standard library |
| Microservices, Kubernetes, event sourcing or a service mesh for a small team with no load yet | Prime Video cut costs by over 90% moving one system back to a monolith [PV]; "monolith first" [MF] | one deployable, modules by feature. This one is reversible: don't block, but require a stated reason and record it |

## 3. Recommend by default

Apply these unless the person says otherwise. Mention each in a short line so they learn why.

| Area | Smell | Default fix | Evidence |
|---|---|---|---|
| Errors | `except: pass`, `catch (e) {}`, `// TODO handle`, catch-all handlers | catch specific errors, add context, handle once at the edge, test the error path | 92% of catastrophic failures came from mishandled non-fatal errors; 58% were catchable by simple tests [YU]; OWASP A10:2025 [OW] |
| Limits | HTTP calls without timeouts, unbounded uploads, lists or retries | timeouts everywhere, capped retries with jittered backoff, body and page-size limits | CWE-770 [CWE]; AWS Builders' Library [AWS] |
| Tests | no test command, no tests in CI | a test runner and a smoke test on day one, run in CI | 77% of failures in the same study were reproducible with a unit test [YU] |
| Flaky tests | sleeps, real network, shared databases in unit tests | hermetic tests with fakes at the boundary, plus a few integration tests | about 16% of Google's tests showed some flakiness [GT] |
| Tests that can't fail | an assertion that accepts two outcomes ("200 or 405"); expected values imported from the code under test; a test loosened, skipped or deleted to get green; only the happy path | both sides of every limit as literals, whole-body comparisons, the error path; mutation testing to prove each test fails when the code is wrong | the same study: most catastrophic failures were in error handling that simple tests would have caught [YU] |
| Plan not checked against the code | a task deletes something another task's test uses; a quickstart command that runs something else than the step claims; a migration with no named target | ground every task in the repo before review: search each symbol, list the existing tests and guards it trips, read each command | four such findings in a single spec PR during landspec's own testing |
| New file ignores its siblings | a migration that creates a table unconditionally in a repo whose other migrations guard with `has_table`, because environments are built by `create_all` and stamped; a test that only proves the fresh-database path | before writing a file of a kind that exists, read the newest one and keep its guards; make *Completed when* exercise the real upgrade path | a task PR passed `/code-review` and its own tests, then a second reviewer found it from the neighbouring migration (landspec's own use, Nov 2026) |
| Lockfile | no `Cargo.lock`, `pnpm-lock.yaml` or `uv.lock`; `*` or open ranges | commit the lockfile, install `--locked`/`--frozen-lockfile`, add a release cooldown | OWASP A03:2025 supply chain [OW]; 512,847 malicious packages in a year [SN] |
| Updates | no Dependabot or Renovate | automated update PRs, gated by tests and the security scan | exploited vulnerabilities were 20% of breach entry points [DBIR] |
| Dependencies | a package for a few lines of code | the standard library, or a few lines of your own | third parties were involved in 30% of breaches [DBIR] |
| Config | URLs or credentials in source; `if env == "prod"` all over | one config module reading the environment, validated at startup | Twelve-Factor III and X [12F] |
| Schema | hand-run `ALTER TABLE`, no migrations folder | a migration tool from the first table | [SRE] |
| Personal data | storing ID numbers or birth dates "just in case"; logging request bodies | collect less, encrypt sensitive fields, keep personal data out of logs | CWE-200 [CWE] |
| Observability | `print()` debugging only, no health check, nobody alerted | structured logs with a request ID, `/health`, one uptime alert | OWASP A09:2025 [OW] |
| Delivery | deploys by hand from a laptop, no rollback, "one big release at the end" | CI on every push, small PRs, one-command deploy that rolls back on its own | about 70% of outages come from changes to a live system [SRE]; Knight Capital lost $460M in 45 minutes to a bad deploy [SEC] |
| CI security | `uses: x@main`, `permissions: write-all`, `pull_request_target` | actions pinned to a SHA, read-only tokens, zizmor | OWASP A08:2025 [OW] |
| Premature scaling | Redis, a CDN or a queue before any traffic estimate | an index and a profiler first; write down the trigger for adding it | technical debt consumes ~23% of development time [BE] |
| AI cost and quality | no token limits, no rate limits, "we'll eyeball the quality" | hard budgets, an evaluation set in CI, logs with personal data redacted | OWASP LLM10 [LLM]; hidden technical debt in ML systems [SC] |
| AI-written code | merging generated code without review because it looks right | tests, review and scanners as gates, no matter who wrote the code | people with an AI assistant wrote less secure code in 4 of 5 tasks while feeling more confident [PE]; DORA 2024 links more AI adoption to lower delivery stability [DORA] |

## 4. How to say it

- **One sentence, the reason, the fix.** "There's no backup for the database. If it's lost,
  everything is gone. I'll add daily automated backups with an alert. OK?"
- **Teach, don't lecture.** Name the practice once so they can look it up. Then move on.
- **Respect a reasoned choice.** If they understand the risk and still decide otherwise, record
  it and continue. Section 2 needs an explicit yes; section 3 just needs no objection.
- **Never pile on.** At most three recommendations at a time, most severe first.

## Sources

- [OW] OWASP Top 10:2025: https://owasp.org/Top10/
- [CWE] CWE Top 25 (2025): https://cwe.mitre.org/top25/
- [LLM] OWASP Top 10 for LLM Applications 2025: https://genai.owasp.org/llm-top-10/
- [IAMBP] AWS IAM security best practices: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- [MCP] AWS Security Blog, Understanding IAM for managed AWS MCP servers: https://aws.amazon.com/blogs/security/understanding-iam-for-managed-aws-mcp-servers
- [YU] Yuan et al., "Simple Testing Can Prevent Most Critical Failures", OSDI 2014: https://www.usenix.org/conference/osdi14/technical-sessions/presentation/yuan
- [GG] GitGuardian, State of Secrets Sprawl 2025: https://blog.gitguardian.com/the-state-of-secrets-sprawl-2025/
- [SN] Sonatype, State of the Software Supply Chain 2024: https://www.sonatype.com/state-of-the-software-supply-chain/introduction
- [DBIR] Verizon Data Breach Investigations Report 2025: https://www.verizon.com/business/resources/reports/dbir/
- [SP] Spracklen et al., package hallucinations, USENIX Security 2025: https://arxiv.org/abs/2406.10279
- [PE] Perry et al., "Do Users Write More Insecure Code with AI Assistants?", CCS 2023: https://arxiv.org/abs/2211.03622
- [DORA] DORA 2024 report: https://dora.dev/research/2024/dora-report/
- [GL] GitLab database outage postmortem, 2017: https://about.gitlab.com/blog/2017/02/10/postmortem-of-database-outage-of-january-31/
- [PV] Prime Video monitoring service: https://www.primevideotech.com/video-streaming/scaling-up-the-prime-video-audio-video-monitoring-service-and-reducing-costs-by-90
- [MF] Fowler, MonolithFirst: https://martinfowler.com/bliki/MonolithFirst.html
- [SRE] Google, Site Reliability Engineering: https://sre.google/sre-book/introduction/
- [AWS] Timeouts, retries and backoff with jitter: https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/
- [GT] Flaky tests at Google, 2016: https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html
- [SEC] SEC order on Knight Capital, 2013: https://www.sec.gov/news/press-release/2013-222
- [12F] The Twelve-Factor App: https://12factor.net/
- [BE] Besker et al., technical debt cost, JSS 2019: https://research.chalmers.se/en/publication/511450
- [SC] Sculley et al., "Hidden Technical Debt in Machine Learning Systems", NeurIPS 2015: https://papers.nips.cc/paper/5656-hidden-technical-debt-in-machine-learning-systems
