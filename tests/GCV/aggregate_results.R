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
source("src/utils/test_groups.R")
source("src/utils/load_results_utils.R")
source("src/utils/plotting_utils.R")
source("src/utils/diagnostic_plot_utils.R")
source("tests/GCV/config.R")
source("tests/GCV/generate_options.R")
source("tests/1D/utils/models_evaluation.R")

## Select requested families ----
args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
# aggregate grouped requests through the same per-test path used by individual runs
aggregate_test_group(test_suite, requested)
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
if (any(!families %in% test_groups$all)) stop("unknown GCV diagnostic family")

cfg <- load_config()
aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
status_file <- file.path(aggregate_dir, "run_status.json")
if (file.exists(status_file) && unlink(status_file) != 0L) {
  stop("cannot invalidate the previous GCV run status")
}
staging_dir <- tempfile(".aggregate_staging_", tmpdir = aggregate_dir)
dir.create(staging_dir)
on.exit(unlink(staging_dir, recursive = TRUE), add = TRUE)
all_diagnostics <- list()
diagnostic_outputs <- list()

validate_sensitivity_metric <- function(
    data, family_options, metric, lower = -Inf, upper = Inf) {
  if (is.null(data)) stop(glue::glue("missing sensitivity metric: {metric}"))

  n_comp <- family_options[[1]]$model$n_comp
  n_reps <- family_options[[1]]$test_options$n_reps
  expected_rows <- length(family_options) * n_comp * n_reps
  if (nrow(data) != expected_rows ||
      !identical(sort(unique(as.integer(data$Group))), seq_len(n_comp))) {
    stop(glue::glue("incomplete sensitivity metric: {metric}"))
  }

  counts <- aggregate(
    data$R1_fPLS,
    list(component = data$Group, lambda = data$lambda),
    length
  )
  values <- data$R1_fPLS
  if (nrow(counts) != length(family_options) * n_comp ||
      any(counts$x != n_reps) || any(!is.finite(values)) ||
      any(values < lower) || any(values > upper)) {
    stop(glue::glue("invalid sensitivity metric: {metric}"))
  }
}

validate_sensitivity_metrics <- function(loaded, family_options) {
  validate_sensitivity_metric(
    loaded$rmse$Y_reconstruction, family_options, "Y reconstruction RMSE", 0
  )
  validate_sensitivity_metric(
    loaded$rmse$X_reconstruction_locations,
    family_options, "X reconstruction RMSE", 0
  )
  validate_sensitivity_metric(
    loaded$rmse$Beta1_locations, family_options, "beta shape RMSE", 0
  )
  validate_sensitivity_metric(
    loaded$cosine$Beta_locations,
    family_options, "signed beta cosine", -1, 1
  )
  for (metric in c(
    "X_direction_locations", "X_loading_locations", "X_latent_scores"
  )) {
    validate_sensitivity_metric(
      loaded$cosine[[metric]], family_options, metric, 0, 1
    )
  }
}

validate_gcv_curves <- function(raw_dir, options) {
  expected_lambda <- as.numeric(options$regularization$lambda_grid)
  for (prefix in c("direction", "loading")) {
    for (component in seq_len(options$model$n_comp)) {
      curve <- suppressWarnings(read.csv(
        file.path(raw_dir, glue::glue("{prefix}_gcv_h{component}.csv")),
        check.names = FALSE
      ))
      if (!identical(names(curve), c("lambda", "edf", "gcv", "selected_by_fit")) ||
          nrow(curve) != length(expected_lambda) ||
          !isTRUE(all.equal(curve$lambda, expected_lambda)) ||
          any(!is.finite(curve$gcv)) || any(!is.finite(curve$edf)) ||
          any(!curve$selected_by_fit %in% c(0, 1)) || sum(curve$selected_by_fit) != 1L ||
          which(curve$selected_by_fit == 1L) != which.min(curve$gcv)) {
        stop(glue::glue("invalid {prefix} GCV curve for component {component}"))
      }
    }
  }
}

load_gcv_curves <- function(path_list, family, options) {
  if (!identical(options$regularization$calibration, "gcv")) {
    return(data.frame())
  }

  curves <- list()
  index <- 1L
  for (batch_index in seq_len(options$test_options$n_reps)) {
    raw_dir <- file.path(
      path_list$results, family, options$name_test,
      glue::glue("batch_{batch_index}"), "raw", "R1_fPLS"
    )
    for (update in c("direction", "loading")) {
      for (component in seq_len(options$model$n_comp)) {
        curve <- read.csv(
          file.path(raw_dir, glue::glue("{update}_gcv_h{component}.csv")),
          check.names = FALSE
        )
        curves[[index]] <- transform(
          curve,
          batch = batch_index,
          update = update,
          component = factor(component, levels = seq_len(options$model$n_comp))
        )
        index <- index + 1L
      }
    }
  }
  dplyr::bind_rows(curves)
}

write_gcv_curve_plots <- function(curves, image_dir, name_test) {
  if (!nrow(curves)) return(character())

  summary <- curves |>
    dplyr::group_by(update, component, lambda) |>
    dplyr::summarise(
      median_gcv = median(gcv),
      lower_gcv = quantile(gcv, 0.25),
      upper_gcv = quantile(gcv, 0.75),
      .groups = "drop"
    )

  output_files <- character()
  for (update in c("direction", "loading")) {
    plot_data <- dplyr::filter(summary, .data$update == update)
    output_file <- file.path(
      image_dir, glue::glue("{name_test}_{update}_gcv_curves.pdf")
    )
    plot <- ggplot(plot_data, aes(x = lambda, y = median_gcv)) +
      geom_ribbon(
        aes(ymin = lower_gcv, ymax = upper_gcv),
        fill = "#377EB8", alpha = 0.22
      ) +
      geom_line(colour = "#377EB8", linewidth = 0.6) +
      geom_point(colour = "#377EB8", size = 1.5) +
      scale_x_log10() +
      facet_wrap(~ component, scales = "free_y", nrow = 1L) +
      labs(
        x = expression(lambda),
        y = "GCV criterion",
        title = paste("GCV curves for", update, "updates")
      ) +
      theme_bw(base_size = 10) +
      theme(plot.title = element_text(hjust = 0.5, face = "bold"))
    ggsave(output_file, plot, width = 9, height = 3, units = "in")
    output_files <- c(output_files, output_file)
  }
  output_files
}

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
        raw_dir <- file.path(batch_dir, "raw", "R1_fPLS")
        raw_required <- c(
          "params.json", "telemetry.json", "component_diagnostics.csv",
          "direction_lambdas.csv", "loading_lambdas.csv",
          paste0("objective_history_h", seq_len(options$model$n_comp), ".csv")
        )
        if (identical(options$regularization$calibration, "gcv")) {
          raw_required <- c(
            raw_required,
            paste0("direction_gcv_h", seq_len(options$model$n_comp), ".csv"),
            paste0("loading_gcv_h", seq_len(options$model$n_comp), ".csv")
          )
        }
        if (any(!file.exists(file.path(raw_dir, raw_required)))) {
          stop(glue::glue("incomplete native diagnostics for {options$name_test}/batch_{batch_index}"))
        }
        if (identical(options$regularization$calibration, "gcv")) {
          validate_gcv_curves(raw_dir, options)
        }
        telemetry <- fromJSON(file.path(raw_dir, "telemetry.json"))
        saves_gcv_curves <- identical(options$regularization$calibration, "gcv")
        expected_schema <- if (saves_gcv_curves) 6L else 4L
        gcv_curve_setting_current <- if (saves_gcv_curves) {
          identical(telemetry$save_gcv_curves, TRUE)
        } else {
          is.null(telemetry$save_gcv_curves) || identical(telemetry$save_gcv_curves, FALSE)
        }
        if (!identical(telemetry$schema_version, expected_schema) ||
            !identical(telemetry$model, "R1_fPLS") ||
            !identical(telemetry$mode, "native_fdaPDE_cpp") ||
            !identical(telemetry$calibration, options$regularization$calibration) ||
            !gcv_curve_setting_current ||
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
  image_dir <- file.path(cfg$PATH_IMAGES, test_suite, family)
  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  prefix_sensitivity <- family %in% sensitivity_families

  near_zero_family <- startsWith(family, "small_lambda")
  near_zero_breaks <- if (identical(family, "small_lambda_m_lt_k")) {
    c(-300, -200, -100, -50, -40, -30, -20, -9)
  } else {
    c(-300, -200, -100, -50, -20, -9)
  }
  diagnostics <- write_family_diagnostics(
    loaded, family, aggregate_dir, image_dir,
    lambda_limits = if (near_zero_family) c(-300, -9) else lambda_log10_limits,
    lambda_breaks = if (near_zero_family) near_zero_breaks else lambda_log10_grid,
    fit_time_median_lines = !prefix_sensitivity
  )
  all_diagnostics[[family]] <- diagnostics$rows
  diagnostic_outputs[[family]] <- diagnostics$plots

  gcv_curve_outputs <- unlist(lapply(
    family_options,
    function(options) {
      write_gcv_curve_plots(
        load_gcv_curves(path_list, family, options), image_dir, options$name_test
      )
    }
  ), use.names = FALSE)
  diagnostic_outputs[[family]]$gcv_curves <- gcv_curve_outputs

  plot_specs <- if (prefix_sensitivity) {
    validate_sensitivity_metrics(loaded, family_options)
    data.frame(
      metric = c(
        "Y_reconstruction", "X_reconstruction_locations", "Beta1_locations",
        "Beta_locations", "X_direction_locations", "X_loading_locations",
        "X_latent_scores"
      ),
      source = c(rep("rmse", 3L), rep("cosine", 4L)),
      value_label = c(
        rep("RMSE", 3L), "Signed cosine similarity",
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

  # Stage only after every metric and plot for this family has validated.
  saveRDS(loaded, file.path(staging_dir, glue::glue("loaded_{family}.rds")))
}

diagnostics <- dplyr::bind_rows(all_diagnostics)
write.csv(diagnostics, file.path(aggregate_dir, "all_diagnostics.csv"), row.names = FALSE)
staged_status <- file.path(staging_dir, "run_status.json")
write_json(
  list(
    schema_version = 6L,
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
  staged_status,
  auto_unbox = TRUE,
  pretty = TRUE
)
for (family in families) {
  destination <- file.path(aggregate_dir, glue::glue("loaded_{family}.rds"))
  staged <- file.path(staging_dir, glue::glue("loaded_{family}.rds"))
  if (file.exists(destination) && unlink(destination) != 0L) {
    stop(glue::glue("cannot replace the previous GCV aggregate: {destination}"))
  }
  if (!file.rename(staged, destination)) {
    stop(glue::glue("cannot publish validated GCV aggregate: {destination}"))
  }
}
if (!file.rename(staged_status, status_file)) {
  stop("cannot publish the validated GCV run status")
}
cat(glue::glue("Aggregated {length(families)} complete GCV diagnostic families.\n"))
