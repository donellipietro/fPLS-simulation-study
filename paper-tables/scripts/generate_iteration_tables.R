# Generate the R1-fPLS convergence tables used in the manuscript.

suppressPackageStartupMessages(library(jsonlite))

script_file <- sub(
  "^--file=", "", commandArgs(trailingOnly = FALSE)[grep(
    "^--file=", commandArgs(trailingOnly = FALSE)
  )][1]
)
if (is.na(script_file) || !nzchar(script_file)) stop("Run this script with Rscript.")
table_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
repository_root <- normalizePath(file.path(table_root, ".."), mustWork = TRUE)
results_root <- normalizePath(
  Sys.getenv("FPLS_RESULTS", unset = file.path(repository_root, "results")),
  mustWork = TRUE
)
output_dir <- file.path(table_root, "csv")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

spec <- function(suite, family, levels, components = 1:4, varying_h = FALSE,
                 excluded_levels = numeric()) {
  list(
    suite = suite, family = family, levels = levels,
    components = components, varying_h = varying_h,
    excluded_levels = excluded_levels
  )
}

specs <- list(
  spec("1D", "vary_k", c(5, 11, 21, 51, 101)),
  spec("1D", "vary_n", c(50, 100, 200)),
  spec("1D", "vary_m", c(50, 100, 200)),
  spec("1D", "vary_NSRX", c(1, 3, 5, 10)),
  spec("1D", "vary_NSRY", c(0.01, 0.1, 0.5, 1)),
  spec("2D", "vary_n", c(50, 100, 200)),
  spec("2D", "vary_m", c(900, 1600, 2400)),
  spec("2D", "vary_k", c(25, 100, 400, 900, 1600, 2500)),
  spec("2D", "vary_NSRX", c(1, 3, 5, 10)),
  spec("2D", "vary_NSRY", c(0.01, 0.1, 0.5, 1)),
  spec("GCV", "sensitivity", c(-1, 0, 10^(-9:-2)), excluded_levels = 0),
  spec(
    "GCV", "sensitivity_high_NSRX", c(-1, 0, 10^(-9:-2)),
    excluded_levels = 0
  ),
  spec("2D", "vary_H", 1:5, components = 1L, varying_h = TRUE),
  spec(
    "2D-predictive-order", "vary_H", 1:10,
    components = 1L, varying_h = TRUE
  )
)

schema_versions <- c(`1D` = 7L, `2D` = 7L, GCV = 6L, `2D-predictive-order` = 2L)
required_diagnostics <- c(
  "Iteration count", "Reached iteration cap", "Finite solution"
)

validate_status <- function(item, aggregate_dir) {
  file <- file.path(aggregate_dir, "run_status.json")
  if (!file.exists(file)) stop("Missing validated aggregate status: ", file)
  status <- fromJSON(file, simplifyVector = TRUE)
  if (!identical(as.integer(status$schema_version), schema_versions[[item$suite]]) ||
      !identical(status$suite, item$suite) ||
      !identical(status$requested, "all") ||
      !item$family %in% as.character(status$families) ||
      !identical(status$run_complete, TRUE) ||
      !identical(status$smoke_test, FALSE)) {
    stop("Aggregate status is not a complete production run: ", file)
  }
  flags <- if (identical(item$suite, "2D-predictive-order")) {
    status$diagnostic_outputs
  } else {
    status$diagnostic_outputs[[item$family]]
  }
  required_flags <- c("iteration_count", "hit_max_iter", "finite_solution")
  if (is.null(flags) || any(!vapply(flags[required_flags], identical, logical(1), TRUE))) {
    stop("Aggregate status is missing convergence diagnostics: ", file)
  }
}

cell_key <- function(rows) paste(
  as.integer(rows$component),
  format(as.numeric(rows$level), scientific = TRUE, digits = 17, trim = TRUE),
  as.integer(rows$repetition),
  sep = "|"
)

read_diagnostics <- function(item) {
  aggregate_dir <- file.path(results_root, item$suite, "aggregate", "all")
  validate_status(item, aggregate_dir)
  file <- file.path(aggregate_dir, paste0(item$family, "_diagnostics.csv"))
  if (!file.exists(file)) stop("Missing paper-facing diagnostics: ", file)
  diagnostics <- read.csv(file, stringsAsFactors = FALSE)
  required_columns <- c(
    "family", "diagnostic", "component", "level", "repetition", "model", "value"
  )
  if (any(!required_columns %in% names(diagnostics)) ||
      any(diagnostics$family != item$family)) {
    stop("Invalid diagnostics schema or family: ", file)
  }

  expected <- expand.grid(
    component = item$components,
    level = item$levels,
    repetition = 1:30,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  expected_keys <- sort(cell_key(expected))
  selected <- lapply(required_diagnostics, function(name) {
    rows <- diagnostics[
      diagnostics$model == "R1_fPLS" & diagnostics$diagnostic == name,
      required_columns,
      drop = FALSE
    ]
    keys <- cell_key(rows)
    if (nrow(rows) != nrow(expected) || anyDuplicated(keys) ||
        !identical(sort(keys), expected_keys) || any(!is.finite(rows$value))) {
      stop(sprintf("Incomplete %s for %s/%s", tolower(name), item$suite, item$family))
    }
    rows
  })
  names(selected) <- required_diagnostics

  iterations <- selected[["Iteration count"]]
  hit_cap <- selected[["Reached iteration cap"]]
  finite <- selected[["Finite solution"]]
  zero_allowed <- iterations$level %in% item$excluded_levels
  if (any(iterations$value < 0 | iterations$value != round(iterations$value)) ||
      any(iterations$value == 0 & !zero_allowed) ||
      any(iterations$value != 0 & zero_allowed)) {
    stop("Invalid iteration counts for ", item$suite, "/", item$family)
  }
  if (any(!hit_cap$value %in% c(0, 1)) || any(!finite$value %in% c(0, 1))) {
    stop("Invalid binary convergence diagnostics for ", item$suite, "/", item$family)
  }
  if (any(finite$value != 1)) {
    stop("Non-finite R1-fPLS solution in ", item$suite, "/", item$family)
  }
  included <- !iterations$level %in% item$excluded_levels
  list(
    iterations = iterations[included, , drop = FALSE],
    hit_cap = hit_cap[included, , drop = FALSE],
    finite = finite[included, , drop = FALSE]
  )
}

loaded <- Map(function(item) c(item, read_diagnostics(item)), specs)

fixed <- lapply(loaded[!vapply(loaded, `[[`, logical(1), "varying_h")], function(item) {
  values <- item$iterations
  row <- data.frame(suite = item$suite, experiment = item$family)
  for (component in 1:4) {
    component_values <- values$value[values$component == component]
    row[[paste0("h", component, "_median")]] <- median(component_values)
    row[[paste0("h", component, "_max")]] <- max(component_values)
  }
  row
})
fixed <- do.call(rbind, fixed)

varying <- lapply(loaded[vapply(loaded, `[[`, logical(1), "varying_h")], function(item) {
  values <- item$iterations
  do.call(rbind, lapply(item$levels, function(component) {
    component_values <- values$value[values$level == component]
    data.frame(
      suite = item$suite,
      experiment = item$family,
      component = component,
      median_iterations = median(component_values),
      max_iterations = max(component_values)
    )
  }))
})
varying <- do.call(rbind, varying)

all_iterations <- unlist(lapply(loaded, function(item) item$iterations$value))
all_cap_hits <- unlist(lapply(loaded, function(item) item$hit_cap$value))
all_finite <- unlist(lapply(loaded, function(item) item$finite$value))
summary <- data.frame(
  experiments = length(loaded),
  component_optimizations = length(all_iterations),
  median_iterations = median(all_iterations),
  max_iterations = max(all_iterations),
  iteration_cap_hits = sum(all_cap_hits),
  all_within_iteration_cap = all(all_cap_hits == 0),
  nonfinite_solutions = sum(all_finite != 1),
  all_solutions_finite = all(all_finite == 1)
)

if (nrow(fixed) != 12L || nrow(varying) != 15L || nrow(summary) != 1L ||
    any(fixed[grep("_median$", names(fixed))] > fixed[grep("_max$", names(fixed))]) ||
    any(varying$median_iterations > varying$max_iterations)) {
  stop("Generated iteration-table shape or summaries are inconsistent")
}

write.csv(fixed, file.path(output_dir, "fixed_h_iterations.csv"), row.names = FALSE)
write.csv(varying, file.path(output_dir, "varying_h_iterations.csv"), row.names = FALSE)
write.csv(summary, file.path(output_dir, "convergence_summary.csv"), row.names = FALSE)
message("Regenerated paper convergence tables in ", output_dir, ".")
