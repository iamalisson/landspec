# Tasks: Price search

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: User Story 1 - Search products by price (P1)

- [ ] T001 [US1] Add the price query and its index in `src/products/search.ts`
  - Comes from: FR-001, SC-001
  - Impact: new table index in `db/migrations/`; `tests/schema.test.ts` lists every index and needs the new one
  - Completed when: `pnpm test` passes for search, including an empty catalog and equal prices
- [ ] T002 [US1] Add `GET /products?maxPrice=` with input validation in `src/products/routes.ts` (depends on T001)
  - Comes from: FR-001, FR-002
  - Impact: registers a route in `src/app.ts`; the route list in `docs/api.md` gains `GET /products`
  - Completed when: the integration test gets 200 sorted results for `15` and 400 for `-1` and `abc`
- [ ] T003 [P] [US1] Add the "max price" field to the product list in `src/web/ProductList.tsx`
  - Comes from: FR-003
  - Impact: `src/web/ProductList.tsx` only; no existing test covers this component yet
  - Completed when: the component test shows only matching products and the error message on bad input
