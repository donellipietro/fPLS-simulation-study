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
  pdf(file.path(image_dir, "qualitative_beta.pdf"), width = 11, height = 5)
  on.exit(dev.off(), add = TRUE)
  par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))

  for (options in selected) {
    batch_dir <- file.path(path_list$results, "vary_k", options$name_test, "batch_1")
    data <- readRDS(file.path(batch_dir, "generated_data.rds"))
    estimates <- lapply(options$model_names, function(model_name) {
      model <- load_fitted_model(
        file.path(batch_dir, glue::glue("batch_1_fitted_model_{model_name}.RData")),
        model_name
      )
      model$results$Beta_evaluation[[options$model$n_comp]][, 1]
    })
    values <- c(data$truth$Beta_reference[, 1], unlist(estimates, use.names = FALSE))

    plot(
      data$evaluation[, 1], data$truth$Beta_reference[, 1],
      type = "l", lwd = 2, lty = 2, col = "black", ylim = range(values),
      xlab = "t", ylab = expression(beta(t)),
      main = glue::glue("k = {options$dimensions$source_k}")
    )
    for (i in seq_along(estimates)) {
      lines(data$evaluation[, 1], estimates[[i]], col = options$model_colors[i], lwd = 1.5)
    }
    legend(
      "topright", legend = c("Truth", options$model_labels),
      col = c("black", options$model_colors), lty = c(2, rep(1, length(estimates))),
      lwd = c(2, rep(1.5, length(estimates))), cex = 0.65, bty = "n"
    )
  }
  TRUE
}
