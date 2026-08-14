# Fail-closed and atomicity smoke checks for reports/generate_review_tables.R.
# All fixtures and generated CSVs live below a temporary directory.
# Run from the repository root with: Rscript tests/smoke_generate_review_tables.R

suppressMessages(library(jsonlite))

scratch <- tempfile("review_tables_smoke_")
dir.create(scratch)
on.exit(unlink(scratch, recursive = TRUE), add = TRUE)

generator <- file.path("reports", "generate_review_tables.R")
rscript <- file.path(R.home("bin"), "Rscript")
assert <- function(ok, message) if (!isTRUE(ok)) stop(message)

run_generator <- function(results, reports, section) {
  output <- suppressWarnings(system2(
    rscript, c(generator, section),
    stdout = TRUE, stderr = TRUE,
    env = c(
      paste0("PATH_RESULTS=", results),
      paste0("REVIEW_REPORTS_DIR=", reports),
      "TESTBENCH_PROFILE=macbook",
      "SMOKE_TEST=0"
    )
  ))
  status <- attr(output, "status")
  list(status = if (is.null(status)) 0L else status, output = paste(output, collapse = "\n"))
}

expect_failure <- function(run, pattern) {
  assert(run$status != 0L, paste("Expected failure, got success:\n", run$output))
  assert(grepl(pattern, run$output, ignore.case = TRUE), paste(
    "Failure did not mention", pattern, ":\n", run$output
  ))
}

seed_snapshots <- function(reports, relative_files) {
  for (relative in relative_files) {
    path <- file.path(reports, relative)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(paste("sentinel", relative), path)
  }
  unname(tools::md5sum(file.path(reports, relative_files)))
}

assert_snapshots_unchanged <- function(reports, relative_files, hashes) {
  current <- unname(tools::md5sum(file.path(reports, relative_files)))
  assert(identical(current, hashes), "A failed regeneration changed existing CSV snapshots")
}

gcv_grid <- c(-1, 0, 10^(-9:-2))
gcv_metric <- function(value) {
  rows <- expand.grid(
    Group = 1:4, lambda = gcv_grid, repetition = 1:30,
    KEEP.OUT.ATTRS = FALSE
  )
  data.frame(Group = rows$Group, lambda = rows$lambda, R1_fPLS = value)
}

gcv_selector <- function() {
  data <- gcv_metric(NaN)
  data$R1_fPLS[data$lambda == -1] <- 1e-6
  data$R1_fPLS[data$lambda > 0] <- data$lambda[data$lambda > 0]
  data
}

gcv_scalar <- function(value) {
  rows <- expand.grid(lambda = gcv_grid, repetition = 1:30, KEEP.OUT.ATTRS = FALSE)
  data.frame(Group = 1L, lambda = rows$lambda, R1_fPLS = value)
}

gcv_loaded <- function(missing_beta_rmse = FALSE, incomplete_grid = FALSE) {
  gcv_scalar_nsrx <- function(value) {
    rows <- expand.grid(
      lambda = gcv_grid[gcv_grid != 0], repetition = 1:30,
      KEEP.OUT.ATTRS = FALSE
    )
    data.frame(Group = 1L, lambda = rows$lambda, R1_fPLS = value)
  }
  loaded <- list(
    rmse = list(
      Y_reconstruction = gcv_metric(0.2),
      X_reconstruction_locations = gcv_metric(0.3),
      Beta1_locations = gcv_metric(0.1)
    ),
    cosine = list(
      Beta_locations = gcv_metric(0.7),
      X_direction_locations = gcv_metric(0.8),
      X_loading_locations = gcv_metric(0.8),
      X_latent_scores = gcv_metric(0.8)
    ),
    direction_lambda = gcv_selector(),
    loading_lambda = gcv_selector(),
    truth_target = list(R1_fPLS = rep("prefix", length(gcv_grid) * 30L)),
    provenance = list(
      family = gcv_scalar("fixture"),
      NSR_X_final_component = gcv_scalar_nsrx(3)
    ),
    model_names = "R1_fPLS",
    varying_options = "lambda"
  )
  loaded$provenance$family$R1_fPLS <- rep(
    "sensitivity", nrow(loaded$provenance$family)
  )
  if (missing_beta_rmse) loaded$rmse$Beta1_locations <- NULL
  if (incomplete_grid) {
    loaded$cosine$Beta_locations <- loaded$cosine$Beta_locations[
      loaded$cosine$Beta_locations$lambda != max(gcv_grid), , drop = FALSE
    ]
  }
  loaded
}

write_gcv_family <- function(results, family, loaded = gcv_loaded(), schema = 6L,
                             smoke_test = FALSE, families = family,
                             aggregate_family = family, target = family) {
  directory <- file.path(results, "GCV", "aggregate", target)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  aggregate <- file.path(directory, sprintf("loaded_%s.rds", family))
  status <- file.path(directory, "run_status.json")
  loaded$provenance$family$R1_fPLS <- rep(
    aggregate_family, nrow(loaded$provenance$family)
  )
  loaded$provenance$NSR_X_final_component$R1_fPLS <- if (
    identical(aggregate_family, "sensitivity_high_NSRX")
  ) 10 else 3
  saveRDS(loaded, aggregate)
  write_json(
    list(
      schema_version = schema,
      suite = "GCV",
      requested = target,
      families = families,
      run_complete = TRUE,
      smoke_test = smoke_test,
      sensitivity_lambda_grid = gcv_grid,
      sensitivity_NSR_X = c(baseline = 3, challenging = 10)
    ),
    status, auto_unbox = TRUE, digits = NA
  )
  Sys.setFileTime(status, file.info(aggregate)$mtime + 1)
  invisible(list(aggregate = aggregate, status = status))
}

gcv_results <- file.path(scratch, "gcv_results")
gcv_reports <- file.path(scratch, "gcv_reports")
gcv_relative <- file.path(
  "gcv_tables",
  paste0(
    rep(c("sensitivity", "sensitivity_high_NSRX"), each = 6L), "_",
    rep(c(
      "Y_reconstruction", "X_reconstruction", "Beta",
      "X_direction", "X_loading", "X_scores"
    ), 2L),
    ".csv"
  )
)
gcv_hashes <- seed_snapshots(gcv_reports, gcv_relative)
write_gcv_family(gcv_results, "sensitivity", schema = 5L)
write_gcv_family(gcv_results, "sensitivity_high_NSRX")
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "schema must be exactly 6")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(gcv_results, "sensitivity")
all_families <- c(
  "sensitivity", "sensitivity_high_NSRX", "lambda_to_zero",
  "small_lambda_m_gt_k", "small_lambda_m_lt_k"
)
newest_invalid <- write_gcv_family(
  gcv_results, "sensitivity", schema = 5L,
  families = all_families, target = "all"
)
Sys.setFileTime(newest_invalid$aggregate, Sys.time() + 2)
Sys.setFileTime(newest_invalid$status, Sys.time() + 3)
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "schema must be exactly 6")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)
unlink(file.path(gcv_results, "GCV", "aggregate", "all"), recursive = TRUE)

stale <- write_gcv_family(gcv_results, "sensitivity")
Sys.setFileTime(stale$status, Sys.time())
Sys.setFileTime(stale$aggregate, Sys.time() + 1)
archive_order <- run_generator(gcv_results, gcv_reports, "gcv")
assert(archive_order$status == 0L,
       paste("Valid archived GCV fixtures failed:\n", archive_order$output))
gcv_hashes <- seed_snapshots(gcv_reports, gcv_relative)

write_gcv_family(gcv_results, "sensitivity", smoke_test = TRUE)
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "complete production run")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(gcv_results, "sensitivity", families = "wrong_family")
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "family does not match")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(
  gcv_results, "sensitivity", families = c("sensitivity", "sensitivity_high_NSRX")
)
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "exactly match")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(gcv_results, "sensitivity", aggregate_family = "wrong_family")
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "family metadata does not match")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(gcv_results, "sensitivity")
write_gcv_family(
  gcv_results, "sensitivity_high_NSRX", gcv_loaded(missing_beta_rmse = TRUE)
)
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "Beta_RMSE")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(
  gcv_results, "sensitivity_high_NSRX", gcv_loaded(incomplete_grid = TRUE)
)
expect_failure(run_generator(gcv_results, gcv_reports, "gcv"), "incomplete or non-production")
assert_snapshots_unchanged(gcv_reports, gcv_relative, gcv_hashes)

write_gcv_family(gcv_results, "sensitivity_high_NSRX")
gcv_run <- run_generator(gcv_results, gcv_reports, "gcv")
assert(gcv_run$status == 0L, paste("Valid GCV fixtures failed:\n", gcv_run$output))
assert(all(file.exists(file.path(gcv_reports, gcv_relative))), "Missing generated GCV CSV")
assert(!identical(
  unname(tools::md5sum(file.path(gcv_reports, gcv_relative))), gcv_hashes
), "Successful GCV regeneration did not replace snapshots")

iteration_specs <- list(
  list(suite = "1D", family = "vary_k", levels = c(5, 11, 21, 51, 101),
       models = c("MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS", "fPCR", "R1_fPLS")),
  list(suite = "1D", family = "vary_n", levels = c(50, 100, 200),
       models = c("MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS", "fPCR", "R1_fPLS")),
  list(suite = "1D", family = "vary_m", levels = c(50, 100, 200),
       models = c("MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS", "fPCR", "R1_fPLS")),
  list(suite = "2D", family = "vary_n", levels = c(50, 100, 200),
       models = c("MV_PLS", "fPCR", "R1_fPLS")),
  list(suite = "2D", family = "vary_k", levels = c(25, 100, 400, 900, 1600, 2500),
       models = c("MV_PLS", "fPCR", "R1_fPLS"))
)

iteration_diagnostics <- function(spec) {
  rows <- expand.grid(
    diagnostic = c("Iteration count", "Monotonic fit"),
    component = 1:4,
    level = spec$levels,
    repetition = 1:30,
    model = spec$models,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  iterative <- rows$model %in% c("fPCR", "R1_fPLS")
  rows$value <- ifelse(
    rows$diagnostic == "Iteration count", ifelse(iterative, 2, 0), 1
  )
  data.frame(family = spec$family, rows, stringsAsFactors = FALSE)
}

write_iteration_family <- function(results, spec, diagnostics = iteration_diagnostics(spec)) {
  directory <- file.path(results, spec$suite, "aggregate", spec$family)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  aggregate <- file.path(directory, sprintf("%s_diagnostics.csv", spec$family))
  status <- file.path(directory, "run_status.json")
  write.csv(diagnostics, aggregate, row.names = FALSE)
  write_json(
    list(
      schema_version = 7L,
      suite = spec$suite,
      requested = spec$family,
      families = spec$family,
      run_complete = TRUE,
      smoke_test = FALSE
    ),
    status, auto_unbox = TRUE
  )
  Sys.setFileTime(status, file.info(aggregate)$mtime + 1)
}

iteration_results <- file.path(scratch, "iteration_results")
iteration_reports <- file.path(scratch, "iteration_reports")
iteration_relative <- file.path(
  "review_tables",
  vapply(iteration_specs, function(spec) {
    sprintf("%s_%s_iterations.csv", spec$suite, spec$family)
  }, character(1))
)
iteration_hashes <- seed_snapshots(iteration_reports, iteration_relative)
for (spec in iteration_specs) write_iteration_family(iteration_results, spec)

last_spec <- iteration_specs[[length(iteration_specs)]]
missing_monotonicity <- iteration_diagnostics(last_spec)
drop <- with(missing_monotonicity,
  diagnostic == "Monotonic fit" & model == "R1_fPLS" &
    component == 4L & level == max(last_spec$levels) & repetition == 30L
)
write_iteration_family(iteration_results, last_spec, missing_monotonicity[!drop, ])
expect_failure(
  run_generator(iteration_results, iteration_reports, "iterations"),
  "incomplete monotonic fit diagnostics"
)
assert_snapshots_unchanged(iteration_reports, iteration_relative, iteration_hashes)

missing_iterations <- iteration_diagnostics(last_spec)
drop <- with(missing_iterations,
  diagnostic == "Iteration count" & model == "fPCR" &
    component == 1L & level == min(last_spec$levels) & repetition == 1L
)
write_iteration_family(iteration_results, last_spec, missing_iterations[!drop, ])
expect_failure(
  run_generator(iteration_results, iteration_reports, "iterations"),
  "incomplete iteration count diagnostics"
)
assert_snapshots_unchanged(iteration_reports, iteration_relative, iteration_hashes)

write_iteration_family(iteration_results, last_spec)
iteration_run <- run_generator(iteration_results, iteration_reports, "iterations")
assert(iteration_run$status == 0L, paste(
  "Valid iteration fixtures failed:\n", iteration_run$output
))
table <- read.csv(file.path(iteration_reports, iteration_relative[1]), check.names = FALSE)
assert(all(table[table$method == "MV-PLS", 2:6] == "--"),
       "Non-iterative MV-PLS was not rendered as unavailable")
assert(all(table[table$method == "fPCR", 2:5] != "--"),
       "Iterative fPCR diagnostics were silently rendered as unavailable")

cat("review-table fail-closed and atomicity smoke checks passed\n")
