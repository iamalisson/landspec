# Plan review fixture: one planted defect per pass

A small feature folder (three FRs, two SCs, three tasks) for the plan review. A review of it that
says `ready` missed something: each pass below has one defect its table must show as failing.
`tests/review.test.sh` records reports on a copy of this folder.

| Pass | Planted defect | The failing row |
|---|---|---|
| size | T003 adds a tag index, a sync queue, an endpoint and a web page: four behaviors, well over 400 lines | `T003`: `BREAKS: <why>` |
| requirements | FR-003 (a delete is final) is proven by no task's *Completed when* | `FR-003`: `MISSING` |
| rules | the title's limit is 200 characters in `data-model.md` and 100 in `contracts/api.md` | `DIFFERENT: 200 vs 100` |
| claims | `plan.md` says `save()` is unchanged for its callers, while T002 changes what it returns | `FALSE` |
| inputs | T001's test calls `tag_index()`, which only T003, a later task, adds | `MISSING` |
| guards | the `lint-docs` CI job covers `docs/`, which T002 edits, and no task handles it | `MISSING` |
| rollout | T002 backfills `created_at` with today's date on its first run, a value that cannot be corrected later (SC-002) | `BREAKS: <how>` |
| orderings | `data-model.md` lets an update for a deleted bookmark save it again: a late update undoes a delete (FR-003) | `BREAKS: <how>` |
