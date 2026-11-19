---

description: "Task list template for feature implementation"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Every task ships its own tests, in the same task and the same PR as its code. They come from the task's *Completed when* and the spec's acceptance scenarios. There are no separate test-only tasks: a PR whose new tests fail can't pass CI or merge.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- A task that needs another one **landed** first says so on its line: `(depends on T003)`.
  landspec holds it until T003 has landed, instead of offering it with a caveat.
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions
- **Tests at the level the behavior demands**, named in *Completed when*: logic (parsing, rules,
  money) gets a unit test; a behavior through the interface (an endpoint, a query, a migration)
  gets an integration test against the real thing (in-memory HTTP, the database the project uses
  in CI); a user-visible flow gets one end-to-end test of the running program. A unit test alone
  never proves an endpoint or a migration. A task that changes what people see names its
  accessibility check: the contrast ratio of each new text and icon colour against its background
  (text at least 4.5:1, large text and icons 3:1), focus visible on each control, an accessible
  name on each control and image.
- **Every task names its failure path in *Completed when*.** What the caller gets when it fails
  (a status and an error code, never internals), what is logged (one structured line with the
  request ID, no personal data or secrets), and who is refused (the wrong user, bad input, a
  replay, a missing dependency), each as a test. Error handling, logging and the refused cases are
  part of the task that adds the behavior, never a task of their own done last.
- **A task is a vertical slice, not a layer.** It is the smallest change that is reviewable,
  mergeable and revertible on its own, with a result someone can observe (a request that answers,
  a command that works, a rule that refuses). The layers of one behavior (its model, migration,
  repository, endpoint, UI) are **one task**, never four: merged apart they leave dead code on the
  base branch and the later PR lands in an environment the earlier one changed. A task under
  about 30 lines joins its neighbor. A task whose diff, tests included, would pass about 400
  lines is split by behavior (a defect found per line drops sharply past that size). Generated
  files, lockfiles, and markup or data copied as is from an existing file do not count.
- **Every task is safe to reach production alone.** Others promote the base branch while the
  feature is half built, so no task makes an unfinished feature visible to users. A feature with
  more than one task that users can see ships dark: the first task that adds something visible (a
  screen, route, menu entry, endpoint other clients call) puts it behind a flag, off by default,
  and the **last task** turns the flag on, depending on every other task of the feature. A
  migration stays backward compatible with the code already in production (add, never rename or
  drop in the same release).
- Under each task, add these sub-bullets (the builder and the reviewer read them):
  - `  - Comes from: <FR-/SC-/story IDs or plan section>`
  - `  - Impact: <existing code, tests, docs, data files and guards this task must update, found by
    searching the repo for every symbol, table, file and route it adds, renames, removes or changes
    the behaviour of (its result, its failure, who it lets through), naming each caller and how it
    is affected>`
  - `  - Completed when: <a verifiable check: a command that passes, an output, a screenshot>`
- **Ground every task in the real code, not in memory.** Before writing a task, search the repo
  for what it touches. If a task removes or renames something, list every reference to it,
  including in tests and in the other tasks. Copy a test's expected values in as literals, never
  imported from the code under test, or the test moves with the bug. Every input a task reads (a
  file, data, a URL) is on the base branch, in the spec folder, or written in the task: a file
  that exists only untracked in your tree is missing for whoever starts the task from a clean
  clone. A command in *Completed when* runs from any clone (`gh --repo <owner>/<repo>`, paths from
  the repository root). A step that writes data
  (migrations, scripts) names its target environment and how it refuses production.
- **A new file of a kind the repo already has** (a migration, a workflow, an endpoint, a model)
  names the newest existing one in *Impact* as the pattern to follow, guards included (for a
  migration: `has_table`, a seed that skips rows already there). Its *Completed when* exercises
  the path it runs on in reality, not only a fresh state: a migration is also upgraded from the
  previous head on a database that already has the model's tables.

Example:

```text
- [ ] T005 [P] [US1] Validate the signup email in src/auth/validate.py
  - Comes from: FR-002
  - Impact: `signup()` in src/auth/routes.py calls it; tests/auth/test_signup.py expects the old
    message "invalid email" and must be updated in this task
  - Completed when: `pytest tests/auth/test_validate.py` passes, including empty and malformed emails
```

## Path Conventions

- **Single project**: `src/`, `tests/` at repository root
- **Web app**: `backend/src/`, `frontend/src/`
- **Mobile**: `api/src/`, `ios/src/` or `android/src/`
- Paths shown below assume single project - adjust based on plan.md structure

<!--
  ============================================================================
  IMPORTANT: The tasks below are SAMPLE TASKS for illustration purposes only.

  The /speckit-tasks command MUST replace these with actual tasks based on:
  - User stories from spec.md (with their priorities P1, P2, P3...)
  - Feature requirements from plan.md
  - Entities from data-model.md
  - Endpoints from contracts/

  Tasks MUST be organized by user story so each story can be:
  - Implemented independently
  - Tested independently
  - Delivered as an MVP increment

  DO NOT keep these sample tasks in the generated tasks.md file.
  ============================================================================
-->

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [ ] T001 Create project structure per implementation plan
- [ ] T002 Initialize [language] project with [framework] dependencies
- [ ] T003 [P] Configure linting and formatting tools

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

Only what no story can start without, and still as slices with an observable result (adjust
based on your project; in an existing project most of this already exists):

- [ ] T004 Create the `orders` table and model with a migration that is safe on an existing database, in migrations/ and src/orders/model.py
  - Completed when: the migration upgrades on an empty database and on one built from the models; `pytest tests/orders/test_model.py` passes
- [ ] T005 Require a signed-in user on `/orders/*` in src/auth/require_user.py
  - Completed when: an anonymous request gets 401 with code `auth_required` and one log line with the request ID; a signed-in one passes

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - [Title] (Priority: P1) 🎯 MVP

**Goal**: [Brief description of what this story delivers]

**Independent Test**: [How to verify this story works on its own]

### Implementation for User Story 1

- [ ] T012 [US1] Create an order via `POST /orders` (validation, persistence, response) in src/orders/create.py
  - Comes from: FR-001, US1 scenarios 1-3
  - Impact: `routes.py` registers it; `tests/orders/test_create.py` is new; newest sibling endpoint `src/orders/cancel.py` (same auth and error shape)
  - Completed when: `pytest tests/orders/test_create.py` passes: a valid order answers 201 with its id; an empty cart answers 422 with code `empty_cart`; another user's address answers 403; a database failure answers 500 with an `error_id` that is also in the one log line, which carries the request ID and no personal data
- [ ] T013 [P] [US1] List a user's orders via `GET /orders` in src/orders/list.py
  - Completed when: `pytest tests/orders/test_list.py` passes: only the caller's orders, newest first; user A never sees user B's; an unknown `status` filter answers 422

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - [Title] (Priority: P2)

**Goal**: [Brief description of what this story delivers]

**Independent Test**: [How to verify this story works on its own]

### Implementation for User Story 2

- [ ] T020 [US2] Cancel an order via `POST /orders/{id}/cancel` in src/orders/cancel.py
  - Completed when: `pytest tests/orders/test_cancel.py` passes: a pending order becomes cancelled once (two simultaneous cancels produce one refund); a shipped one answers 409 with code `already_shipped`; another user's order answers 404; every refusal is one log line with the request ID

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - [Title] (Priority: P3)

**Goal**: [Brief description of what this story delivers]

**Independent Test**: [How to verify this story works on its own]

### Implementation for User Story 3

- [ ] T026 [US3] Email the receipt when an order is paid, in src/orders/receipt.py
  - Completed when: `pytest tests/orders/test_receipt.py` passes with the mail provider faked: one email per paid order, none on retry; a provider failure is logged with the request ID and retried later, and the order stays paid

**Checkpoint**: All user stories should now be independently functional

---

[Add more user story phases as needed, following the same pattern]

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] TXXX [P] Documentation updates in docs/
- [ ] TXXX Run quickstart.md validation

(No "error handling", "logging", "security hardening" or "cleanup" tasks: each task already ships
its failure path, its logs and its refused cases, and leaves the code clean.)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - May integrate with US1 but should be independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - May integrate with US1/US2 but should be independently testable

### Within Each User Story

- Each task includes the tests that prove its *Completed when*
- Models before services
- Services before endpoints
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Once Foundational phase completes, all user stories can start in parallel (if team capacity allows)
- Models within a story marked [P] can run in parallel
- Different user stories can be worked on in parallel by different team members

---

## Parallel Example: User Story 1

```bash
# Launch all models for User Story 1 together:
Task: "Create [Entity1] model in src/models/[entity1].py"
Task: "Create [Entity2] model in src/models/[entity2].py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3
3. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
