---
name: security
description: "Full security audit of the project: scanners, a manual OWASP Top 10 and CWE Top 25 sweep, business-logic and race-condition flaws, each finding verified, then tracked and fixed safely. Use for /landspec:security, before a release, or when the user asks whether the software is secure."
argument-hint: "[quick|full|deep|<report>]"
---

# Security audit

This is the full audit, on demand. `/landspec:implement` does not run it for a feature: there, one
**security review** of the feature's diff (`review.md`, "A security review") runs in the end check,
before the PR is ready, and stands in for the audit at the release. Run this skill when the whole
repository is the question: before a launch, after adopting a codebase, on a schedule.

**Modes**
- `quick`: only what this branch changed. Scanners on the changed files, `/security-review`,
  the sweep limited to the touched code.
- `full` (default): the whole repository, every phase below.
- `deep`: `full`, plus one read-only subagent per sweep group running in parallel, and a fresh
  subagent trying to disprove each high or critical finding.
- `<report>` (a path): a report the audit of `/landspec:implement` already wrote, for a held release.
  Read it, show its summary as step 6 says, then step 7. Skip steps 1 to 5. A held finding that a
  fresh verification (step 5) disproves gets the reason written in the report, and the new count of
  confirmed critical or high recorded with `implement.sh audit-record <commit> <report> <n>` (the
  commit is the report's): with 0, the next `/landspec:implement` goes on with the release.
  A report with a `Security:` count line is the end check's security review (the record
  `review.sh record --security` printed as `REPORT=`), held on a public repository: fix its confirmed
  critical and high findings on the feature branch, each with its regression test, and commit them
  with a neutral message; the next `/landspec:implement` checks the new head and reviews it again.
  One that a fresh verification disproves is settled by the confirming security review of
  `review.md` ("No second agent by default"), recorded with `review.sh record --security`, never by
  editing the record.
- **Unattended** (the audit `/landspec:implement` runs before a release when no security review is
  recorded for the feature, `AUDIT=needed`): `full`, steps 1 to 6 only, on
  the checkout it names. Ask nothing; change no file in the working tree (the scanners' reports in
  `REPORT_DIR`, inside `.git`, are fine), commit nothing, open no issue, advisory or PR,
  post nothing. Write the report where the prompt says (not `REPORT_DIR`), and end with one line
  `HOLD=<n>`: the number of findings marked `confirmed` with severity critical or high. Step 4 takes
  the `/code-review high` and `/security-review` output from the files the prompt names (the main
  session ran them); one the prompt says was not available is named in the report's coverage, as a
  missing scanner is. Step 7 is for the developer, through `/landspec:security <report>`.

**Rules for the whole audit**
- Read code; don't guess. Every finding cites `file:line` and a concrete way to exploit or
  trigger it. "Could be risky" with no path to harm is not a finding.
- Never print a secret's value. Redact it.
- Change nothing until the report is done and the user chooses what to fix.

## 1. Map the attack surface

Write a short map before hunting:
- **Entry points:** HTTP routes and their auth requirement, CLI commands, queue and webhook
  consumers, scheduled jobs, file uploads, and LLM prompts that take user text.
- **Trust boundaries:** where data crosses from the internet, users, third parties or other
  services into the code.
- **Identity:** how authentication works (sessions, JWT, OAuth, API keys), and where
  authorization is enforced: per route, per record, per role.
- **Assets:** stored data (PII, money, credentials), secrets and where they are loaded from,
  and outbound calls (payments, email, cloud APIs).
- **Infrastructure:** Dockerfiles, IaC, CI/CD workflows, the deployed environments.

## 2. Run the scanners

Run `bash .specify/extensions/landspec/scripts/security-scan.sh` (add `--changed` in `quick` mode).
- For each `missing` tool, list its install line once at the end. Missing scanners mean less
  coverage, so say exactly which categories went unscanned.
- Read every report in `REPORT_DIR`. For each scanner finding decide: **reachable** and
  exploitable here, or a **false positive** (and why: dead code, test fixture, input never
  user-controlled). Never drop a finding without that reason.
- Dependency findings: check whether the vulnerable function is actually used, and give the
  fixed version.

## 3. Sweep by category

Go through the code against each group. Use the map from step 1 to know where to look.

| Group | Look for |
|---|---|
| **Access control** (A01, CWE-862/863/639) | routes missing auth; records fetched by ID without an owner check (IDOR); role checks only on the client; privilege escalation through mass assignment; SSRF (user-controlled URLs fetched by the server); path traversal (CWE-22) |
| **Injection** (A05, CWE-79/89/78/94/77) | SQL built from strings; command execution with user input; template, LDAP, NoSQL and header injection; XSS (unescaped output, `dangerouslySetInnerHTML`, `v-html`); log injection |
| **Authentication & sessions** (A07) | weak or missing password hashing (use argon2/bcrypt/scrypt); JWT `alg` confusion, missing expiry or signature checks; session fixation; tokens in URLs or logs; missing rate limits on login, reset and OTP |
| **Cryptography & secrets** (A04, CWE-798) | hardcoded credentials; weak algorithms (MD5/SHA1 for passwords, ECB, static IVs); `Math.random()` for tokens; TLS verification turned off; secrets in the client bundle or in public env vars |
| **Insecure design & business logic** (A06) | money as floats; negative or zero amounts and quantities; steps of a flow that can be skipped or replayed; coupons and limits applied twice; trust in client-sent prices, totals or roles |
| **Concurrency & integrity** (CWE-362/367) | read-then-write races on balances, stock and quotas (double spend); missing unique constraints; non-idempotent webhooks or payments; TOCTOU on files |
| **Input & resource handling** (A10, CWE-20/400/770/1333) | unbounded body, upload, page size or recursion; regexes vulnerable to ReDoS; zip and XML bombs (XXE, CWE-611); unsafe deserialization (CWE-502); unrestricted upload types (CWE-434) |
| **Errors & logging** (A09, A10) | stack traces or internals in responses; failing open (an exception leading to "allowed"); swallowed errors on security checks; PII or tokens in logs; no audit trail for sensitive actions |
| **Configuration** (A02) | CORS `*` with credentials; missing security headers; CSRF (CWE-352) on cookie-authenticated state changes; debug mode or default credentials; public buckets; overly broad IAM; containers running as root |
| **Supply chain & CI** (A03, A08) | unpinned actions; `pull_request_target` running untrusted code; secrets exposed to forks; script injection via `${{ github.event.* }}`; install scripts and typosquatted packages; lockfiles not committed |
| **AI features** (if any) | prompt injection reaching tools, actions or data; model output rendered as HTML or run as code; secrets or PII sent in prompts |

In `deep` mode, start one read-only subagent per group, in parallel, each given the attack
surface map and its group's checklist. Then merge their findings and remove duplicates.

## 4. Logic bugs

Run `/code-review high` on the current branch, or on the most recent changes in `full` mode. It
catches correctness bugs that become outages: wrong conditions, unhandled errors, broken edge
cases. On a branch with changes, also run `/security-review`.

## 5. Verify every high and critical finding

For each one, try to **disprove** it: find the middleware, validation, constraint or framework
default that already stops it. In `deep` mode a fresh subagent does this without seeing your
reasoning. Keep a finding only if the exploit path survives. Mark it `confirmed`, or
`plausible` (the path exists but depends on deployment or config you can't see).

## 6. Report

Write `REPORT_DIR/report.md`, which stays inside `.git` and is never committed. Then show the
summary to the user:

- one line on overall risk, then the counts by severity;
- a table with severity, category, `file:line`, a one-line title, and `confirmed` or `plausible`;
- for each finding, most severe first:
  - **What:** the code and why it's exploitable;
  - **Exploit:** concrete steps or a request;
  - **Impact:** what an attacker gets;
  - **Fix:** the change;
  - **Test:** the regression test that proves the fix;
- coverage: which scanners ran, which were missing, and what was out of scope.

Severity: **critical** = remote, unauthenticated, data or money at stake; **high** = an
authenticated user can harm others, or one step from critical; **medium** = needs unusual
conditions; **low** = hardening.

## 7. Track and fix, without disclosing

- **Private repository:** offer one issue per confirmed critical or high finding, labelled
  `security` and with no exploit details in the title. Each one is then fixed through the normal
  flow (`/speckit-implement` or a small task), always with its regression test.
- **Public repository:** never open public issues for vulnerabilities. Offer a private draft
  security advisory instead, or keep the report local. First look for one with the same summary:
  ```bash
  gh api --paginate "repos/{owner}/{repo}/security-advisories?per_page=100" \
    --jq '.[] | select(.summary == "<summary>") | .html_url'
  ```
  If it prints a link, show that link and stop: the advisory already exists. Otherwise send the
  JSON body GitHub accepts (`severity` is `critical`, `high`, `medium` or `low`; `ecosystem` is the
  package's registry, such as `npm` or `pip`, or `other` when none fits):
  ```bash
  gh api -X POST "repos/{owner}/{repo}/security-advisories" --input - <<'EOF'
  {
    "summary": "<one line, no exploit detail>",
    "description": "<what is affected, the impact and the fix>",
    "severity": "high",
    "vulnerabilities": [{ "package": { "ecosystem": "other", "name": "<package>" } }]
  }
  EOF
  ```
- **A real secret was found:** say first that it must be **rotated** now, because removing it
  from git does not un-leak it. Then help remove it from the code.
- Offer to fix the lower-severity items as one hardening task.
