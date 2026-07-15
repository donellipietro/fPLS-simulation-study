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
source("tests/2D/config.R")
source("tests/2D/utils/generate_options.R")
source("tests/2D/utils/plot_qualitative_results.R")

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
          any(data$noise$requested_NSR_Y != 0.1)) {
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
        if (!identical(provenance$metric_status, "provisional_submitted_paper_formula") ||
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
if (any(!families %in% test_groups$all)) stop("unknown 2D fPLS experiment family")

cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
all_rows <- list()
all_completeness <- list()
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

  metrics <- c("X_reconstruction_locations", "Beta1_locations", "Beta2_locations")
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
    stop(glue::glue("incomplete 2D experiment family: {family}"))
  }

  all_rows[[family]] <- family_rows
  all_completeness[[family]] <- completeness
  write.csv(family_rows, file.path(aggregate_dir, glue::glue("{family}_paper_metrics.csv")),
            row.names = FALSE)
  saveRDS(loaded, file.path(aggregate_dir, glue::glue("loaded_{family}.rds")))

  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, family)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)

  ## Create the standard standalone model legend
  pdf(file.path(image_dir, "legend.pdf"), width = 6, height = 1.5, bg = "white")
  par(mar = rep(0, 4))
  plot.new()
  legend(
    "center",
    legend = loaded$model_labels,
    col = loaded$model_colors,
    lty = 1,
    lwd = 2,
    pch = 15,
    pt.cex = 1.5,
    horiz = TRUE,
    bty = "n"
  )
  dev.off()

  for (metric in metrics) {
    data_plot <- loaded$rmse[[metric]][final_component, , drop = FALSE]
    pdf(file.path(image_dir, glue::glue("{metric}.pdf")), width = 8, height = 5)
    plot.aggregated_data(
      loaded, data_plot, glue::glue("2D: {family}"),
      "Provisional submitted-paper normalized RMSE",
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

## Write validated aggregate outputs ----
results <- do.call(rbind, all_rows)
completeness <- do.call(rbind, all_completeness)
write.csv(results, file.path(aggregate_dir, "all_metrics.csv"), row.names = FALSE)
write.csv(completeness, file.path(aggregate_dir, "completeness.csv"), row.names = FALSE)
write_json(
  list(
    schema_version = 3L,
    suite = test_suite,
    requested = requested,
    families = families,
    run_complete = all(completeness$complete),
    smoke_test = SMOKE_TEST,
    paper_design_complete = FALSE,
    paper_results_reproduced = FALSE,
    family_scope = setNames(
      ifelse(families == "vary_n", "submitted_main_paper_family", "pietro_requested_historical_family"),
      families
    ),
    design_blockers = c(
      "comparator_implementation_acceptance",
      "basis_and_rng_semantics_acceptance",
      "final_metric_acceptance"
    ),
    qualitative_outputs = qualitative_outputs,
    competitors = paper_model_catalog()$names,
    NSR_X_final_component = 3,
    NSR_Y = 0.1,
    metric_status = "provisional_submitted_paper_formula"
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
