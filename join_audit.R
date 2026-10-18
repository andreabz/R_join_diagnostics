# join_audit.R
# Join auditing for data.table. No runtime dependency beyond data.table.

library(data.table)

# Return TRUE when every composite key is unique.
.keys_unique <- function(dt, by) {
  !anyDuplicated(dt[, ..by])
}

# Count rows for each composite key.
.key_counts <- function(dt, by, count_name) {
  out <- dt[, .N, by = by]
  setnames(out, "N", count_name)
  out
}

# Build a frequency table for keys found in x and y.
.key_frequency_audit <- function(x, y, by) {
  cx <- .key_counts(x, by, "n_x")
  cy <- .key_counts(y, by, "n_y")
  merge(cx, cy, by = by, all = TRUE, sort = FALSE)[
    , `:=`(
      n_x = fifelse(is.na(n_x), 0L, n_x),
      n_y = fifelse(is.na(n_y), 0L, n_y)
    )
  ][
    , `:=`(
      matched = n_x > 0L & n_y > 0L,
      expected_pairs = as.double(n_x) * as.double(n_y)
    )
  ]
}

# Validate prerequisites without modifying the inputs.
validate_join <- function(x, y, by,
                          relationship = c("many-to-one", "one-to-one",
                                           "one-to-many", "many-to-many")) {
  relationship <- match.arg(relationship)
  errors <- character()

  if (!is.data.table(x) || !is.data.table(y)) {
    return(list(ok = FALSE, errors = "x and y must be data.table objects."))
  }
  if (!is.character(by) || length(by) < 1L || anyNA(by) ||
      any(!nzchar(by)) || anyDuplicated(by)) {
    return(list(ok = FALSE, errors = "`by` must contain unique, non-empty column names."))
  }
  if (!all(by %in% names(x))) {
    errors <- c(errors, paste("Missing key columns in x:", paste(setdiff(by, names(x)), collapse = ", ")))
  }
  if (!all(by %in% names(y))) {
    errors <- c(errors, paste("Missing key columns in y:", paste(setdiff(by, names(y)), collapse = ", ")))
  }
  if (length(errors)) {
    return(list(ok = FALSE, errors = errors))
  }

  # Require identical key types and classes; do not coerce implicitly.
  for (k in by) {
    if (!identical(class(x[[k]]), class(y[[k]])) ||
        !identical(typeof(x[[k]]), typeof(y[[k]]))) {
      errors <- c(errors, sprintf(
        "Incompatible type for key '%s' (x: %s/%s; y: %s/%s).",
        k, paste(class(x[[k]]), collapse = "/"), typeof(x[[k]]),
        paste(class(y[[k]]), collapse = "/"), typeof(y[[k]])
      ))
    }
  }

  x_missing <- sum(!complete.cases(x[, ..by]))
  y_missing <- sum(!complete.cases(y[, ..by]))
  if (x_missing > 0L || y_missing > 0L) {
    errors <- c(errors, sprintf(
      "Missing keys: %d rows in x and %d rows in y.",
      x_missing, y_missing
    ))
  }

  x_unique <- .keys_unique(x, by)
  y_unique <- .keys_unique(y, by)

  if (relationship %in% c("one-to-one", "one-to-many") && !x_unique) {
    errors <- c(errors, "The declared relationship requires unique keys in x.")
  }
  if (relationship %in% c("one-to-one", "many-to-one") && !y_unique) {
    errors <- c(errors, "The declared relationship requires unique keys in y.")
  }

  list(
    ok = length(errors) == 0L,
    errors = unique(errors),
    x_missing_key_rows = x_missing,
    y_missing_key_rows = y_missing,
    x_keys_unique = x_unique,
    y_keys_unique = y_unique,
    relationship = relationship
  )
}

# Execute the join and return the result together with the audit.
# With stop_on_fail = FALSE, retain the diagnostic object; use assert_join()
# to stop the pipeline explicitly.
join_checked <- function(x, y, by,
                         type = c("left", "inner", "full"),
                         relationship = c("many-to-one", "one-to-one",
                                          "one-to-many", "many-to-many"),
                         stop_on_fail = FALSE) {
  type <- match.arg(type)
  relationship <- match.arg(relationship)

  pre <- validate_join(x, y, by, relationship)

  empty_result <- NULL
  if (!isTRUE(pre$ok)) {
    # Invalid inputs may not have a row count; keep the failure report well-formed.
    safe_nrow <- function(z) {
      if (is.data.frame(z)) nrow(z) else NA_integer_
    }
    out <- list(
      result = empty_result,
      status = "FAIL",
      violations = pre$errors,
      report = data.table(
        check = c("Rows in x", "Rows in y", "Rows in result"),
        value = c(safe_nrow(x), safe_nrow(y), NA_integer_)
      ),
      key_audit = NULL,
      x_unmatched = NULL,
      y_unmatched = NULL,
      x_replicated = NULL,
      y_replicated = NULL,
      validation = pre,
      type = type,
      relationship = relationship
    )
    if (stop_on_fail) assert_join(out)
    return(out)
  }

  # Work on copies to avoid mutating caller-owned objects.
  xx <- copy(x)
  yy <- copy(y)

  # Use temporary names that do not already exist in either input.
  x_id <- "..audit_row_id_x"
  y_id <- "..audit_row_id_y"
  while (x_id %in% c(names(xx), names(yy))) x_id <- paste0(x_id, "_")
  while (y_id %in% c(names(xx), names(yy), x_id)) y_id <- paste0(y_id, "_")
  xx[, (x_id) := .I]
  yy[, (y_id) := .I]

  # Anti-joins and key frequencies.
  x_unmatched <- xx[!yy, on = by]
  y_unmatched <- yy[!xx, on = by]
  key_audit <- .key_frequency_audit(xx, yy, by)

  # Join copies while retaining technical row identifiers.
  result <- switch(
    type,
    left = merge(xx, yy, by = by, all.x = TRUE, sort = FALSE,
                 suffixes = c(".x", ".y")),
    inner = merge(xx, yy, by = by, all = FALSE, sort = FALSE,
                  suffixes = c(".x", ".y")),
    full = merge(xx, yy, by = by, all = TRUE, sort = FALSE,
                 suffixes = c(".x", ".y"))
  )

  # Count how often each original row appears in the result.
  x_occ <- result[!is.na(get(x_id)), .(n_result = .N), by = x_id]
  y_occ <- result[!is.na(get(y_id)), .(n_result = .N), by = y_id]

  x_replicated <- x_occ[n_result > 1L]
  y_replicated <- y_occ[n_result > 1L]

  x_lost <- setdiff(seq_len(nrow(xx)), x_occ[[x_id]])
  y_lost <- setdiff(seq_len(nrow(yy)), y_occ[[y_id]])

  violations <- character()
  # In many-to-one / one-to-one relationships, each row of x may appear at most once.
  if (relationship %in% c("many-to-one", "one-to-one") &&
      nrow(x_replicated) > 0L) {
    violations <- c(violations, "Rows from x were replicated despite the declared relationship.")
  }
  # In one-to-many / one-to-one relationships, each row of y may appear at most once.
  if (relationship %in% c("one-to-many", "one-to-one") &&
      nrow(y_replicated) > 0L) {
    violations <- c(violations, "Rows from y were replicated despite the declared relationship.")
  }

  # A left join must retain every row of x exactly once.
  if (type == "left" &&
      (length(x_lost) > 0L || nrow(x_replicated) > 0L)) {
    violations <- c(violations, "The left join did not retain every row of x exactly once.")
  }

  unmatched_x_n <- nrow(x_unmatched)
  unmatched_y_n <- nrow(y_unmatched)
  status <- if (length(violations)) "FAIL" else if (unmatched_x_n > 0L || unmatched_y_n > 0L) "WARN" else "PASS"

  # Keep technical row IDs out of the public join result.
  result[, (c(x_id, y_id)) := NULL]

  report <- data.table(
    check = c(
      "Rows in x",
      "Rows in y",
      "Duplicate key groups in x",
      "Duplicate key groups in y",
      "Unmatched rows in x",
      "Unmatched rows in y",
      "Unmatched rate in x",
      "Rows from x absent from result",
      "Rows from y absent from result",
      "Replicated rows from x",
      "Replicated rows from y",
      "Rows in result"
    ),
    value = c(
      nrow(xx), nrow(yy),
      nrow(.key_counts(xx, by, "n")[n > 1L]),
      nrow(.key_counts(yy, by, "n")[n > 1L]),
      unmatched_x_n, unmatched_y_n,
      if (nrow(xx) == 0L) 0 else unmatched_x_n / nrow(xx),
      length(x_lost), length(y_lost),
      nrow(x_replicated), nrow(y_replicated),
      nrow(result)
    )
  )

  # Diagnostic tables retain the original columns and technical row identifiers.
  out <- list(
    result = result,
    status = status,
    violations = unique(violations),
    report = report,
    key_audit = key_audit,
    x_unmatched = x_unmatched,
    y_unmatched = y_unmatched,
    x_replicated = x_replicated,
    y_replicated = y_replicated,
    validation = pre,
    type = type,
    relationship = relationship,
    technical_ids = list(x = x_id, y = y_id)
  )

  if (stop_on_fail && status == "FAIL") assert_join(out)
  out
}

# Stop the pipeline when the audit status is FAIL.
# The caller can inspect the audit object before calling this assertion.
assert_join <- function(audit) {
  if (!is.list(audit) || is.null(audit$status)) {
    stop("`audit` was not produced by join_checked().", call. = FALSE)
  }
  if (identical(audit$status, "FAIL")) {
    details <- if (length(audit$violations)) {
      paste(audit$violations, collapse = "; ")
    } else {
      "Join contract violation."
    }
    stop(details, call. = FALSE)
  }
  invisible(audit$result)
}
