# = ========================================================================== =
# - Script: plot_qualitative_results.R
# - Desc: Produces the submitted k=11/k=101 beta comparison when available.
# = ========================================================================== =

load_fitted_model <- function(file, model_name) {
  env <- new.env(parent = emptyenv())
  load(file, envir = env)
  get(glue::glue("model_{model_name}"), envir = env, inherits = FALSE)
}

plot_qualitative_beta_1d <- function(path_list, family_options, image_dir) {
  selected <- family_options[vapply(family_options, function(options) {
    !isTRUE(options$test_options$smoke_test) &&
      options$dimensions$source_k %in% c(11L, 101L)
  }, logical(1))]
  if (length(selected) != 2L) return(FALSE)
  selected <- selected[order(vapply(selected, function(x) x$dimensions$source_k, integer(1)))]

  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  pdf(file.path(image_dir, "qualitative_beta.pdf"), width = 11, height = 6)
  on.exit(dev.off(), add = TRUE)
  layout(matrix(c(1, 2, 3, 3), nrow = 2, byrow = TRUE), heights = c(4, 1))

  for (panel in seq_along(selected)) {
    options <- selected[[panel]]
    batch_dir <- file.path(path_list$results, "vary_k", options$name_test, "batch_1")
    data <- readRDS(file.path(batch_dir, "generated_data.rds"))
    truth <- normalize_beta_shape(data$truth$Beta_reference[, 1])[, 1]
    estimates <- setNames(lapply(options$model_names, function(model_name) {
      model <- load_fitted_model(
        file.path(batch_dir, glue::glue("batch_1_fitted_model_{model_name}.RData")),
        model_name
      )
      raw_evaluation <- model$results$Beta_evaluation[[options$model$n_comp]][, 1]
      sign <- if (source_figure_rmse(normalize_beta_shape(raw_evaluation), truth) >
                    source_figure_rmse(-normalize_beta_shape(raw_evaluation), truth)) -1 else 1
      list(
        evaluation = sign * normalize_beta_shape(raw_evaluation)[, 1],
        locations = sign * model$results$Beta_locations[[options$model$n_comp]][, 1] /
          norm(as.matrix(raw_evaluation), "F")
      )
    }), options$model_names)
    values <- c(truth, unlist(lapply(estimates, `[[`, "evaluation"), use.names = FALSE))

    par(mar = c(4, 4, 3, 1))

    plot(
      data$evaluation[, 1], truth,
      type = "n", ylim = range(values), yaxt = "n",
      xlab = "t", ylab = if (panel == 1L) expression(beta[1]) else "",
      main = bquote(k == .(options$dimensions$source_k))
    )
    grid(col = "grey90", lty = 3)
    lines(data$evaluation[, 1], truth, col = "black", lty = 2, lwd = 1.5)

    mv <- estimates$MV_PLS$locations
    lines(data$locations[, 1], mv, col = "grey70", lty = 2, lwd = 1)
    points(data$locations[, 1], mv, col = "grey70", pch = 16, cex = 0.3)

    colors <- setNames(options$model_colors, options$model_names)
    for (model_name in c("B_fPLS", "B_fPLS_smooth", "PB_fPLS", "R1_fPLS")) {
      lines(
        data$evaluation[, 1], estimates[[model_name]]$evaluation,
        col = colors[[model_name]], lwd = if (model_name %in% c("B_fPLS_smooth", "R1_fPLS")) 2 else 1
      )
    }
  }

  options <- selected[[1]]
  colors <- setNames(options$model_colors, options$model_names)
  labels <- setNames(options$model_labels, options$model_names)
  legend_order <- c("MV_PLS", "R1_fPLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS")
  par(mar = rep(0, 4))
  plot.new()
  legend(
    "center",
    legend = c("Ground Truth", labels[legend_order]),
    col = c("black", "grey70", colors[legend_order[-1]]),
    lty = c(2, 2, rep(1, 4)),
    lwd = c(1.5, 1, 2, 1, 2, 1),
    pch = c(NA, 16, rep(NA, 4)),
    pt.cex = 0.7,
    ncol = 2,
    cex = 0.8,
    bty = "n"
  )
  TRUE
}
