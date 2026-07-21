# = ========================================================================== =
# - Test: fPLS paper simulation 2D - aggregate results
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
source("tests/2D/config.R")
source("tests/2D/utils/generate_options.R")
source("tests/2D/utils/models_evaluation.R")
source("tests/2D/utils/plot_qualitative_results.R")

validate_family_files <- function(path_list, family, family_options, cfg) {
  expected <- list()
  for (options in family_options) {
    varying <- options$test_options$varying_options
    level <- as.numeric(resolve_option_value(varying, options))
    expected_levels <- if (family == "vary_H") seq_len(options$model$n_comp) else level
    expected[[options$name_test]] <- transform(
      expand.grid(
        level = expected_levels,
        model = options$model_names,
        stringsAsFactors = FALSE
      ),
      family = family,
      expected_repetitions = options$test_options$n_reps
    )
    expected[[options$name_test]] <- expected[[options$name_test]][
      c("family", "level", "model", "expected_repetitions")
    ]

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
      if (!grepl("NSR", family) &&
          (data$noise$requested_NSR_X_final_component != 3 ||
           any(data$noise$requested_NSR_Y != 0.1))) {
        stop("batch does not use the paper-facing severe-noise slice")
      }

      for (model_name in options$model_names) {
        model_file <- file.path(
          batch_dir,
          glue::glue("batch_{batch_index}_fitted_model_{model_name}.RData")
        )
        if (!file.exists(model_file)) stop(glue::glue("missing fitted model: {model_file}"))
        model <- load_fitted_model(model_file, model_name)
        if (length(model$results$Y_hat) != options$model$n_comp ||
            length(model$results$X_hat_locations) != options$model$n_comp ||
            length(model$results$Beta_locations) != options$model$n_comp) {
          stop(glue::glue("invalid component-wise result shape for {model_name}"))
        }
        if (model_name %in% c("R1_fPLS", "fPCR")) {
          raw_dir <- model$results$raw_output_dir
          n_comp <- options$model$n_comp
          required_raw <- c(
            "params.json", "telemetry.json", "X.csv", "Y.csv", "locations.csv",
            "x_space_directions_coefficients.csv",
            glue::glue("y_hat_h{n_comp}.csv"),
            glue::glue("beta_evaluation_h{n_comp}.csv"),
            "component_diagnostics.csv",
            paste0("objective_history_h", seq_len(n_comp), ".csv")
          )
          model_required_raw <- c(
            required_raw,
            if (model_name == "fPCR") "fpca_lambdas.csv" else character()
          )
          missing_raw <- model_required_raw[!file.exists(file.path(raw_dir, model_required_raw))]
          if (length(missing_raw)) stop("native raw output is incomplete")
          telemetry <- fromJSON(file.path(raw_dir, "telemetry.json"))
          if (!identical(telemetry$model, model_name) ||
              !identical(telemetry$mode, "native_fdaPDE_cpp") ||
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
if (any(!families %in% test_groups$all)) stop("unknown 2D fPLS experiment family")

cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
all_rows <- list()
all_completeness <- list()
all_diagnostics <- list()
diagnostic_outputs <- list()
qualitative_outputs <- list()

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
  varying <- family_options[[1]]$test_options$varying_options
  if (!identical(loaded$varying_options, varying)) stop("loaded varying option mismatch")

  if (family == "vary_H") {
    for (metric in names(loaded$rmse)) {
      loaded$rmse[[metric]]$n_comp <- as.integer(as.character(loaded$rmse[[metric]]$Group))
      loaded$rmse[[metric]]$Group <- 1L
    }
    for (name in c(
      "iteration_count", "monotone", "objective",
      "hit_max_iter", "finite_solution",
      "direction_lambda", "loading_lambda", "fpca_lambda"
    )) {
      loaded[[name]]$n_comp <- as.integer(as.character(loaded[[name]]$Group))
      loaded[[name]]$Group <- 1L
    }
  }

  metrics <- c(
    if (family == "vary_H") "Y_reconstruction" else character(),
    "X_reconstruction_locations", "Beta1_locations", "Beta2_locations"
  )
  final_component <- if (family == "vary_H") {
    rep(TRUE, nrow(loaded$rmse$Y_reconstruction))
  } else {
    loaded$rmse$Y_reconstruction$Group == 4L
  }
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
    stop(glue::glue("incomplete 2D experiment family: {family}"))
  }

  all_rows[[family]] <- family_rows
  all_completeness[[family]] <- completeness
  write.csv(family_rows, file.path(aggregate_dir, glue::glue("{family}_paper_metrics.csv")),
            row.names = FALSE)
  saveRDS(loaded, file.path(aggregate_dir, glue::glue("loaded_{family}.rds")))

  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, family)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  diagnostics <- write_family_diagnostics(loaded, family, aggregate_dir, image_dir)
  all_diagnostics[[family]] <- diagnostics$rows
  diagnostic_outputs[[family]] <- diagnostics$plots

  ## Create the standard standalone model legend
  pdf(file.path(image_dir, "legend.pdf"), width = 6, height = 1.5, bg = "white")
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
      loaded, data_plot, glue::glue("2D: {family}"), "RMSE",
      plots_catalog = list(
        boxplots = TRUE, lines = FALSE, logx = FALSE,
        loglog = FALSE, normalized = FALSE
      )
    )
    dev.off()
  }
  if (family == "vary_n") {
    qualitative_outputs$representative_beta <- plot_representative_beta_2d(
      path_list, family_options, image_dir
    )
  }
}

## Write aggregate outputs ----
results <- do.call(rbind, all_rows)
completeness <- do.call(rbind, all_completeness)
diagnostics <- do.call(rbind, all_diagnostics)
write.csv(results, file.path(aggregate_dir, "all_metrics.csv"), row.names = FALSE)
write.csv(completeness, file.path(aggregate_dir, "completeness.csv"), row.names = FALSE)
write.csv(diagnostics, file.path(aggregate_dir, "all_diagnostics.csv"), row.names = FALSE)
write_json(
  list(
    schema_version = 7L,
    suite = test_suite,
    requested = requested,
    families = families,
    run_complete = all(completeness$complete),
    smoke_test = SMOKE_TEST,
    diagnostic_outputs = diagnostic_outputs,
    qualitative_outputs = qualitative_outputs,
    competitors = paper_model_catalog()$names,
    NSR_X_final_component = 3,
    NSR_Y = 0.1
  ),
  file.path(aggregate_dir, "run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat(glue::glue(
  "Wrote {nrow(results)} metric rows across {nrow(completeness)} complete cells.\n",
  .trim = FALSE
))
