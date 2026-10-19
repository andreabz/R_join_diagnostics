# test-join-audit.R
# Run after loading join_audit.R.
# Test dependency: testthat.

library(testthat)
library(data.table)
source("join_audit.R")

test_that("left many-to-one join preserves every row of x", {
  x <- data.table(id = c(1L, 2L, 3L), value = c(10, 20, 30))
  y <- data.table(id = c(1L, 2L, 3L), label = c("a", "b", "c"))

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "many-to-one")
  expect_equal(a$status, "PASS")
  expect_equal(nrow(a$result), nrow(x))
  expect_equal(a$report[check == "Unmatched rows in x", value], 0)
  expect_false(any(grepl("^\\.\\.audit_row_id", names(a$result))))
})

test_that("unmatched keys produce WARN and diagnostics", {
  x <- data.table(id = c(1L, 2L), value = c(10, 20))
  y <- data.table(id = 1L, label = "a")

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "many-to-one")
  expect_equal(a$status, "WARN")
  expect_equal(nrow(a$x_unmatched), 1L)
  expect_equal(a$x_unmatched$id, 2L)
  expect_equal(nrow(a$result), 2L)
})

test_that("unmatched rows in y alone do not warn for a left join", {
  x <- data.table(id = 1L, value = 10)
  y <- data.table(
    id = c(1L, 2L),
    label = c("matched", "unmatched")
  )

  a <- join_checked(
    x, y,
    by = "id",
    type = "left",
    relationship = "one-to-one"
  )

  expect_equal(a$status, "PASS")
  expect_equal(nrow(a$x_unmatched), 0L)
  expect_equal(nrow(a$y_unmatched), 1L)
  expect_equal(
    a$report[check == "Unmatched rows in y", value], 1
  )
  expect_equal(
    a$report[check == "Rows from y absent from result", value], 1
  )
  expect_equal(nrow(a$result), 1L)
  expect_equal(a$result$id, 1L)
})

test_that("full join retains unmatched rows from both inputs", {
  x <- data.table(id = 1L, value = "x")
  y <- data.table(id = 2L, label = "y")
  a <- join_checked(x, y, by = "id", type = "full",
                    relationship = "one-to-one")
  expect_equal(a$status, "WARN")
  expect_equal(nrow(a$result), 2L)
  expect_equal(a$report[check == "Rows from x absent from result", value], 0)
  expect_equal(a$report[check == "Rows from y absent from result", value], 0)
})

test_that("inner join result contains only matched pairs", {
  x <- data.table(id = c(1L, 2L), value = c("a", "b"))
  y <- data.table(id = c(2L, 3L), label = c("matched", "unmatched"))
  a <- join_checked(x, y, by = "id", type = "inner",
                    relationship = "one-to-one")
  expect_equal(a$status, "WARN")
  expect_equal(nrow(a$result), 1L)
  expect_equal(a$result$id, 2L)
  expect_equal(a$report[check == "Rows in result", value], 1)
})

test_that("duplicates incompatible with many-to-one fail validation", {
  x <- data.table(id = c(1L, 2L), value = c(10, 20))
  y <- data.table(id = c(1L, 1L, 2L), label = c("a", "b", "c"))

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "many-to-one")
  expect_equal(a$status, "FAIL")
  expect_null(a$result)
  expect_error(assert_join(a), "declared relationship")
})

test_that("missing key values produce FAIL before joining", {
  x <- data.table(id = c(1L, NA_integer_), value = c(10, 20))
  y <- data.table(id = 1L, label = "a")

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "many-to-one")
  expect_equal(a$status, "FAIL")
  expect_true(any(grepl("Missing keys", a$violations)))
})

test_that("inner join reports rows from x absent from the result", {
  x <- data.table(id = c(1L, 2L), value = c(10, 20))
  y <- data.table(id = 1L, label = "a")

  a <- join_checked(x, y, by = "id", type = "inner",
                    relationship = "many-to-one")
  expect_equal(a$status, "WARN")
  expect_equal(nrow(a$result), 1L)
  expect_equal(a$report[check == "Rows from x absent from result", value], 1)
})

test_that("full join retains unmatched rows from both sides", {
  x <- data.table(id = c(1L, 2L), value = c(10, 20))
  y <- data.table(id = c(2L, 3L), label = c("b", "c"))

  a <- join_checked(x, y, by = "id", type = "full",
                    relationship = "one-to-one")
  expect_equal(a$status, "WARN")
  expect_equal(nrow(a$result), 3L)
  expect_equal(nrow(a$x_unmatched), 1L)
  expect_equal(nrow(a$y_unmatched), 1L)
})

test_that("incompatible key types are rejected", {
  x <- data.table(id = 1:2)
  y <- data.table(id = c("1", "2"))

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "one-to-one")
  expect_equal(a$status, "FAIL")
  expect_true(any(grepl("Incompatible type", a$violations)))
})

test_that("input tables are not modified", {
  x <- data.table(id = 1L, value = 10)
  y <- data.table(id = 1L, label = "a")
  x_before <- copy(x)
  y_before <- copy(y)

  invisible(join_checked(x, y, by = "id", type = "left",
                         relationship = "one-to-one"))
  expect_identical(x, x_before)
  expect_identical(y, y_before)
})


test_that("composite keys are audited as a single key", {
  x <- data.table(region = c("N", "N", "S"), id = c(1L, 2L, 1L), value = 1:3)
  y <- data.table(region = c("N", "N", "S"), id = c(1L, 2L, 1L), label = c("a", "b", "c"))

  a <- join_checked(x, y, by = c("region", "id"), type = "left",
                    relationship = "many-to-one")
  expect_equal(a$status, "PASS")
  expect_equal(nrow(a$result), 3L)
  expect_equal(a$key_audit[matched == TRUE, .N], 3L)
  expect_equal(a$key_audit[matched == TRUE, sum(expected_pairs)], 3)
  expect_equal(a$key_audit[matched == TRUE, all(expected_pairs == 1)], TRUE)
  expect_equal(a$result[order(region, id), label], c("a", "b", "c"))
})

test_that("empty inputs produce valid empty join results", {
  x <- data.table(id = integer(), value = double())
  y <- data.table(id = integer(), label = character())

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "one-to-one")
  expect_equal(a$status, "PASS")
  expect_equal(nrow(a$result), 0L)
  expect_equal(a$report[check == "Rows in result", value], 0)
})

test_that("overlapping non-key columns are suffixed", {
  x <- data.table(id = 1:2, value = c("x1", "x2"))
  y <- data.table(id = 1:2, value = c("y1", "y2"))

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "one-to-one")
  expect_equal(a$status, "PASS")
  expect_true(all(c("value.x", "value.y") %in% names(a$result)))
})

test_that("row multiplication is detected when the relationship is violated", {
  x <- data.table(id = c(1L, 2L), value = c("a", "b"))
  y <- data.table(id = c(1L, 1L, 2L), label = c("p", "q", "r"))

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "many-to-many")
  expect_equal(a$status, "PASS")
  expect_equal(nrow(a$result), 3L)
  expect_equal(nrow(a$x_replicated), 1L)
  expect_equal(a$x_replicated$n_result, 2L)
  expect_equal(a$report[check == "Replicated rows from x", value], 1)
  expect_equal(
    a$result[order(id, label), .(id, value, label)],
    data.table(id = c(1L, 1L, 2L),
               value = c("a", "a", "b"),
               label = c("p", "q", "r"))
  )

  b <- join_checked(x, y, by = "id", type = "left",
                    relationship = "many-to-one")
  expect_equal(b$status, "FAIL")
  expect_true(length(b$violations) > 0L)
})

test_that("invalid non-table input returns a structured failure", {
  a <- join_checked(NULL, data.table(id = 1L), by = "id",
                    type = "left", relationship = "many-to-one")
  expect_equal(a$status, "FAIL")
  expect_null(a$result)
  expect_equal(nrow(a$report), 3L)
  expect_true(is.na(a$report[check == "Rows in x", value]))
})

test_that("one-to-many allows duplicate keys in y when x keys are unique", {
  x <- data.table(id = c(1L, 2L), x_value = c("a", "b"))
  y <- data.table(id = c(1L, 1L, 2L), y_value = c("p", "q", "r"))

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "one-to-many")
  expect_equal(a$status, "PASS")
  expect_equal(nrow(a$result), 3L)
  expect_equal(nrow(a$x_replicated), 1L)
  expect_equal(nrow(a$y_replicated), 0L)
  expect_equal(
    a$result[order(id, y_value), .(id, x_value, y_value)],
    data.table(id = c(1L, 1L, 2L),
               x_value = c("a", "a", "b"),
               y_value = c("p", "q", "r"))
  )
})

test_that("one-to-many rejects duplicate keys in x", {
  x <- data.table(id = c(1L, 1L), x_value = c("a", "b"))
  y <- data.table(id = 1L, y_value = "p")

  a <- join_checked(x, y, by = "id", type = "left",
                    relationship = "one-to-many")
  expect_equal(a$status, "FAIL")
  expect_true(any(grepl("unique keys in x", a$violations)))
})
