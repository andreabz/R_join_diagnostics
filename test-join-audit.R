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
