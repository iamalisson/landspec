# Tasks: Bookmarks

- [ ] T001 [US1] Save a bookmark in `lib/store.sh`
  - Completed when: `tests/store.test.sh` saves a bookmark and lists it by tag with `tag_index()`.
- [ ] T002 [US1] Return the new id from `save()`, document it in `docs/api.md`, and backfill `created_at` with today's date on the first run (depends on T001)
  - Completed when: `tests/store.test.sh` checks the id `save()` returns.
- [ ] T003 [US1] Add the tag index, the sync queue, the delete endpoint and the web page for bookmarks (depends on T002)
  - Completed when: `tests/sync.test.sh` lists bookmarks by tag after a sync.
