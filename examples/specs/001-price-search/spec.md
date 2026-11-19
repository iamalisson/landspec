# Feature Specification: Price search

**Feature Branch**: `feat/001-price-search` · **Status**: Approved

## User Scenarios

### User Story 1 - Search products by price (Priority: P1)

A shopper types a maximum price and sees only the products that cost that much or less,
cheapest first.

**Acceptance Scenarios**:

1. **Given** products at 5, 12 and 30, **When** the shopper searches up to 15, **Then** they see
   the 5 and the 12, in that order.
2. **Given** any catalog, **When** the shopper enters a negative or non-numeric price, **Then**
   they see "Enter a price of 0 or more" and no results.

## Requirements

- **FR-001**: The API MUST return the products priced at or below a given maximum, cheapest first.
- **FR-002**: The API MUST reject a maximum that is negative or not a number, with HTTP 400.
- **FR-003**: The product page MUST offer a "max price" field that shows the results.

## Success Criteria

- **SC-001**: A search over 10,000 products answers in under 200 ms.
