# Generate every CSV table consumed by review_simulation_results.tex.
# Run from the repository root after aggregating production results:
#   Rscript reports/generate_review_tables.R
# Optional sections for focused checks: gcv, design, iterations.

suppressMessages(library(jsonlite))
suppressMessages(library(RColorBrewer))

source("src/utils/options.R")
source("src/utils/directories.R")
source("config.R")

cfg <- get_config()
results_dir <- Sys.getenv("PATH_RESULTS", unset = cfg$PATH_RESULTS)
reports_dir <- Sys.getenv("REVIEW_REPORTS_DIR", unset = "reports")
sections <- commandArgs(trailingOnly = TRUE)
available_sections <- c("gcv", "design", "iterations")
if (!length(sections)) sections <- available_sections
sections <- unique(sections)
unknown_sections <- setdiff(sections, available_sections)
if (length(unknown_sections)) {
  stop("Unknown review-table section: ", paste(unknown_sections, collapse = ", "))
}
dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
staging_dir <- tempfile(".review_tables_staging_", tmpdir = reports_dir)
dir.create(staging_dir)
on.exit(unlink(staging_dir, recursive = TRUE), add = TRUE)
gcv_output_dir <- file.path(staging_dir, "gcv_tables")
review_output_dir <- file.path(staging_dir, "review_tables")
dir.create(gcv_output_dir, recursive = TRUE)
dir.create(review_output_dir, recursive = TRUE)

same_numeric_grid <- function(actual, expected) {
  actual <- sort(as.numeric(actual))
  expected <- sort(as.numeric(expected))
  length(actual) == length(expected) && all(is.finite(actual)) &&
    isTRUE(all.equal(actual, expected, tolerance = 1e-14, check.attributes = FALSE))
}

validate_run_status <- function(status, suite, family, target) {
  expected_schema <- switch(suite, GCV = 6L, `1D` = 7L, `2D` = 7L)
  if (!is.numeric(status$schema_version) || length(status$schema_version) != 1L ||
      !is.finite(status$schema_version) || status$schema_version != expected_schema) {
    stop(sprintf("run_status schema must be exactly %d", expected_schema))
  }
  if (!identical(status$suite, suite) || !identical(status$requested, target) ||
      !family %in% as.character(status$families)) {
    stop("run_status suite, requested target, or family does not match")
  }
  if (!identical(status$run_complete, TRUE) || !identical(status$smoke_test, FALSE)) {
    stop("run_status is not a complete production run")
  }
  if (identical(suite, "GCV")) {
    all_gcv_families <- c(
      "sensitivity", "sensitivity_high_NSRX", "lambda_to_zero",
      "small_lambda_m_gt_k", "small_lambda_m_lt_k"
    )
    expected_families <- switch(
      target,
      all = all_gcv_families,
      sensitivity_review = all_gcv_families[1:2],
      family
    )
    actual_families <- as.character(status$families)
    if (length(actual_families) != length(expected_families) ||
        !identical(sort(actual_families), sort(expected_families))) {
      stop("run_status families do not exactly match the requested GCV target")
    }
    if (!same_numeric_grid(status$sensitivity_lambda_grid, c(-1, 0, 10^(-9:-2)))) {
      stop("run_status does not declare the complete sensitivity lambda grid")
    }
    if (!same_numeric_grid(status$sensitivity_NSR_X, c(3, 10))) {
      stop("run_status does not declare both sensitivity noise regimes")
    }
  }
  invisible(TRUE)
}

aggregate_file <- function(suite, family, filename, groups = character()) {
  targets <- unique(c("all", groups, family))
  candidates <- file.path(results_dir, suite, "aggregate", targets, filename)
  existing <- which(file.exists(candidates))
  if (!length(existing)) {
    stop(paste(
      "Missing", sprintf("%s/%s aggregate %s", suite, family, filename),
      "from every supported aggregate target:\n ",
      paste(candidates, collapse = "\n  ")
    ))
  }

  existing_candidates <- candidates[existing]
  selected_index <- existing[which.max(file.info(existing_candidates)$mtime)]
  selected <- candidates[selected_index]
  status_file <- file.path(dirname(selected), "run_status.json")
  error <- tryCatch({
    if (!file.exists(status_file)) stop("missing run_status.json")
    mtimes <- file.info(c(selected, status_file))$mtime
    if (any(is.na(mtimes)) || mtimes[2] < mtimes[1]) {
      stop("run_status.json predates the aggregate artifact")
    }
    status <- fromJSON(status_file, simplifyVector = TRUE)
    validate_run_status(status, suite, family, targets[selected_index])
    NULL
  }, error = conditionMessage)
  if (!is.null(error)) {
    stop(sprintf(
      "Newest aggregate candidate is not a valid production artifact (%s): %s",
      selected, error
    ))
  }
  message("Using validated production aggregate ", selected)
  selected
}

commit_staged_csvs <- function(relative_files) {
  backup_dir <- tempfile(".review_tables_backup_", tmpdir = reports_dir)
  dir.create(backup_dir)
  installed <- backed_up <- logical(length(relative_files))
  committed <- FALSE
  on.exit({
    if (!committed) {
      for (i in rev(seq_along(relative_files))) {
        final <- file.path(reports_dir, relative_files[i])
        backup <- file.path(backup_dir, relative_files[i])
        if ((installed[i] || backed_up[i]) && file.exists(final)) unlink(final)
        if (backed_up[i] && !file.rename(backup, final)) {
          warning("Failed to restore review-table snapshot: ", final)
        }
      }
    }
    unlink(backup_dir, recursive = TRUE)
  }, add = TRUE)

  for (i in seq_along(relative_files)) {
    staged <- file.path(staging_dir, relative_files[i])
    final <- file.path(reports_dir, relative_files[i])
    backup <- file.path(backup_dir, relative_files[i])
    dir.create(dirname(final), recursive = TRUE, showWarnings = FALSE)
    if (file.exists(final)) {
      dir.create(dirname(backup), recursive = TRUE, showWarnings = FALSE)
      if (!file.rename(final, backup)) {
        stop("Cannot stage existing review-table snapshot for replacement: ", final)
      }
      backed_up[i] <- TRUE
    }
    if (!file.rename(staged, final)) {
      stop("Cannot install staged review-table CSV: ", final)
    }
    installed[i] <- TRUE
  }
  committed <- TRUE
  invisible(TRUE)
}

format_lambda <- function(value) {
  if (is.na(value)) return("")
  if (value == 0) return("0")
  exponent <- round(log10(value))
  if (isTRUE(all.equal(value, 10^exponent))) {
    return(sprintf("10^{%d}", exponent))
  }
  format(value, scientific = TRUE, digits = 3, trim = TRUE)
}

gcv_lambda_grid <- c(-1, 0, 10^(-9:-2))

validate_gcv_metric <- function(data, label, lower = -Inf, upper = Inf) {
  required <- c("Group", "lambda", "R1_fPLS")
  if (is.null(data) || any(!required %in% names(data))) {
    stop(sprintf("Missing GCV table input: %s", label))
  }
  groups <- sort(unique(as.integer(as.character(data$Group))))
  lambdas <- sort(unique(as.numeric(data$lambda)))
  counts <- aggregate(
    data$R1_fPLS,
    list(component = data$Group, lambda = data$lambda),
    length
  )
  values <- as.numeric(data$R1_fPLS)
  if (!identical(groups, 1:4) || !same_numeric_grid(lambdas, gcv_lambda_grid) ||
      nrow(data) != 4L * length(gcv_lambda_grid) * 30L ||
      nrow(counts) != 4L * length(gcv_lambda_grid) || any(counts$x != 30L) ||
      any(!is.finite(values)) || any(values < lower) || any(values > upper)) {
    stop(sprintf("GCV table input is incomplete or non-production: %s", label))
  }
}

validate_gcv_selector <- function(data, label) {
  required <- c("Group", "lambda", "R1_fPLS")
  if (is.null(data) || any(!required %in% names(data))) {
    stop(sprintf("Missing GCV selector input: %s", label))
  }
  groups <- sort(unique(as.integer(as.character(data$Group))))
  counts <- aggregate(
    data$R1_fPLS,
    list(component = data$Group, lambda = data$lambda),
    length
  )
  if (!identical(groups, 1:4) ||
      !same_numeric_grid(unique(data$lambda), gcv_lambda_grid) ||
      nrow(data) != 4L * length(gcv_lambda_grid) * 30L ||
      nrow(counts) != 4L * length(gcv_lambda_grid) || any(counts$x != 30L)) {
    stop(sprintf("GCV selector input is incomplete or non-production: %s", label))
  }
  fixed <- data$lambda > 0
  if (any(!is.finite(data$R1_fPLS[fixed])) || !isTRUE(all.equal(
    as.numeric(data$R1_fPLS[fixed]), as.numeric(data$lambda[fixed]),
    check.attributes = FALSE
  ))) {
    stop(sprintf("Fixed-lambda selector diagnostics are invalid: %s", label))
  }
  selected <- data$R1_fPLS[data$lambda == -1]
  if (any(!is.finite(selected)) ||
      any(!selected %in% gcv_lambda_grid[gcv_lambda_grid > 0])) {
    stop(sprintf("GCV selector chose a lambda outside the production grid: %s", label))
  }
  invisible(TRUE)
}

validate_gcv_aggregate <- function(loaded, family) {
  aggregate_families <- loaded$provenance$family$R1_fPLS
  expected_rows <- length(gcv_lambda_grid) * 30L
  expected_nsrx <- if (identical(family, "sensitivity_high_NSRX")) 10 else 3
  aggregate_nsrx <- loaded$provenance$NSR_X_final_component$R1_fPLS
  if (!identical(as.character(loaded$model_names), "R1_fPLS") ||
      !identical(as.character(loaded$varying_options), "lambda") ||
      is.null(aggregate_families) ||
      length(aggregate_families) != expected_rows ||
      any(is.na(aggregate_families) | aggregate_families != family) ||
      is.null(aggregate_nsrx) || length(aggregate_nsrx) != expected_rows ||
      any(!is.finite(aggregate_nsrx) | aggregate_nsrx != expected_nsrx)) {
    stop(sprintf("GCV aggregate family metadata does not match: %s", family))
  }
  metrics <- list(
    Y_reconstruction = list(loaded$rmse$Y_reconstruction, 0, Inf),
    X_reconstruction = list(loaded$rmse$X_reconstruction_locations, 0, Inf),
    Beta_RMSE = list(loaded$rmse$Beta1_locations, 0, Inf),
    Beta = list(loaded$cosine$Beta_locations, -1, 1),
    X_direction = list(loaded$cosine$X_direction_locations, 0, 1),
    X_loading = list(loaded$cosine$X_loading_locations, 0, 1),
    X_scores = list(loaded$cosine$X_latent_scores, 0, 1)
  )
  for (name in names(metrics)) {
    validate_gcv_metric(
      metrics[[name]][[1]], paste(family, name),
      metrics[[name]][[2]], metrics[[name]][[3]]
    )
  }
  validate_gcv_selector(loaded$direction_lambda, paste(family, "direction lambda"))
  validate_gcv_selector(loaded$loading_lambda, paste(family, "loading lambda"))
  selection_distribution(loaded$direction_lambda, paste(family, "direction lambda"))
  selection_distribution(loaded$loading_lambda, paste(family, "loading lambda"))
  if (is.null(loaded$truth_target$R1_fPLS) ||
      length(loaded$truth_target$R1_fPLS) != expected_rows ||
      any(loaded$truth_target$R1_fPLS != "prefix")) {
    stop(sprintf("GCV aggregate does not use prefix truth: %s", family))
  }
  invisible(TRUE)
}

median_by_component <- function(data, lambda_value) {
  selected <- data[data$lambda == lambda_value, , drop = FALSE]
  aggregate(
    selected[["R1_fPLS"]],
    list(h = as.integer(as.character(selected$Group))),
    median
  )
}

selection_distribution <- function(data, label) {
  selected <- data[data$lambda == -1, , drop = FALSE]
  selected <- selected[is.finite(selected$R1_fPLS), , drop = FALSE]
  counts_by_component <- table(selected$Group)
  if (!identical(sort(as.integer(names(counts_by_component))), 1:4) ||
      any(counts_by_component != 30L) || any(selected$R1_fPLS <= 0)) {
    stop(sprintf("GCV selector input is incomplete or non-production: %s", label))
  }
  distributions <- lapply(split(selected, selected$Group), function(rows) {
    counts <- table(rows$R1_fPLS)
    counts <- counts[order(-as.numeric(counts), as.numeric(names(counts)))]
    percentages <- 100 * as.numeric(counts) / sum(counts)
    formatted_percentages <- vapply(percentages, function(value) {
      if (abs(value - round(value)) < 1e-8) {
        sprintf("%d", round(value))
      } else {
        sprintf("%.1f", value)
      }
    }, character(1))
    paste(
      paste0(
        vapply(as.numeric(names(counts)), format_lambda, character(1)),
        "\\,(", formatted_percentages, "\\%)"
      ),
      collapse = "\\;;\\;"
    )
  })
  data.frame(
    h = as.integer(names(distributions)),
    distribution = unname(unlist(distributions)),
    stringsAsFactors = FALSE
  )
}

best_fixed <- function(data, higher_is_better) {
  fixed <- data[data$lambda > 0, , drop = FALSE]
  summaries <- aggregate(
    fixed[["R1_fPLS"]],
    list(h = as.integer(as.character(fixed$Group)), lambda = fixed$lambda),
    median
  )
  names(summaries)[3] <- "value"
  chosen <- do.call(rbind, lapply(split(summaries, summaries$h), function(rows) {
    rows <- rows[order(rows$lambda), , drop = FALSE]
    index <- if (higher_is_better) which.max(rows$value) else which.min(rows$value)
    rows[index, , drop = FALSE]
  }))
  chosen[order(chosen$h), , drop = FALSE]
}

write_gcv_table <- function(loaded, family, metric_name, data, higher_is_better) {
  validate_gcv_metric(data, paste(family, metric_name))
  fixed <- best_fixed(data, higher_is_better)
  gcv_metric <- median_by_component(data, -1)
  mv_metric <- median_by_component(data, 0)
  gcv_direction <- selection_distribution(
    loaded$direction_lambda, paste(family, "direction lambda")
  )
  gcv_loading <- selection_distribution(
    loaded$loading_lambda, paste(family, "loading lambda")
  )

  rows <- data.frame(
    h = fixed$h,
    lambda_fixed = vapply(fixed$lambda, format_lambda, character(1)),
    lambda_gcv_dir = gcv_direction$distribution[match(fixed$h, gcv_direction$h)],
    lambda_gcv_load = gcv_loading$distribution[match(fixed$h, gcv_loading$h)],
    metric_fixed = sprintf("%.4f", fixed$value),
    metric_gcv = sprintf("%.4f", gcv_metric$x[match(fixed$h, gcv_metric$h)]),
    metric_mv = sprintf("%.4f", mv_metric$x[match(fixed$h, mv_metric$h)]),
    stringsAsFactors = FALSE
  )
  write.csv(
    rows,
    file.path(gcv_output_dir, sprintf("%s_%s.csv", family, metric_name)),
    row.names = FALSE,
    quote = FALSE
  )
}

if ("gcv" %in% sections) {
  for (family in c("sensitivity", "sensitivity_high_NSRX")) {
    loaded <- readRDS(aggregate_file(
      "GCV", family, sprintf("loaded_%s.rds", family),
      groups = "sensitivity_review"
    ))
    validate_gcv_aggregate(loaded, family)
    metrics <- list(
      Y_reconstruction = list(data = loaded$rmse$Y_reconstruction, higher = FALSE),
      X_reconstruction = list(data = loaded$rmse$X_reconstruction_locations, higher = FALSE),
      Beta = list(data = loaded$cosine$Beta_locations, higher = TRUE),
      X_direction = list(data = loaded$cosine$X_direction_locations, higher = TRUE),
      X_loading = list(data = loaded$cosine$X_loading_locations, higher = TRUE),
      X_scores = list(data = loaded$cosine$X_latent_scores, higher = TRUE)
    )
    for (metric_name in names(metrics)) {
      write_gcv_table(
        loaded, family, metric_name,
        metrics[[metric_name]]$data,
        metrics[[metric_name]]$higher
      )
    }
  }
}

load_family_options <- function(suite, family) {
  suite_environment <- new.env(parent = .GlobalEnv)
  sys.source(file.path("tests", suite, "config.R"), envir = suite_environment)
  suite_environment$SMOKE_TEST <- FALSE
  sys.source(
    file.path("tests", suite, "utils", "generate_options.R"),
    envir = suite_environment
  )

  queue_dir <- tempfile(sprintf("review_%s_%s_", suite, family))
  dir.create(queue_dir)
  on.exit(unlink(queue_dir, recursive = TRUE), add = TRUE)
  suite_environment$generate_options(suite, family, queue_dir)
  option_files <- sort(list.files(queue_dir, pattern = "[.]json$", full.names = TRUE))
  lapply(option_files, fromJSON, simplifyVector = TRUE)
}

option_values <- function(options, accessor) {
  sort(unique(unlist(lapply(options, accessor), use.names = FALSE)))
}

latex_values <- function(values) {
  values <- sort(unique(values))
  text <- paste(values, collapse = ",")
  if (length(values) == 1L) text else paste0("\\{", text, "\\}")
}

dimension_values <- function(options, name) {
  option_values(options, function(option) option$dimensions[[name]])
}
competitor_values <- function(options, name) {
  option_values(options, function(option) option$competitors[[name]])
}

if ("design" %in% sections) {
  plot_1d <- new.env(parent = .GlobalEnv)
  sys.source("tests/1D/utils/plot_qualitative_results.R", envir = plot_1d)
  plot_2d <- new.env(parent = .GlobalEnv)
  sys.source("tests/2D/utils/plot_qualitative_results.R", envir = plot_2d)

  one_d_k <- load_family_options("1D", "vary_k")
  one_d_n <- load_family_options("1D", "vary_n")
  one_d_m <- load_family_options("1D", "vary_m")
  two_d_n <- load_family_options("2D", "vary_n")

  submitted_design <- data.frame(
    suite_test = c("1D/vary\\_k", "1D/vary\\_n", "1D/vary\\_m", "2D/vary\\_n"),
    setting = c(
      sprintf(
        "$n=%s$, $m=%s$, $k=%s$; qualitativo per $k=%s$",
        latex_values(dimension_values(one_d_k, "n_stat_units")),
        latex_values(dimension_values(one_d_k, "n_locs")),
        latex_values(dimension_values(one_d_k, "source_k")),
        latex_values(plot_1d$qualitative_source_k_1d)
      ),
      sprintf(
        "$n=%s$, $m=%s$; $k=%s$, base dei competitor $k=%s$",
        latex_values(dimension_values(one_d_n, "n_stat_units")),
        latex_values(dimension_values(one_d_n, "n_locs")),
        latex_values(dimension_values(one_d_n, "source_k")),
        latex_values(competitor_values(one_d_n, "basis_k"))
      ),
      sprintf(
        "$n=%s$, $m=%s$; $k=%s$, base dei competitor $k=%s$",
        latex_values(dimension_values(one_d_m, "n_stat_units")),
        latex_values(dimension_values(one_d_m, "n_locs")),
        latex_values(dimension_values(one_d_m, "source_k")),
        latex_values(competitor_values(one_d_m, "basis_k"))
      ),
      sprintf(
        "$n=%s$, $m=%s$, $k=%s$; qualitativo a $n=%s$",
        latex_values(dimension_values(two_d_n, "n_stat_units")),
        latex_values(dimension_values(two_d_n, "n_locs")),
        latex_values(dimension_values(two_d_n, "source_k")),
        plot_2d$representative_beta_setting_2d$n_stat_units
      )
    ),
    stringsAsFactors = FALSE
  )
  write.table(
    submitted_design,
    file.path(review_output_dir, "submitted_design.csv"),
    row.names = FALSE,
    quote = FALSE,
    sep = "|"
  )
}

format_number <- function(value) {
  if (abs(value - round(value)) < 1e-8) {
    sprintf("%d", round(value))
  } else {
    format(round(value, 2), trim = TRUE, scientific = FALSE)
  }
}

format_percent <- function(value) {
  number <- if (abs(value - round(value)) < 1e-8) {
    sprintf("%d", round(value))
  } else {
    sprintf("%.1f", value)
  }
  paste0(number, "\\%")
}

write_iteration_table <- function(suite, family) {
  diagnostics <- read.csv(
    aggregate_file(
      suite, family, sprintf("%s_diagnostics.csv", family)
    ),
    stringsAsFactors = FALSE
  )
  required <- c(
    "family", "diagnostic", "component", "level", "repetition", "model", "value"
  )
  if (any(!required %in% names(diagnostics))) {
    stop(sprintf("Invalid diagnostics schema for %s/%s", suite, family))
  }
  if (any(diagnostics$family != family)) {
    stop(sprintf("Diagnostics family mismatch for %s/%s", suite, family))
  }

  options <- load_family_options(suite, family)
  first <- options[[1]]
  n_comp <- first$model$n_comp
  n_reps <- first$test_options$n_reps
  if (n_comp != 4L) stop("The review iteration table expects four components")
  varying <- first$test_options$varying_options
  expected_levels <- option_values(options, function(option) {
    path <- find_name_path(option, varying)
    if (!isTRUE(path$found)) stop(sprintf("Missing varying option: %s", varying))
    get_by_path(option, path$path)
  })
  expected_cells <- expand.grid(
    component = seq_len(n_comp),
    level = expected_levels,
    repetition = seq_len(n_reps),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  cell_key <- function(rows) paste(
    rows$component,
    format(rows$level, scientific = TRUE, digits = 17, trim = TRUE),
    rows$repetition,
    sep = "|"
  )
  expected_keys <- sort(cell_key(expected_cells))
  required_diagnostic <- function(model_name, diagnostic_name) {
    rows <- diagnostics[
      diagnostics$diagnostic == diagnostic_name & diagnostics$model == model_name,
      , drop = FALSE
    ]
    keys <- cell_key(rows)
    if (nrow(rows) != nrow(expected_cells) || anyDuplicated(keys) ||
        !identical(sort(keys), expected_keys) || any(!is.finite(rows$value))) {
      stop(sprintf(
        "Incomplete %s diagnostics for %s/%s/%s",
        tolower(diagnostic_name), suite, family, model_name
      ))
    }
    rows
  }
  non_iterative_models <- c("MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS")

  rows <- lapply(seq_along(first$model_names), function(index) {
    model_name <- first$model_names[index]
    component_values <- rep("--", n_comp)
    monotone_value <- "--"
    if (!model_name %in% non_iterative_models) {
      iterations <- required_diagnostic(model_name, "Iteration count")
      if (any(iterations$value <= 0)) {
        stop(sprintf("Invalid iteration counts for %s/%s/%s", suite, family, model_name))
      }
      for (component in seq_len(n_comp)) {
        values <- iterations$value[iterations$component == component]
        component_values[component] <- format_number(median(values))
      }

      monotone <- required_diagnostic(model_name, "Monotonic fit")$value
      if (any(!monotone %in% c(0, 1))) {
        stop(sprintf("Invalid monotonicity diagnostics for %s/%s/%s", suite, family, model_name))
      }
      monotone_value <- format_percent(100 * mean(monotone))
    }

    data.frame(
      method = first$model_labels[index],
      h1 = component_values[1], h2 = component_values[2],
      h3 = component_values[3], h4 = component_values[4],
      monotone = monotone_value,
      stringsAsFactors = FALSE
    )
  })

  write.csv(
    do.call(rbind, rows),
    file.path(review_output_dir, sprintf("%s_%s_iterations.csv", suite, family)),
    row.names = FALSE,
    quote = FALSE
  )
}

iteration_tables <- list(
  c("1D", "vary_k"),
  c("1D", "vary_n"),
  c("1D", "vary_m"),
  c("2D", "vary_n"),
  c("2D", "vary_k")
)
if ("iterations" %in% sections) {
  for (spec in iteration_tables) write_iteration_table(spec[1], spec[2])
}

expected_csvs <- character()
if ("gcv" %in% sections) {
  expected_csvs <- c(expected_csvs, file.path(
    "gcv_tables",
    paste0(
      rep(c("sensitivity", "sensitivity_high_NSRX"), each = 6L), "_",
      rep(c(
        "Y_reconstruction", "X_reconstruction", "Beta",
        "X_direction", "X_loading", "X_scores"
      ), 2L),
      ".csv"
    )
  ))
}
if ("design" %in% sections) {
  expected_csvs <- c(expected_csvs, file.path("review_tables", "submitted_design.csv"))
}
if ("iterations" %in% sections) {
  expected_csvs <- c(expected_csvs, file.path(
    "review_tables",
    vapply(iteration_tables, function(spec) {
      sprintf("%s_%s_iterations.csv", spec[1], spec[2])
    }, character(1))
  ))
}
staged_csvs <- list.files(
  staging_dir, pattern = "[.]csv$", recursive = TRUE, full.names = FALSE
)
if (!identical(sort(staged_csvs), sort(expected_csvs))) {
  stop("Staged review-table CSV set is incomplete or unexpected")
}
commit_staged_csvs(expected_csvs)
message("Regenerated review-table sections: ", paste(sections, collapse = ", "), ".")
