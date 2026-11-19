---
name: speckit-landspec-analyzed
description: Record that analysis ran on the current tasks
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: iamalisson
  source: landspec:commands/analyzed.md
---

# Record the analysis (after `/speckit-analyze`)

1. If the analysis report above has **CRITICAL** findings, say they must be fixed first, and stop.
   Do not record anything.
2. Otherwise save the analysis report as it came (from its `## Specification Analysis Report`
   heading through its Coverage Summary Table and the rest) to a file outside the repository
   (`mktemp`), and record it: `bash .specify/extensions/landspec/scripts/analyzed.sh <file>`. It refuses
   a file that is not that report; never write one yourself to get past it. This lets level `full`
   start tasks. If `tasks.md` changes later, the analysis has to be run again. If the analysis
   changed `tasks.md` or `plan.md`, run the plan review again (`/speckit-landspec-review`) before the
   next step: `pr.sh spec` stops on a stale one.
3. On level `full` (`level:` in `.specify/extensions/landspec/landspec-config.yml`), open the spec PR now:
   `bash .specify/extensions/landspec/scripts/pr.sh spec "<title>"` (a Conventional Commit title,
   `docs(specs): <what this run adds or changes>`), and show its URL.
