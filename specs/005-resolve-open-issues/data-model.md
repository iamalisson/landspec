# Data model: Resolve the open issues

Nothing new is stored. Three values change meaning.

## Task summary (derived, `lib.sh task_summary`)

Input: one task line. Output: its description without the trailing `(depends on …)` clause and
without the ` in <path>` part.

| Line | Summary |
|---|---|
| `- [ ] T007 [P] [US4] Show the class in \`a/b.py\` (depends on T004)` | `Show the class` |
| `- [ ] T007 Show the class (depends on T004, T005)` | `Show the class` |
| `- [ ] T007 Show the class` | `Show the class` |
| `- [ ] T007 Mostrar a turma, em a/b.py (depends on T004) — #13` | `Mostrar a turma, em a/b.py` |
| `- [ ] T007 Use (depends on X) as a label in docs` | unchanged: the clause is not at the end |

Used by: the issue title (and the duplicate lookup by title), the branch slug, the `next` text.

## Plan state (derived, `review.sh state()`)

`sha256` of `plan.md` followed by `tasks.md` with every trailing ` — #N` removed. Unchanged
definition; it is now also printed by `review.sh state --plan` and written by the reviewer into
its report as `Plan state: <64 hex>`. With a folder argument, `state --plan <dir>` hashes
`<dir>/plan.md` and `<dir>/tasks.md` and needs no active feature.

**Invariant (plan review):** the reviewer hashes and reads the same snapshot, in its own copy. It
copies `plan.md` and `tasks.md` out of `<checkout>/specs/NNN-*/` into a `mktemp -d` folder (reading
the checkout only: no git command there, no write), runs `review.sh state --plan <that folder>`
in its own copy, and reviews those copied files. So the recorded state is exactly the text read,
and nothing the reviewer runs needs the author's checkout.

Validation in `record --plan`: the report's last exact `Plan state:` line (optional bold, like
`Model:`), 64 lowercase hex; equal to the current `state()`.

## Settled release (derived, `bin/check-tools.sh`)

For each tool: the newest non-prerelease GitHub release published at least 21 days before the
run. "Behind" means that release is newer than the pin.
