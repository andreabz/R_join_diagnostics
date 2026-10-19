# R Join Diagnostics

A small `data.table`-based utility for auditing joins in R scripts and automated reports.

## Features

- Supports left, inner, and full joins.
- Requires an explicit expected relationship: `one-to-one`, `many-to-one`, `one-to-many`, or `many-to-many`.
- Validates key columns, key types, missing key values, and uniqueness constraints before joining.
- Reports unmatched rows, key-frequency diagnostics, row loss by join type, and row replication.
- Supports composite keys and handles empty tables explicitly.
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

- `PASS`: no contract violation exists and no unmatched rows trigger a warning under the join-specific rules.
- `WARN`: the join satisfies the declared relationship, but unmatched rows warrant review.
- `FAIL`: input validation, the declared relationship, or a join invariant is violated. A pre-validation failure prevents the join from running.

Warning rules depend on join type: for `left`, unmatched rows in `x` trigger `WARN`, while unmatched rows in `y` alone do not; for `inner` and `full`, unmatched rows on either side trigger `WARN`. Unmatched rows alone never trigger `FAIL`.

Unmatched rows are counted per input row, not per distinct key. Rows absent from the result are distinct from unmatched rows: a left join preserves unmatched rows from `x`, an inner join excludes unmatched rows, and a full join retains unmatched rows from both inputs. Replication diagnostics count original rows that occur more than once in the result, not additional copies. Missing key values are rejected. No automatic key normalization, coercion, or deduplication is performed.

The detailed functional contract is documented in [docs/functional-contract.md](docs/functional-contract.md).

## Run the unit tests

From the repository root:

```r
results <- testthat::test_file("test-join-audit.R")
summary <- as.data.frame(results)
if (any(summary$failed > 0L | summary$error)) quit(status = 1)
```

## Current scope and limitations

- Supports equi-joins on one or more named columns.
- Does not support update joins, rolling joins, non-equi joins, or join expressions.
- Key classes and underlying R types must match exactly.
- Non-key columns with the same name are suffixed `.x` and `.y` by `merge()`.
- The first version is a sourceable utility, not yet a packaged R library.

## Continuous integration

GitHub Actions runs the unit tests on every push and pull request. See `.github/workflows/test.yml`.

## License

This project is licensed under the GNU General Public License v3.0 only. See [LICENSE](LICENSE) for the full text.
