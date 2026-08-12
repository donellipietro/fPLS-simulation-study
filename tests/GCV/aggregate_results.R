# = ========================================================================== =
# - Test: fPLS GCV diagnostics - aggregate results
# - Desc: Validates complete batches and creates diagnostic plots and tables.
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
source("tests/GCV/config.R")
source("tests/GCV/utils/generate_options.R")

## Select requested families ----
args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
if (any(!families %in% test_groups$all)) stop("unknown GCV diagnostic family")

cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
all_diagnostics <- list()
diagnostic_outputs <- list()

## Load, validate, and plot every family ----
for (family in families) {
  path_list <- create_paths(test_suite)
  path_list$queue <- config_path(path_list$queue, family)
  path_list$logs <- config_path(path_list$logs, family)
  mkdir(c(path_list$queue, path_list$logs))
  generate_options(test_suite, family, path_list$queue)

  option_files <- sort(list.files(path_list$queue, pattern = "[.]json$", full.names = TRUE))
  family_options <- lapply(option_files, fromJSON, simplifyVector = TRUE)
  for (options in family_options) {
    for (batch_index in seq_len(options$test_options$n_reps)) {
      batch_dir <- file.path(
        path_list$results, family, options$name_test, glue::glue("batch_{batch_index}")
      )
      required <- c(
        "generated_data.rds",
        glue::glue(
          "batch_{batch_index}_fitted_model_{options$model_names}.RData"
        ),
        glue::glue("batch_{batch_index}_results_evaluation.RData")
      )
      if (any(!file.exists(file.path(batch_dir, required)))) {
        stop(glue::glue("incomplete batch files for {options$name_test}/batch_{batch_index}"))
      }
      model_file <- file.path(
        batch_dir,
        glue::glue("batch_{batch_index}_fitted_model_R1_fPLS.RData")
      )
      load(model_file)
      model <- model_R1_fPLS
      if (identical(options$regularization$calibration, "multivariate")) {
        if (!identical(model$MODE, "MV_PLS")) stop("lambda = 0 must use MV-PLS")
      } else {
        raw_dir <- model$results$raw_output_dir
        raw_required <- c(
          "params.json", "telemetry.json", "component_diagnostics.csv",
          "direction_lambdas.csv", "loading_lambdas.csv",
          paste0("objective_history_h", seq_len(options$model$n_comp), ".csv")
        )
        if (any(!file.exists(file.path(raw_dir, raw_required)))) {
          stop(glue::glue("incomplete native diagnostics for {options$name_test}/batch_{batch_index}"))
        }
        telemetry <- fromJSON(file.path(raw_dir, "telemetry.json"))
        if (!identical(telemetry$schema_version, 4L) ||
            !identical(telemetry$model, "R1_fPLS") ||
            !identical(telemetry$mode, "native_fdaPDE_cpp") ||
            !identical(telemetry$calibration, options$regularization$calibration) ||
            telemetry$max_iter != 1000L || telemetry$tolerance != 1e-8) {
          stop("native diagnostic settings do not match the GCV suite")
        }
        if (!isTRUE(all.equal(
          as.numeric(telemetry$lambda_grid), options$regularization$lambda_grid
        ))) stop("native lambda grid does not match the GCV suite")
        if (identical(telemetry$calibration, "fixed") &&
            (!isTRUE(all.equal(
              telemetry$fixed_direction_lambda,
              options$regularization$fixed_direction_lambda
            )) || !isTRUE(all.equal(
              telemetry$fixed_loading_lambda,
              options$regularization$fixed_loading_lambda
            )))) {
          stop("native fixed lambda does not match the requested level")
        }
        if (identical(telemetry$calibration, "fixed")) {
          expected_direction <- as.numeric(options$regularization$fixed_direction_lambda)
          expected_loading <- as.numeric(options$regularization$fixed_loading_lambda)
          if (!length(expected_direction) %in% c(1L, options$model$n_comp) ||
              !length(expected_loading) %in% c(1L, options$model$n_comp)) {
            stop("fixed lambda schedule must be scalar or component-wise")
          }
          if (length(expected_direction) == 1L) {
            expected_direction <- rep(expected_direction, options$model$n_comp)
          }
          if (length(expected_loading) == 1L) {
            expected_loading <- rep(expected_loading, options$model$n_comp)
          }
          actual_direction <- as.numeric(as.matrix(suppressWarnings(read.csv(
            file.path(raw_dir, "direction_lambdas.csv"), check.names = FALSE
          ))))
          actual_loading <- as.numeric(as.matrix(suppressWarnings(read.csv(
            file.path(raw_dir, "loading_lambdas.csv"), check.names = FALSE
          ))))
          if (!isTRUE(all.equal(actual_direction, expected_direction)) ||
              !isTRUE(all.equal(actual_loading, expected_loading))) {
            stop("native fixed lambda schedule does not match the requested components")
          }
        }
      }
    }
  }

  loaded <- load_all_quantitiative_results(path_list, family)
  saveRDS(loaded, file.path(aggregate_dir, glue::glue("loaded_{family}.rds")))
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, family)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  prefix_sensitivity <- family %in% c(
    "sensitivity", "sensitivity_high_NSRX"
  )

  near_zero_family <- startsWith(family, "small_lambda")
  near_zero_breaks <- if (identical(family, "small_lambda_m_lt_k")) {
    c(-300, -200, -100, -50, -40, -30, -20, -9)
  } else {
    c(-300, -200, -100, -50, -20, -9)
  }
  diagnostics <- write_family_diagnostics(
    loaded, family, aggregate_dir, image_dir,
    lambda_limits = if (near_zero_family) c(-300, -9) else lambda_log10_limits,
    lambda_breaks = if (near_zero_family) near_zero_breaks else lambda_log10_grid
  )
  all_diagnostics[[family]] <- diagnostics$rows
  diagnostic_outputs[[family]] <- diagnostics$plots


  plot_specs <- if (prefix_sensitivity) {
    data.frame(
      metric = c(
        "Y_reconstruction", "X_reconstruction_locations", "Beta_locations",
        "X_direction_locations", "X_loading_locations", "X_latent_scores"
      ),
      source = c("rmse", "rmse", rep("cosine", 4L)),
      value_label = c(
        rep("RMSE", 2L), "Signed cosine similarity",
        rep("Absolute cosine similarity", 3L)
      ),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      metric = c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations"),
      source = "rmse",
      value_label = "RMSE",
      stringsAsFactors = FALSE
    )
  }
  if (prefix_sensitivity &&
      (is.null(loaded$truth_target$R1_fPLS) ||
       any(loaded$truth_target$R1_fPLS != "prefix"))) {
    stop("one-lambda sensitivity metrics must use prefix truth")
  }
  plot_data <- lapply(seq_len(nrow(plot_specs)), function(i) {
    spec <- plot_specs[i, ]
    value <- loaded[[spec$source]][[spec$metric]]
    if (is.null(value)) {
      stop(glue::glue("missing aggregate metric: {spec$source}${spec$metric}"))
    }
    value
  })
  for (i in seq_len(nrow(plot_specs))) {
    spec <- plot_specs[i, ]
    pdf(file.path(image_dir, glue::glue("{spec$metric}.pdf")), width = 10, height = 5)
    plot.aggregated_data(
      loaded, plot_data[[i]], family, spec$value_label,
      plots_catalog = list(
        boxplots = TRUE, lines = FALSE, logx = FALSE,
        loglog = FALSE, normalized = FALSE
      )
    )
    dev.off()
  }
  if (prefix_sensitivity) {
    unlink(file.path(image_dir, "Beta1_locations.pdf"))
  }

  pdf(
    file.path(image_dir, "legend.pdf"),
    width = max(4, 2.8 * length(loaded$model_labels)), height = 1.5, bg = "white"
  )
  par(mar = rep(0, 4))
  plot.new()
  legend(
    "center", legend = loaded$model_labels, col = "black",
    pt.bg = loaded$model_colors, pch = 22, pt.cex = 1.5,
    horiz = TRUE, bty = "n"
  )
  dev.off()
}

diagnostics <- dplyr::bind_rows(all_diagnostics)
write.csv(diagnostics, file.path(aggregate_dir, "all_diagnostics.csv"), row.names = FALSE)
write_json(
  list(
    schema_version = 5L,
    suite = test_suite,
    requested = requested,
    families = families,
    run_complete = TRUE,
    smoke_test = SMOKE_TEST,
    tolerance = 1e-8,
    max_iter = 1000L,
    gcv_seed = 0L,
    diagnostic_outputs = diagnostic_outputs,
    sensitivity_lambda_grid = c(-1, 0, sensitivity_lambda_grid),
    sensitivity_NSR_X = c(baseline = 3, challenging = 10),
    near_zero_m_gt_k_lambda_grid = 10^c(-300, -200, -100, -50, -30, -20:-9),
    near_zero_m_lt_k_lambda_grid = 10^c(
      -300, -200, -100, seq(-50, -30, by = 2), -20:-9
    )
  ),
  file.path(aggregate_dir, "run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat(glue::glue("Aggregated {length(families)} complete GCV diagnostic families.\n"))
