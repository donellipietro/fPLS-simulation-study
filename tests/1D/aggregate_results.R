# = ========================================================================== =
# - Test: fPLS paper simulation 1D - aggregate results
# - Desc: Validates complete batches, writes metrics, and creates paper plots.
# - Args:
#   [1] name_main_test: one family or the grouped all target
# = ========================================================================== =

rm(list = ls())
graphics.off()

## Load libraries ----
invisible(suppressMessages(sapply(
  c("jsonlite", "ggplot2", "tidyr", "dplyr", "grid", "gridExtra"),
  require,
  character.only = TRUE
)))

## Load general and suite-specific functions ----
source("src/utils/cat.R")
source("src/utils/directories.R")
source("src/utils/options.R")
source("src/utils/load_results_utils.R")
source("src/utils/plotting_utils.R")
source("src/utils/diagnostic_plot_utils.R")
source("tests/1D/config.R")
source("tests/1D/utils/generate_options.R")
source("tests/1D/utils/models_evaluation.R")
source("tests/1D/utils/plot_qualitative_results.R")

validate_family_files <- function(path_list, family, family_options, cfg) {
  expected <- list()
  required_raw <- c(
    "params.json", "telemetry.json", "X.csv", "Y.csv", "locations.csv",
    "x_space_directions_coefficients.csv", "y_hat_h4.csv", "beta_evaluation_h4.csv"
  )

  for (options in family_options) {
    varying <- options$test_options$varying_options
    level <- as.numeric(resolve_option_value(varying, options))
    expected[[options$name_test]] <- data.frame(
      family = family,
      level = level,
      model = options$model_names,
      expected_repetitions = options$test_options$n_reps,
      stringsAsFactors = FALSE
    )

    for (batch_index in seq_len(options$test_options$n_reps)) {
      batch_dir <- file.path(path_list$results, family, options$name_test,
                             glue::glue("batch_{batch_index}"))
      data_file <- file.path(batch_dir, "generated_data.rds")
      evaluation_file <- file.path(
        batch_dir, glue::glue("batch_{batch_index}_results_evaluation.RData")
      )
      if (!file.exists(data_file) || !file.exists(evaluation_file)) {
        stop(glue::glue("incomplete batch files for {options$name_test}/batch_{batch_index}"))
      }
      data <- readRDS(data_file)
      if (data$noise$requested_NSR_X_final_component != 3 ||
          data$noise$requested_NSR_Y != 0.1) {
        stop("batch does not use the paper-facing severe-noise slice")
      }

      for (model_name in options$model_names) {
        model_file <- file.path(
          batch_dir,
          glue::glue("batch_{batch_index}_fitted_model_{model_name}.RData")
        )
        if (!file.exists(model_file)) stop(glue::glue("missing fitted model: {model_file}"))
        model <- load_fitted_model(model_file, model_name)
        if (length(model$results$Y_hat) != 4L ||
            length(model$results$X_hat_locations) != 4L ||
            length(model$results$Beta_locations) != 4L) {
          stop(glue::glue("invalid component-wise result shape for {model_name}"))
        }
        provenance <- model$results$provenance
        if (!provenance$metric_status %in% c(
              "provisional_submitted_paper_formula", "provisional_source_figure_metric"
            ) ||
            !identical(provenance$paper_design_complete, FALSE)) {
          stop(glue::glue("invalid provisional provenance for {model_name}"))
        }

        if (model_name == "R1_fPLS") {
          raw_dir <- model$results$raw_output_dir
          missing_raw <- required_raw[!file.exists(file.path(raw_dir, required_raw))]
          if (length(missing_raw)) stop("native raw output is incomplete")
          telemetry <- fromJSON(file.path(raw_dir, "telemetry.json"))
          if (!identical(telemetry$mode, "native_fdaPDE_cpp") ||
              !identical(telemetry$provenance$outer_branch, cfg$FDAPDE_CPP_BRANCH)) {
            stop("native telemetry provenance does not match the active profile")
          }
        }
      }
    }
  }
  do.call(rbind, expected)
}

## Select requested families ----
args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
if (any(!families %in% test_groups$all)) stop("unknown 1D fPLS experiment family")

cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
all_rows <- list()
all_completeness <- list()
all_diagnostics <- list()
diagnostic_outputs <- list()
qualitative_outputs <- list()
vary_k_limits <- list(
  Y_reconstruction = c(0.067, 0.145),
  X_reconstruction_locations = c(0.055, 0.14),
  Beta1_locations = c(0, 0.035)
)
metric_titles <- c(
  Y_reconstruction = "RMSE Y",
  X_reconstruction_locations = "RMSE X",
  Beta1_locations = "RMSE beta"
)

## Load, validate, and plot every family ----
for (family in families) {
  path_list <- create_paths(test_suite)
  path_list$queue <- config_path(path_list$queue, family)
  path_list$logs <- config_path(path_list$logs, family)
  mkdir(c(path_list$queue, path_list$logs))
  generate_options(test_suite, family, path_list$queue)

  option_files <- sort(list.files(path_list$queue, pattern = "[.]json$", full.names = TRUE))
  family_options <- lapply(option_files, fromJSON, simplifyVector = TRUE)
  expected <- validate_family_files(path_list, family, family_options, cfg)
  loaded <- load_all_quantitiative_results(path_list, family)
  if (is.null(loaded$submitted_normalized_rmse)) stop("submitted manuscript metric is missing")
  varying <- family_options[[1]]$test_options$varying_options
  if (!identical(loaded$varying_options, varying)) stop("loaded varying option mismatch")

  metrics <- c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations")
  final_component <- loaded$rmse$Y_reconstruction$Group == 4L
  family_rows <- do.call(rbind, lapply(metrics, function(metric) {
    table <- loaded$rmse[[metric]][final_component, , drop = FALSE]
    levels <- as.numeric(table[[varying]])
    repetitions <- ave(seq_along(levels), levels, FUN = seq_along)
    do.call(rbind, lapply(loaded$model_names, function(model_name) {
      data.frame(
        suite = test_suite, family = family, metric = metric, level = levels,
        repetition = repetitions, model = model_name, value = table[[model_name]],
        stringsAsFactors = FALSE
      )
    }))
  }))
  if (any(!is.finite(family_rows$value))) stop(glue::glue("non-finite metric in {family}"))

  primary <- family_rows[family_rows$metric == metrics[1], , drop = FALSE]
  counts <- aggregate(repetition ~ family + level + model, primary,
                      function(x) length(unique(x)))
  names(counts)[4] <- "completed_repetitions"
  completeness <- merge(expected, counts, all = TRUE)
  completeness$completed_repetitions[is.na(completeness$completed_repetitions)] <- 0L
  completeness$complete <- completeness$completed_repetitions == completeness$expected_repetitions
  if (nrow(completeness) != nrow(expected) || any(!completeness$complete)) {
    stop(glue::glue("incomplete 1D experiment family: {family}"))
  }

  all_rows[[family]] <- family_rows
  all_completeness[[family]] <- completeness
  write.csv(family_rows, file.path(aggregate_dir, glue::glue("{family}_paper_metrics.csv")),
            row.names = FALSE)
  saveRDS(loaded, file.path(aggregate_dir, glue::glue("loaded_{family}.rds")))

  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, family)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  lambda_limits <- list(
    direction_lambda = log10(range(family_options[[1]]$regularization$lambda_grid)),
    loading_lambda = log10(range(family_options[[1]]$regularization$lambda_grid)),
    pre_smoothing_lambda = log10(range(family_options[[1]]$competitors$smoothing_lambda_grid)),
    pb_penalty_lambda = log10(range(family_options[[1]]$competitors$pb_lambda_grid))
  )
  diagnostics <- write_family_diagnostics(
    loaded, family, aggregate_dir, image_dir, lambda_limits
  )
  all_diagnostics[[family]] <- diagnostics$rows
  diagnostic_outputs[[family]] <- diagnostics$plots

  ## Create the standard standalone model legend
  pdf(file.path(image_dir, "legend.pdf"), width = 14, height = 1.5, bg = "white")
  par(mar = rep(0, 4))
  plot.new()
  legend(
    "center",
    legend = loaded$model_labels,
    col = "black",
    pt.bg = loaded$model_colors,
    pch = 22,
    pt.cex = 1.5,
    horiz = TRUE,
    bty = "n"
  )
  dev.off()

  for (metric in metrics) {
    data_plot <- loaded$rmse[[metric]][final_component, , drop = FALSE]
    pdf(file.path(image_dir, glue::glue("{metric}.pdf")), width = 8, height = 5)
    plot.aggregated_data(
      loaded, data_plot, metric_titles[[metric]], "RMSE",
      limits = if (family == "vary_k") vary_k_limits[[metric]] else NULL,
      plots_catalog = list(
        boxplots = TRUE, lines = FALSE, logx = FALSE,
        loglog = FALSE, normalized = FALSE
      )
    )
    dev.off()
  }
  if (family == "vary_k") {
    qualitative_outputs$qualitative_beta <- plot_qualitative_beta_1d(
      path_list, family_options, image_dir
    )
  }
}

## Write validated aggregate outputs ----
results <- do.call(rbind, all_rows)
completeness <- do.call(rbind, all_completeness)
diagnostics <- do.call(rbind, all_diagnostics)
write.csv(results, file.path(aggregate_dir, "all_metrics.csv"), row.names = FALSE)
write.csv(completeness, file.path(aggregate_dir, "completeness.csv"), row.names = FALSE)
write.csv(diagnostics, file.path(aggregate_dir, "all_diagnostics.csv"), row.names = FALSE)
write_json(
  list(
    schema_version = 5L,
    suite = test_suite,
    requested = requested,
    families = families,
    run_complete = all(completeness$complete),
    smoke_test = SMOKE_TEST,
    paper_design_complete = FALSE,
    paper_results_reproduced = FALSE,
    design_blockers = c(
      "competitor_paper_description_precision",
      "basis_and_rng_semantics_acceptance",
      "final_metric_acceptance"
    ),
    diagnostic_outputs = diagnostic_outputs,
    qualitative_outputs = qualitative_outputs,
    competitors = paper_model_catalog()$names,
    NSR_X_final_component = 3,
    NSR_Y = 0.1,
    metric_status = "provisional_source_figure_metric",
    submitted_metric_status = "provisional_submitted_paper_formula",
    vary_k_display_limits = vary_k_limits
  ),
  file.path(aggregate_dir, "paper_run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat(glue::glue(
  "Validated {nrow(results)} metric rows across {nrow(completeness)} complete cells; ",
  "paper acceptance remains pending.\n",
  .trim = FALSE
))
