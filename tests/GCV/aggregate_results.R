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
componentwise_outputs <- list()

componentwise_diagnostic_rows <- function(loaded, family) {
  labels <- c(
    fit_seconds = "Fit time (s)",
    peak_ram_mib = "Peak RAM (MiB)",
    iteration_count = "Iteration count",
    monotone = "Monotonic fit",
    hit_max_iter = "Reached iteration cap",
    finite_solution = "Finite solution",
    objective = "Final objective",
    direction_lambda = "Direction lambda",
    loading_lambda = "Loading lambda",
    fpca_lambda = "fPCA lambda",
    pre_smoothing_lambda = "B-fPLS smoothing lambda",
    pb_penalty_lambda = "PB-fPLS penalty lambda"
  )
  component_fields <- c(
    "iteration_count", "monotone", "hit_max_iter", "finite_solution",
    "objective", "direction_lambda", "loading_lambda", "fpca_lambda"
  )
  rows <- lapply(names(labels), function(name) {
    table <- loaded[[name]]
    if (is.null(table)) return(NULL)
    repetitions <- ave(
      seq_len(nrow(table)), table$Group, table$lambda_1, table$lambda_2,
      FUN = seq_along
    )
    do.call(rbind, lapply(loaded$model_names, function(model_name) {
      data.frame(
        family = family,
        diagnostic = labels[[name]],
        component = if (name %in% component_fields) {
          as.integer(as.character(table$Group))
        } else {
          NA_integer_
        },
        level = as.numeric(table$lambda_1),
        lambda_2 = as.numeric(table$lambda_2),
        repetition = as.integer(repetitions),
        model = model_name,
        value = as.numeric(table[[model_name]]),
        stringsAsFactors = FALSE
      )
    }))
  })
  do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
}

write_componentwise_diagnostics <- function(loaded, family, aggregate_dir, image_dir) {
  labels <- c(
    fit_seconds = "Fit time (s)",
    peak_ram_mib = "Peak RAM (MiB)",
    iteration_count = "Iteration count",
    monotone = "Monotonic fit",
    hit_max_iter = "Reached iteration cap",
    finite_solution = "Finite solution",
    objective = "Final objective",
    direction_lambda = "Direction lambda",
    loading_lambda = "Loading lambda",
    fpca_lambda = "fPCA lambda",
    pre_smoothing_lambda = "B-fPLS smoothing lambda",
    pb_penalty_lambda = "PB-fPLS penalty lambda"
  )
  rows <- componentwise_diagnostic_rows(loaded, family)
  write.csv(
    rows,
    file.path(aggregate_dir, glue::glue("{family}_diagnostics.csv")),
    row.names = FALSE
  )

  plot_status <- setNames(as.list(rep(FALSE, length(labels))), names(labels))
  lambda_diagnostics <- c(
    "direction_lambda", "loading_lambda", "fpca_lambda",
    "pre_smoothing_lambda", "pb_penalty_lambda"
  )
  for (name in names(labels)) {
    plot_rows <- rows[rows$diagnostic == labels[[name]] & is.finite(rows$value), ]
    if (!nrow(plot_rows)) next
    value_label <- labels[[name]]
    if (name %in% lambda_diagnostics) {
      plot_rows <- plot_rows[plot_rows$value > 0, ]
      if (!nrow(plot_rows)) next
      plot_rows$value <- log10(plot_rows$value)
      value_label <- "log10(lambda)"
    }

    fixed_rows <- plot_rows[plot_rows$level > 0 & plot_rows$lambda_2 > 0, ]
    selector_rows <- plot_rows[plot_rows$level <= 0 & plot_rows$lambda_2 <= 0, ]
    fixed_summary <- aggregate(
      value ~ component + level + lambda_2,
      transform(fixed_rows, component = ifelse(is.na(component), 0L, component)),
      median
    )
    fixed_summary$component <- ifelse(
      fixed_summary$component == 0L, "all", paste0("h = ", fixed_summary$component)
    )
    fixed_plot <- ggplot(
      fixed_summary,
      aes(x = log10(level), y = log10(lambda_2), fill = value)
    ) +
      geom_tile(color = "grey90") +
      facet_wrap(~component) +
      coord_fixed() +
      labs(
        title = "Fixed schedules",
        x = "log10(component-1 lambda)",
        y = "log10(component-2 lambda)", fill = value_label
      ) +
      std_plot_settings() +
      theme(legend.position = "right")

    selector_rows$selector <- factor(
      ifelse(selector_rows$level == -1, "GCV", "MV-PLS"),
      levels = c("GCV", "MV-PLS")
    )
    selector_rows$component <- ifelse(
      is.na(selector_rows$component), "all", paste0("h = ", selector_rows$component)
    )
    selector_plot <- ggplot(selector_rows, aes(x = selector, y = value)) +
      geom_jitter(width = 0.08, height = 0, alpha = 0.45) +
      stat_summary(fun = median, geom = "point", shape = 18, size = 3) +
      facet_wrap(~component) +
      labs(title = "Native selectors", x = NULL, y = value_label) +
      std_plot_settings()

    plot_file <- file.path(image_dir, glue::glue("{name}.pdf"))
    combined <- gridExtra::arrangeGrob(
      fixed_plot, selector_plot, nrow = 1, widths = c(2, 1),
      top = grid::textGrob(labels[[name]], gp = grid::gpar(fontface = "bold"))
    )
    ggsave(plot_file, combined, width = 11, height = 5.5, units = "in")
    plot_status[[name]] <- TRUE
  }
  list(rows = rows, plots = plot_status)
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
  if (identical(family, "sensitivity_componentwise")) {
    diagnostics <- write_componentwise_diagnostics(
      loaded, family, aggregate_dir, image_dir
    )
  } else {
    diagnostics <- write_family_diagnostics(
      loaded, family, aggregate_dir, image_dir,
      lambda_limits = if (near_zero_family) c(-300, -9) else lambda_log10_limits,
      lambda_breaks = if (near_zero_family) near_zero_breaks else lambda_log10_grid
    )
  }
  all_diagnostics[[family]] <- diagnostics$rows
  diagnostic_outputs[[family]] <- diagnostics$plots

  if (identical(family, "sensitivity_componentwise")) {
    if (!identical(loaded$varying_options, c("lambda_1", "lambda_2"))) {
      stop("component-wise sensitivity must retain both lambda coordinates")
    }
    if (any(loaded$truth_target$R1_fPLS != "prefix") ||
        any(loaded$n_true_components$R1_fPLS != 4L)) {
      stop("component-wise sensitivity did not use rank-four prefix truth")
    }
    metric_specs <- data.frame(
      metric = c(
        "Y_reconstruction", "X_reconstruction_locations", "Beta_locations",
        "X_direction_locations", "X_loading_locations", "X_latent_scores"
      ),
      source = c("rmse", "rmse", rep("cosine", 4L)),
      label = c(
        "Y reconstruction", "X reconstruction", "Beta",
        "X direction", "X loading", "X score"
      ),
      value_label = c(
        rep("RMSE", 2L), "Signed cosine similarity",
        rep("Absolute cosine similarity", 3L)
      ),
      higher_is_better = c(FALSE, FALSE, rep(TRUE, 4L)),
      stringsAsFactors = FALSE
    )
    prefix_metrics <- metric_specs$metric
    metric_rows <- do.call(rbind, lapply(seq_len(nrow(metric_specs)), function(i) {
      spec <- metric_specs[i, ]
      table <- loaded[[spec$source]][[spec$metric]]
      if (is.null(table)) stop(glue::glue("missing prefix metric: {spec$metric}"))
      repetitions <- ave(
        seq_len(nrow(table)), table$Group, table$lambda_1, table$lambda_2,
        FUN = seq_along
      )
      data.frame(
        metric = spec$metric,
        measure = spec$value_label,
        higher_is_better = spec$higher_is_better,
        component = as.integer(as.character(table$Group)),
        lambda_1 = as.numeric(table$lambda_1),
        lambda_2 = as.numeric(table$lambda_2),
        repetition = as.integer(repetitions),
        value = as.numeric(table$R1_fPLS),
        stringsAsFactors = FALSE
      )
    }))
    if (any(!is.finite(metric_rows$value))) {
      stop("non-finite component-wise sensitivity metric")
    }
    if (any(metric_rows$value[!metric_rows$higher_is_better] < 0) ||
        any(abs(metric_rows$value[metric_rows$metric == "Beta_locations"]) > 1) ||
        any(metric_rows$value[
          metric_rows$higher_is_better & metric_rows$metric != "Beta_locations"
        ] < 0) ||
        any(metric_rows$value[
          metric_rows$higher_is_better & metric_rows$metric != "Beta_locations"
        ] > 1)) {
      stop("component-wise metric outside its valid range")
    }
    expected_cells <- length(component_lambda_grid)^2L + 2L
    option_pairs <- unique(metric_rows[c("lambda_1", "lambda_2")])
    if (nrow(option_pairs) != expected_cells) {
      stop("component-wise sensitivity option-cell count mismatch")
    }
    cell_counts <- aggregate(
      repetition ~ metric + component + lambda_1 + lambda_2,
      metric_rows,
      function(value) length(unique(value))
    )
    if (any(cell_counts$repetition != family_options[[1]]$test_options$n_reps)) {
      stop("incomplete component-wise sensitivity metric cell")
    }

    fixed_rows <- metric_rows[metric_rows$lambda_1 > 0 & metric_rows$lambda_2 > 0, ]
    h1_spread <- aggregate(
      value ~ metric + lambda_1 + repetition,
      fixed_rows[fixed_rows$component == 1L, ],
      function(value) diff(range(value))
    )
    h1_tolerance <- sqrt(.Machine$double.eps) * max(1, abs(fixed_rows$value))
    if (any(h1_spread$value > h1_tolerance)) {
      stop("component-1 results unexpectedly depend on component-2 lambda")
    }
    fixed_surfaces <- aggregate(
      value ~ metric + measure + higher_is_better + component + lambda_1 + lambda_2,
      fixed_rows,
      median
    )
    names(fixed_surfaces)[names(fixed_surfaces) == "value"] <- "median_value"
    fixed_surfaces <- fixed_surfaces[order(
      fixed_surfaces$metric, fixed_surfaces$component,
      fixed_surfaces$lambda_1, fixed_surfaces$lambda_2
    ), ]
    surface_file <- file.path(
      aggregate_dir, "sensitivity_componentwise_fixed_metric_surfaces.csv"
    )
    write.csv(fixed_surfaces, surface_file, row.names = FALSE)

    oracle_rows <- transform(
      fixed_rows,
      oracle_loss = ifelse(higher_is_better, -value, value)
    )
    oracle_rows <- dplyr::arrange(
      oracle_rows, metric, component, repetition, oracle_loss, lambda_1, lambda_2
    )
    oracle_rows <- dplyr::group_by(oracle_rows, metric, component, repetition)
    oracle_rows <- dplyr::slice(oracle_rows, 1L)
    oracle_rows <- dplyr::ungroup(oracle_rows)
    oracle_rows <- data.frame(
      metric = oracle_rows$metric,
      measure = oracle_rows$measure,
      higher_is_better = oracle_rows$higher_is_better,
      component = oracle_rows$component,
      repetition = oracle_rows$repetition,
      oracle_lambda_1 = oracle_rows$lambda_1,
      oracle_lambda_2 = oracle_rows$lambda_2,
      oracle_value = oracle_rows$value,
      stringsAsFactors = FALSE
    )
    oracle_rows$oracle_lambda_2[oracle_rows$component == 1L] <- NA_real_
    selector_rows <- metric_rows[
      metric_rows$lambda_1 <= 0 & metric_rows$lambda_2 <= 0,
    ]
    if (any(selector_rows$lambda_1 != selector_rows$lambda_2) ||
        any(!selector_rows$lambda_1 %in% c(-1, 0))) {
      stop("unexpected non-fixed component-wise sensitivity cell")
    }
    selector_rows$selector <- ifelse(selector_rows$lambda_1 == -1, "GCV", "MV-PLS")
    selector_rows <- data.frame(
      metric = selector_rows$metric,
      component = selector_rows$component,
      repetition = selector_rows$repetition,
      selector = selector_rows$selector,
      selector_value = selector_rows$value,
      stringsAsFactors = FALSE
    )
    regrets <- merge(
      selector_rows,
      oracle_rows,
      by = c("metric", "component", "repetition"),
      all.x = TRUE,
      sort = TRUE
    )
    regrets$regret <- ifelse(
      regrets$higher_is_better,
      regrets$oracle_value - regrets$selector_value,
      regrets$selector_value - regrets$oracle_value
    )
    regret_file <- file.path(
      aggregate_dir, "sensitivity_componentwise_truth_oracle_regrets.csv"
    )
    write.csv(regrets, regret_file, row.names = FALSE)

    h1_rows <- aggregate(
      value ~ metric + lambda_1 + repetition,
      fixed_rows[fixed_rows$component == 1L, ],
      median
    )
    metric_plot_files <- character()
    for (metric in prefix_metrics) {
      spec <- metric_specs[metric_specs$metric == metric, ]
      h1_data <- h1_rows[h1_rows$metric == metric, ]
      h1_medians <- aggregate(value ~ lambda_1, h1_data, median)
      h1_best <- if (spec$higher_is_better) {
        max(h1_medians$value)
      } else {
        min(h1_medians$value)
      }
      h1_optima <- h1_medians[h1_medians$value == h1_best, ]
      boxplot_data <- data.frame(
        Group = log10(h1_data$lambda_1),
        R1_fPLS = h1_data$value
      )
      boxplot_data <- boxplot_data[order(boxplot_data$Group), ]
      boxplot_groups <- sort(unique(boxplot_data$Group))
      boxplot_plot <- plot.grouped_boxplots(
        boxplot_data,
        group_name = "log10(component-1 fixed lambda)",
        subgroup_name = "Approaches",
        subgroup_labels = loaded$model_labels,
        subgroup_colors = loaded$model_colors,
        values_name = spec$value_label,
        DIVIDERS = FALSE,
        LEGEND = FALSE
      ) +
        annotate(
          "point",
          x = match(log10(h1_optima$lambda_1), boxplot_groups),
          y = h1_optima$value,
          shape = 23, size = 4, stroke = 0.8,
          color = "black", fill = "#E69F00"
        ) +
        labs(
          title = glue::glue("{spec$label}: prefix h = 1"),
          caption = "Diamond: best fixed-grid median"
        ) +
        std_plot_settings()
      h1_plot_file <- file.path(image_dir, glue::glue("{metric}_h1_fixed_boxplot.pdf"))
      ggsave(
        h1_plot_file,
        boxplot_plot, width = 7, height = 5, units = "in"
      )

      heatmap_data <- fixed_surfaces[
        fixed_surfaces$metric == metric & fixed_surfaces$component == 2L,
      ]
      heatmap_best <- if (spec$higher_is_better) {
        max(heatmap_data$median_value)
      } else {
        min(heatmap_data$median_value)
      }
      heatmap_optima <- heatmap_data[heatmap_data$median_value == heatmap_best, ]
      median_label <- if (identical(spec$value_label, "RMSE")) {
        "Median RMSE"
      } else {
        glue::glue("Median {tolower(spec$value_label)}")
      }
      heatmap_plot <- ggplot(
        heatmap_data,
        aes(x = log10(lambda_1), y = log10(lambda_2), fill = median_value)
      ) +
        geom_tile(color = "grey90") +
        geom_point(
          data = heatmap_optima,
          aes(x = log10(lambda_1), y = log10(lambda_2)),
          inherit.aes = FALSE,
          shape = 23, size = 4, stroke = 0.8,
          color = "black", fill = "#E69F00"
        ) +
        scale_x_continuous(breaks = sort(unique(log10(heatmap_data$lambda_1)))) +
        scale_y_continuous(breaks = sort(unique(log10(heatmap_data$lambda_2)))) +
        scale_fill_gradient(
          low = if (spec$higher_is_better) "white" else RColorBrewer::brewer.pal(3, "Blues")[3],
          high = if (spec$higher_is_better) RColorBrewer::brewer.pal(3, "Blues")[3] else "white"
        ) +
        coord_fixed() +
        labs(
          title = glue::glue("{spec$label}: prefix h = 2"),
          x = "log10(component-1 fixed lambda)",
          y = "log10(component-2 fixed lambda)", fill = median_label,
          caption = "Diamond: best fixed-grid median"
        ) +
        std_plot_settings() +
        guides(fill = guide_colorbar(direction = "vertical")) +
        theme(legend.position = "right")
      h2_plot_file <- file.path(image_dir, glue::glue("{metric}_h2_fixed_heatmap.pdf"))
      ggsave(
        h2_plot_file,
        heatmap_plot, width = 7, height = 6, units = "in"
      )
      metric_plot_files <- c(metric_plot_files, h1_plot_file, h2_plot_file)
    }

    selected_pair_rows <- list()
    selected_pair_plot_files <- character()
    selected_fields <- c(direction = "direction_lambda", loading = "loading_lambda")
    for (penalty in names(selected_fields)) {
      table <- loaded[[selected_fields[[penalty]]]]
      table <- table[table$lambda_1 == -1 & table$lambda_2 == -1, ]
      repetitions <- ave(seq_len(nrow(table)), table$Group, FUN = seq_along)
      pairs <- tidyr::pivot_wider(
        data.frame(
          repetition = as.integer(repetitions),
          component = as.integer(as.character(table$Group)),
          selected_lambda = as.numeric(table$R1_fPLS)
        ),
        names_from = component,
        values_from = selected_lambda,
        names_prefix = "lambda_"
      )
      if (nrow(pairs) != family_options[[1]]$test_options$n_reps ||
          any(!is.finite(as.matrix(pairs[c("lambda_1", "lambda_2")]))) ||
          any(as.matrix(pairs[c("lambda_1", "lambda_2")]) <= 0) ||
          any(!round(log10(as.matrix(pairs[c("lambda_1", "lambda_2")])), 10) %in%
                lambda_log10_grid)) {
        stop(glue::glue("invalid GCV {penalty} selected-lambda pairs"))
      }
      pair_rows <- data.frame(
        penalty = penalty,
        repetition = pairs$repetition,
        lambda_1 = pairs$lambda_1,
        lambda_2 = pairs$lambda_2,
        stringsAsFactors = FALSE
      )
      selected_pair_rows[[penalty]] <- pair_rows
      pair_counts <- aggregate(
        repetition ~ lambda_1 + lambda_2,
        transform(
          pair_rows,
          lambda_1 = log10(lambda_1),
          lambda_2 = log10(lambda_2)
        ),
        length
      )
      names(pair_counts)[names(pair_counts) == "repetition"] <- "count"
      pair_plot <- ggplot(pair_counts, aes(x = lambda_1, y = lambda_2, fill = count)) +
        geom_tile(width = 0.9, height = 0.9) +
        geom_text(aes(label = count), size = 3) +
        scale_x_continuous(breaks = lambda_log10_grid, limits = lambda_log10_limits) +
        scale_y_continuous(breaks = lambda_log10_grid, limits = lambda_log10_limits) +
        scale_fill_gradient(low = "white", high = RColorBrewer::brewer.pal(3, "Blues")[3]) +
        coord_fixed() +
        labs(
          title = glue::glue("GCV selected {penalty} lambda pairs"),
          x = "log10(component-1 lambda)",
          y = "log10(component-2 lambda)", fill = "Repetitions"
        ) +
        std_plot_settings() +
        guides(fill = guide_colorbar(direction = "vertical")) +
        theme(legend.position = "right")
      pair_plot_file <- file.path(
        image_dir, glue::glue("gcv_{penalty}_selected_pairs.pdf")
      )
      ggsave(
        pair_plot_file,
        pair_plot, width = 7, height = 6, units = "in"
      )
      selected_pair_plot_files <- c(selected_pair_plot_files, pair_plot_file)
    }
    selected_pair_file <- file.path(
      aggregate_dir, "sensitivity_componentwise_gcv_selected_pairs.csv"
    )
    write.csv(do.call(rbind, selected_pair_rows), selected_pair_file, row.names = FALSE)
    componentwise_outputs[[family]] <- list(
      fixed_metric_surfaces = basename(surface_file),
      truth_oracle_regrets = basename(regret_file),
      gcv_selected_pairs = basename(selected_pair_file),
      metric_plots = basename(metric_plot_files),
      selected_pair_plots = basename(selected_pair_plot_files),
      legend = "legend.pdf"
    )
  }

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
  } else if (identical(family, "sensitivity_componentwise")) {
    data.frame(metric = character(), source = character(), value_label = character())
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
    componentwise_outputs = componentwise_outputs,
    sensitivity_lambda_grid = c(-1, 0, sensitivity_lambda_grid),
    sensitivity_NSR_X = c(baseline = 3, challenging = 10),
    componentwise_fixed_lambda_grid = component_lambda_grid,
    componentwise_cells_per_repetition = list(
      fixed = length(component_lambda_grid)^2L,
      GCV = 1L,
      MV_PLS = 1L
    ),
    componentwise_true_rank = 4L,
    componentwise_fitted_components = 2L,
    componentwise_truth_target = "prefix",
    componentwise_metric_convention = list(
      reconstruction = "RMSE against the matching noise-free X/Y prefix",
      latent = "component-wise absolute cosine for X directions, loadings, and scores",
      beta = "signed Frobenius cosine for the cumulative beta prefix",
      component_matching = "fixed sequential order"
    ),
    competitor_reference = "one own-calibration cell per NSR_X scenario",
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
