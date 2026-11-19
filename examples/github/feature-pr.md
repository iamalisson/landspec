<!-- PR #20 "feat(products): price search", feat/001-price-search → develop. Opened as a draft by /landspec:implement (pr.sh feature) after T001 landed; marked ready (pr.sh feature --ready) after the end check. -->
Shoppers filter the product list by a maximum price: `searchByMaxPrice()` with an index on
`products(price)`, `GET /products?maxPrice=` with input validation, and a "max price" field on the
product list.

## Evidence

tests 31/31 · lint clean · scanners on the whole feature diff: no findings · mutants: 0 survivors ·
10,000 rows answered in 41 ms (SC-001)

<details>
<summary>Test output</summary>

```
✓ search > returns products at or below the max, cheapest first
✓ search > returns nothing on an empty catalog
✓ search > keeps a stable order for equal prices
✓ search > 10,000 products under 200 ms (41 ms)
✓ routes > GET /products?maxPrice=15 → 200, sorted
✓ routes > maxPrice=-1 and maxPrice=abc → 400
✓ ProductList > shows only matching products, and the message on bad input
Test Files  5 passed (5) · Tests  31 passed (31)
```

</details>

<details>
<summary>Security scan</summary>

Ran gitleaks, osv-scanner and semgrep on the feature diff: 0 findings.
`/security-review`: the query is parameterized, so there is no injection path.

</details>

## Tasks

| Task | Summary | State | Landing commit | Review |
|---|---|---|---|---|
| T001 | Add the price query and its index in `src/products/search.ts` | done | 3f2a9c1 | ready (patch id 8c41d0e2b7a5) |
| T002 | Add `GET /products?maxPrice=` with input validation in `src/products/routes.ts` (depends on T001) | done | 9b07e4d | ready (patch id e12f6a93c0d4) |
| T003 | Add the "max price" field to the product list in `src/web/ProductList.tsx` | done | 5d6e1a8 | ready (patch id 47b9c2e1f3a6) |

## Low findings

- T001: the index name `idx_products_price` differs from the `<table>_<column>_idx` style of the two previous migrations

## End check

Head: 7c3d2b9 (round 1), tests: green
Assessment: ready

- met: FR-001 — `searchByMaxPrice()` returns products at or below the max, cheapest first (`tests/search.test.ts`)
- met: FR-002 — `-1` and `abc` get HTTP 400 (`tests/routes.test.ts`)
- met: FR-003 — the field shows the results and the error message (`tests/ProductList.test.tsx`)
- met: SC-001 — 10,000 products answered in 41 ms
