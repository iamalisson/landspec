# Data model: Bookmarks

## Bookmark

- `url`: required.
- `title`: required, at most 200 characters.
- `created_at`: the date the bookmark was first saved.
- states: `saved` → `deleted`; an update for a deleted bookmark saves it again.
