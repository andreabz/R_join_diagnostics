# R Join Diagnostics

A small `data.table`-based utility for auditing joins in R scripts and automated reports.

## Features

- Supports left, inner, and full joins.
- Requires an explicit expected relationship: `one-to-one`, `many-to-one`, `one-to-many`, or `many-to-many`.
- Validates key columns, key types, missing key values, and uniqueness constraints before joining.
- Reports unmatched keys and row replication diagnostics.
- Returns a structured audit object with `PASS`, `WARN`, or `FAIL` status.
- Keeps caller-owned input tables unchanged.
- Uses `data.table`; no tidyverse dependencies.

## Installation

```r
install.packages("data.table")
```

Install `testthat` to run the unit tests:

```r
install.packages("testthat")
```

## Quick start

```r
library(data.table)
source("join_audit.R")

x <- data.table(id = c(1L, 2L, 3L), amount = c(100, 200, 300))
y <- data.table(id = c(1L, 2L), category = c("A", "B"))

audit <- join_checked(
  x, y,
  by = "id",
  type = "left",
  relationship = "many-to-one"
)

audit$status
audit$report
audit$x_unmatched

# Stop the pipeline if the audit status is FAIL.
assert_join(audit)

result <- audit$result
```

## Audit statuses

- `PASS`: the join satisfies the declared relationship and no unmatched keys were found.
- `WARN`: the join satisfies the declared relationship, but one or more keys have no match.
- `FAIL`: pre-join validation or a post-join invariant failed. A pre-validation failure prevents the join from running.

Unmatched keys are diagnostic only; no threshold is applied by default. Missing key values are rejected. No automatic key normalization, coercion, or deduplication is performed.

## Run the unit tests

From the repository root:

```r
testthat::test_file("test-join-audit.R")
```

## Current scope and limitations

- Supports equi-joins on one or more named columns.
- Does not support update joins, rolling joins, non-equi joins, or join expressions.
- Key classes and underlying R types must match exactly.
- Non-key columns with the same name are suffixed `.x` and `.y` by `merge()`.
- The first version is a sourceable utility, not yet a packaged R library.

## Continuous integration

GitHub Actions runs the unit tests on every push and pull request. See `.github/workflows/test.yml`.
