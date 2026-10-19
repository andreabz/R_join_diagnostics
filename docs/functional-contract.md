# Functional contract: R Join Diagnostics

## Purpose

`join_checked()` executes an equi-join and returns the result together with diagnostics. The audit status expresses whether the join satisfies its declared contract; diagnostics describe matching, row retention, and replication. A larger or smaller result than either input is not, by itself, evidence of an error.

## Supported join types

- `left`: retain every row from `x`; matching rows from `y` are joined, and unmatched rows from `y` do not appear.
- `inner`: retain only matching row pairs.
- `full`: retain every row from both inputs, including unmatched rows.

## Relationship constraints

| Relationship | Keys in `x` | Keys in `y` | Permitted replication |
|---|---|---|---|
| `one-to-one` | Unique | Unique | Neither input's rows may be replicated |
| `many-to-one` | May repeat | Unique | Rows from `y` may match multiple rows from `x`; rows from `x` may not be replicated |
| `one-to-many` | Unique | May repeat | Rows from `x` may be replicated by multiple matches in `y` |
| `many-to-many` | May repeat | May repeat | Replication from either input is permitted |

Uniqueness is evaluated on the complete combination of key columns. For composite keys, duplicate values in an individual key column do not violate uniqueness if the complete key combination is unique.

## Input validation and FAIL

The audit returns `FAIL` when any of the following applies:

- either input is not a `data.table`;
- `by` is missing, empty, contains missing/empty names, or contains duplicate names;
- a key column is absent from either input;
- corresponding key columns differ in class or underlying R type;
- at least one row has a missing value in any key column;
- observed key uniqueness contradicts the declared relationship;
- a post-join invariant is violated.

Key values are not implicitly coerced, normalized, or deduplicated. Missing values in key columns are rejected before joining. A pre-join validation failure returns no join result.

## Status rules

Status precedence is `FAIL`, then `WARN`, then `PASS`.

- `FAIL`: an input validation, relationship, or join-invariant violation exists.
- `WARN`: no contract violation exists, but there are unmatched rows that warrant a warning under the join-specific rules below.
- `PASS`: no contract violation exists and no unmatched rows warrant a warning.

| Condition | `left` | `inner` | `full` |
|---|---|---|---|
| Unmatched rows in `x` | `WARN` | `WARN` | `WARN` |
| Unmatched rows in `y` | Does not alone trigger `WARN` | `WARN` | `WARN` |

Unmatched rows are not, by themselves, a `FAIL`. Rows from `y` that do not match `x` are expected to be omitted by a left join; they remain visible in diagnostics.

## Join invariants

- `left`: every original row of `x` appears at least once in the result.
- `inner`: every result row represents a matching pair of input rows; unmatched input rows are intentionally excluded.
- `full`: every original row from both inputs appears at least once in the result.
- Every join type: row replication must respect the declared relationship.

Original rows are tracked with temporary technical identifiers, rather than inferred from the values of non-key columns. Input tables must not be modified by the audit.

## Diagnostic definitions

- **Unmatched row**: an original input row with no matching key in the other input. Counts are per input row, not per distinct key.
- **Row absent from result**: an original input row that contributes no row to the result. This differs from unmatched: a left join preserves unmatched rows from `x`.
- **Duplicate key group**: a distinct complete key combination that occurs more than once in one input.
- **Replicated row**: an original input row that contributes to more than one result row. The replication count is the number of original rows replicated, not the number of additional copies.
- **Matched key**: a distinct complete key combination present in both inputs.
- **Expected pairs**: for a key combination, `n_x * n_y`, the number of row pairs implied by its input frequencies.
- **Unmatched rate in x**: unmatched rows in `x` divided by the number of rows in `x`; the current convention is zero when `x` is empty.

The report should include input/result row counts, duplicate key-group counts, unmatched row counts and the unmatched rate in `x`, rows absent from the result, and replicated-row counts. `key_audit` describes key frequencies and expected pair counts.

## Test obligations

Tests must assert status, output rows and values, and relevant diagnostic counts. They must cover input validation, all four relationships, all three join types, composite keys, missing keys, empty inputs, unmatched rows on either side, permitted and prohibited replication, and preservation of the input tables.
