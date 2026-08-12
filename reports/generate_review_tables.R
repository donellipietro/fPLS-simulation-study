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
gcv_output_dir <- file.path("reports", "gcv_tables")
review_output_dir <- file.path("reports", "review_tables")
sections <- commandArgs(trailingOnly = TRUE)
available_sections <- c("gcv", "design", "iterations")
if (!length(sections)) sections <- available_sections
unknown_sections <- setdiff(sections, available_sections)
if (length(unknown_sections)) {
  stop("Unknown review-table section: ", paste(unknown_sections, collapse = ", "))
}
dir.create(gcv_output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(review_output_dir, recursive = TRUE, showWarnings = FALSE)

latest_existing_file <- function(candidates, description) {
  existing <- candidates[file.exists(candidates)]
  if (!length(existing)) {
    stop(paste(
      "Missing", description, "from every supported aggregate target:\n ",
      paste(candidates, collapse = "\n  ")
    ))
  }
  selected <- existing[which.max(file.info(existing)$mtime)]
  message("Using ", selected)
  selected
}

aggregate_file <- function(suite, family, filename, groups = character()) {
  targets <- unique(c("all", groups, family))
  latest_existing_file(
    file.path(results_dir, suite, "aggregate", targets, filename),
    sprintf("%s/%s aggregate %s", suite, family, filename)
  )
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

validate_gcv_metric <- function(data, label) {
  required <- c("Group", "lambda", "R1_fPLS")
  if (is.null(data) || any(!required %in% names(data))) {
    stop(sprintf("Missing GCV table input: %s", label))
  }
  groups <- sort(unique(as.integer(as.character(data$Group))))
  counts <- aggregate(
    data$R1_fPLS,
    list(component = data$Group, lambda = data$lambda),
    length
  )
  if (!identical(groups, 1:4) || any(!is.finite(data$R1_fPLS)) ||
      any(counts$x != 30L)) {
    stop(sprintf("GCV table input is incomplete or non-production: %s", label))
  }
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
  required <- c("diagnostic", "component", "model", "value")
  if (any(!required %in% names(diagnostics))) {
    stop(sprintf("Invalid diagnostics schema for %s/%s", suite, family))
  }

  options <- load_family_options(suite, family)
  first <- options[[1]]
  n_comp <- first$model$n_comp
  n_reps <- first$test_options$n_reps
  expected_per_component <- length(options) * n_reps
  if (n_comp != 4L) stop("The review iteration table expects four components")

  rows <- lapply(seq_along(first$model_names), function(index) {
    model_name <- first$model_names[index]
    iterations <- diagnostics[
      diagnostics$diagnostic == "Iteration count" & diagnostics$model == model_name,
      , drop = FALSE
    ]
    finite_iterations <- iterations[is.finite(iterations$value), , drop = FALSE]
    has_iterations <- nrow(finite_iterations) && any(finite_iterations$value > 0)

    component_values <- rep("--", n_comp)
    monotone_value <- "--"
    if (has_iterations) {
      for (component in seq_len(n_comp)) {
        values <- finite_iterations$value[finite_iterations$component == component]
        if (length(values) != expected_per_component || any(values <= 0)) {
          stop(sprintf(
            "Incomplete iteration diagnostics for %s/%s/%s component %d",
            suite, family, model_name, component
          ))
        }
        component_values[component] <- format_number(median(values))
      }

      monotone <- diagnostics[
        diagnostics$diagnostic == "Monotonic fit" & diagnostics$model == model_name,
        "value"
      ]
      monotone <- monotone[is.finite(monotone)]
      if (length(monotone) != expected_per_component * n_comp ||
          any(!monotone %in% c(0, 1))) {
        stop(sprintf("Incomplete monotonicity diagnostics for %s/%s/%s", suite, family, model_name))
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

message("Regenerated review-table sections: ", paste(sections, collapse = ", "), ".")
