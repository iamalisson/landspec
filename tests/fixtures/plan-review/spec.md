# Feature Specification: Bookmarks

## User Scenarios & Testing

### User Story 1 - Save a bookmark (Priority: P1)

A user saves a page with a title and finds it again by tag.

**Acceptance Scenarios**:

1. **Given** a page, **When** the user saves it with a title, **Then** it is listed.
2. **Given** a saved bookmark, **When** the user deletes it, **Then** it is never listed again.

## Requirements

- **FR-001**: Users MUST be able to save a bookmark with a URL and a title.
- **FR-002**: Users MUST be able to list their bookmarks by tag.
- **FR-003**: Deleting a bookmark MUST remove it for good, whatever arrives after the delete.

## Success Criteria

- **SC-001**: A saved bookmark is listed within one second.
- **SC-002**: Every bookmark saved before this feature shows its real creation date.
