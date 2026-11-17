# Implementation Plan: Bookmarks

## Summary

Bookmarks are stored by `lib/store.sh`; its `save()` is unchanged for its callers. Tags are
indexed by `tag_index()`. Deletes and updates arrive from the sync queue, in any order.

## Constitution Check

CI runs `tests/run.sh` and the `lint-docs` job on `docs/`.
