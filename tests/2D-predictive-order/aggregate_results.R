# = ========================================================================== =
# - Test: Predictive component ordering 2D - aggregate results
# - Desc: Validates complete batches and plots progressive reconstruction error.
# - Args:
#   [1] name_main_test: vary_H or all
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
source("tests/2D-predictive-order/config.R")
source("tests/2D-predictive-order/utils/generate_options.R")

load_model <- function(file, model_name) {
  env <- new.env(parent = emptyenv())
  load(file, envir = env)
  env[[glue::glue("model_{model_name}")]]
}

center_columns <- function(values) {
  sweep(as.matrix(values), 2L, colMeans(values), "-")
}

proportion_variance_explained <- function(observed, fitted) {
  total <- sum(center_columns(observed)^2)
  value <- 1 - sum((as.matrix(observed) - as.matrix(fitted))^2) / total
  if (!is.finite(value)) stop("non-finite explained-variance diagnostic")
  value
}

proportion_cross_covariance_explained <- function(X, Y, X_fitted, Y_fitted) {
  observed <- crossprod(center_columns(X), center_columns(Y)) / (nrow(X) - 1L)
  fitted <- crossprod(center_columns(X_fitted), center_columns(Y_fitted)) /
    (nrow(X_fitted) - 1L)
  total <- sum(observed^2)
  value <- 1 - sum((observed - fitted)^2) / total
  if (!is.finite(value)) stop("non-finite explained-cross-covariance diagnostic")
  value
}

collect_explained_structure <- function(path_list, options) {
  rows <- list()
  row_index <- 0L
  for (batch_index in seq_len(options$test_options$n_reps)) {
    batch_dir <- file.path(
      path_list$results, "vary_H", options$name_test, glue::glue("batch_{batch_index}")
    )
    data <- readRDS(file.path(batch_dir, "generated_data.rds"))
    for (model_name in options$model_names) {
      model <- load_model(
        file.path(batch_dir, glue::glue("batch_{batch_index}_fitted_model_{model_name}.RData")),
        model_name
      )
      values <- do.call(rbind, lapply(seq_len(options$model$n_comp), function(h) {
        c(
          X_variance_explained = proportion_variance_explained(
            data$X, model$results$X_hat_locations[[h]]
          ),
          Y_variance_explained = proportion_variance_explained(
            data$Y, model$results$Y_hat[[h]]
          ),
          XY_cross_covariance_explained = proportion_cross_covariance_explained(
            data$X, data$Y, model$results$X_hat_locations[[h]], model$results$Y_hat[[h]]
          )
        )
      }))
      row_index <- row_index + 1L
      rows[[row_index]] <- data.frame(
        batch = batch_index,
        n_comp = rep(seq_len(nrow(values)), each = ncol(values)),
        model = model_name,
        metric = rep(colnames(values), times = nrow(values)),
        value = as.numeric(t(values)),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

structure_plot_data <- function(rows, metric, model_names) {
  values <- rows[rows$metric == metric, c("batch", "n_comp", "model", "value")]
  wide <- reshape(values, idvar = c("batch", "n_comp"), timevar = "model", direction = "wide")
  names(wide) <- sub("^value[.]", "", names(wide))
  for (model_name in model_names) {
    if (is.null(wide[[model_name]])) wide[[model_name]] <- NaN
  }
  wide <- wide[order(wide$n_comp, wide$batch), c("n_comp", model_names)]
  data.frame(Group = 1L, n_comp = wide$n_comp, wide[model_names] * 100)
}

## Select and validate the requested family ----
args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args)) args[1] else name_main_test_default
families <- if (!is.null(test_groups[[requested]])) test_groups[[requested]] else requested
if (!identical(families, "vary_H")) stop("unknown predictive-order experiment family")

cfg <- load_config()
path_list <- create_paths(test_suite)
path_list$queue <- config_path(path_list$queue, "vary_H")
path_list$logs <- config_path(path_list$logs, "vary_H")
mkdir(c(path_list$queue, path_list$logs))
generate_options(test_suite, "vary_H", path_list$queue)
option_files <- sort(list.files(path_list$queue, pattern = "[.]json$", full.names = TRUE))
family_options <- lapply(option_files, fromJSON, simplifyVector = TRUE)

options <- family_options[[1L]]
n_comp <- options$model$n_comp
expected <- expand.grid(
  component = seq_len(n_comp),
  model = options$model_names,
  stringsAsFactors = FALSE
)
expected$expected_repetitions <- options$test_options$n_reps

for (batch_index in seq_len(options$test_options$n_reps)) {
  batch_dir <- file.path(
    path_list$results, "vary_H", options$name_test,
    glue::glue("batch_{batch_index}")
  )
  required <- c(
    "generated_data.rds",
    glue::glue("batch_{batch_index}_results_evaluation.RData"),
    glue::glue("batch_{batch_index}_fitted_model_{options$model_names}.RData")
  )
  if (any(!file.exists(file.path(batch_dir, required)))) {
    stop(glue::glue("incomplete batch files for {options$name_test}/batch_{batch_index}"))
  }

  data <- readRDS(file.path(batch_dir, "generated_data.rds"))
  if (!identical(data$design$version, 4L) ||
      !identical(data$design$predictive_components, c(9L, 10L)) ||
      any(diff(data$design$score_variance) >= 0)) {
    stop("batch does not implement the current predictive-order setting; rerun the suite")
  }
  for (model_name in options$model_names) {
    model_file <- file.path(
      batch_dir,
      glue::glue("batch_{batch_index}_fitted_model_{model_name}.RData")
    )
    model <- load_model(model_file, model_name)
    if (length(model$results$Y_hat) != n_comp ||
        length(model$results$X_hat_locations) != n_comp ||
        length(model$results$Beta_locations) != n_comp) {
      stop(glue::glue("invalid component-wise result shape for {model_name}"))
    }
  }
}

## Load standard results and expose component prefixes as the varying value ----
loaded <- load_all_quantitiative_results(path_list, "vary_H")
for (metric in names(loaded$rmse)) {
  loaded$rmse[[metric]]$n_comp <- as.integer(as.character(loaded$rmse[[metric]]$Group))
  loaded$rmse[[metric]]$Group <- 1L
}
for (name in c(
  "iteration_count", "monotone", "objective", "hit_max_iter",
  "finite_solution", "direction_lambda", "loading_lambda", "fpca_lambda"
)) {
  loaded[[name]]$n_comp <- as.integer(as.character(loaded[[name]]$Group))
  loaded[[name]]$Group <- 1L
}

aggregate_dir <- file.path(cfg$PATH_RESULTS, test_suite, "aggregate", requested)
image_dir <- file.path(cfg$PATH_IMAGES, test_suite, "vary_H")
dir.create(aggregate_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(loaded, file.path(aggregate_dir, "loaded_vary_H.rds"))

structure_rows <- collect_explained_structure(path_list, options)
write.csv(
  structure_rows,
  file.path(aggregate_dir, "explained_structure.csv"),
  row.names = FALSE
)

## Write metrics and verify repetition completeness ----
metrics <- c(
  "Y_reconstruction", "X_reconstruction_locations",
  "Beta1_locations", "Beta2_locations"
)
rows <- do.call(rbind, lapply(metrics, function(metric) {
  table <- loaded$rmse[[metric]]
  repetitions <- ave(seq_len(nrow(table)), table$n_comp, FUN = seq_along)
  do.call(rbind, lapply(loaded$model_names, function(model_name) {
    data.frame(
      suite = test_suite,
      family = "vary_H",
      metric = metric,
      component = table$n_comp,
      repetition = repetitions,
      model = model_name,
      value = table[[model_name]],
      stringsAsFactors = FALSE
    )
  }))
}))
if (any(!is.finite(rows$value[rows$metric %in% c(
  "Y_reconstruction", "X_reconstruction_locations"
)]))) stop("non-finite reconstruction metric")

primary <- rows[rows$metric == "Y_reconstruction", , drop = FALSE]
counts <- aggregate(
  repetition ~ component + model, primary,
  function(x) length(unique(x))
)
names(counts)[3L] <- "completed_repetitions"
completeness <- merge(expected, counts, all.x = TRUE)
completeness$completed_repetitions[is.na(completeness$completed_repetitions)] <- 0L
completeness$complete <-
  completeness$completed_repetitions == completeness$expected_repetitions
if (nrow(completeness) != nrow(expected) || any(!completeness$complete)) {
  stop("incomplete predictive-order experiment")
}

write.csv(rows, file.path(aggregate_dir, "all_metrics.csv"), row.names = FALSE)
write.csv(completeness, file.path(aggregate_dir, "completeness.csv"), row.names = FALSE)
diagnostics <- write_family_diagnostics(loaded, "vary_H", aggregate_dir, image_dir)

## Create standard metric plots and model legend ----
for (metric in metrics) {
  pdf(file.path(image_dir, glue::glue("{metric}.pdf")), width = 8, height = 5)
  plot.aggregated_data(
    loaded, loaded$rmse[[metric]],
    "Predictive component ordering", "RMSE",
    plots_catalog = list(
      boxplots = TRUE, lines = FALSE, logx = FALSE,
      loglog = FALSE, normalized = FALSE
    )
  )
  dev.off()
}

structure_metrics <- c(
  X_variance_explained = "X variance explained (%)",
  Y_variance_explained = "Y variance explained (%)",
  XY_cross_covariance_explained = "X-Y cross-covariance explained (%)"
)
for (metric in names(structure_metrics)) {
  pdf(file.path(image_dir, glue::glue("{metric}.pdf")), width = 8, height = 5)
  plot.aggregated_data(
    loaded,
    structure_plot_data(structure_rows, metric, loaded$model_names),
    "Predictive component ordering", structure_metrics[[metric]],
    limits = c(0, 100),
    y_breaks = seq(0, 100, 25),
    plots_catalog = list(
      boxplots = TRUE, lines = FALSE, logx = FALSE,
      loglog = FALSE, normalized = FALSE
    )
  )
  dev.off()
}

pdf(file.path(image_dir, "legend.pdf"), width = 6, height = 1.5, bg = "white")
par(mar = rep(0, 4))
plot.new()
legend(
  "center", legend = loaded$model_labels, col = "black",
  pt.bg = loaded$model_colors, pch = 22, pt.cex = 1.5,
  horiz = TRUE, bty = "n"
)
dev.off()

## Record and plot the latent design used by the experiment ----
first_batch <- file.path(
  path_list$results, "vary_H", options$name_test, "batch_1", "generated_data.rds"
)
first_data <- readRDS(first_batch)
design <- data.frame(
  component = seq_len(n_comp),
  X_variance = first_data$design$score_variance,
  Y_signal_variance = first_data$design$score_variance *
    colSums(first_data$design$response_loadings^2)
)
write.csv(design, file.path(aggregate_dir, "latent_design.csv"), row.names = FALSE)
design_long <- tidyr::pivot_longer(
  design, -component, names_to = "quantity", values_to = "value"
)
design_plot <- ggplot(design_long, aes(x = component, y = value)) +
  geom_col(fill = RColorBrewer::brewer.pal(3, "Blues")[3], width = 0.75) +
  facet_wrap(~quantity, ncol = 1L, scales = "free_y") +
  scale_x_continuous(breaks = seq_len(n_comp)) +
  labs(x = "Component", y = NULL) +
  theme_bw()
ggsave(
  file.path(image_dir, "latent_design.pdf"), design_plot,
  width = 8, height = 6, units = "in"
)

write_json(
  list(
    schema_version = 2L,
    suite = test_suite,
    requested = requested,
    families = "vary_H",
    run_complete = all(completeness$complete),
    smoke_test = SMOKE_TEST,
    n_signal_components = 10L,
    predictive_components = c(9L, 10L),
    diagnostic_outputs = diagnostics$plots
  ),
  file.path(aggregate_dir, "run_status.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat(glue::glue(
  "Wrote {nrow(rows)} metric rows across {nrow(completeness)} complete cells.\n",
  .trim = FALSE
))
