# = ========================================================================== =
# - Script: plot_qualitative_results.R
# - Desc: Produces the submitted representative 2D beta maps when available.
# = ========================================================================== =

load_fitted_model <- function(file, model_name) {
  env <- new.env(parent = emptyenv())
  load(file, envir = env)
  get(glue::glue("model_{model_name}"), envir = env, inherits = FALSE)
}

plot_representative_beta_2d <- function(path_list, family_options, image_dir) {
  selected <- family_options[vapply(family_options, function(options) {
    !isTRUE(options$test_options$smoke_test) &&
      options$dimensions$n_stat_units == 100L &&
      options$dimensions$source_k == 900L &&
      options$dimensions$n_locs == 1600L
  }, logical(1))]
  if (length(selected) != 1L) return(FALSE)
  options <- selected[[1]]

  batch_dir <- file.path(path_list$results, "vary_n", options$name_test, "batch_1")
  data <- readRDS(file.path(batch_dir, "generated_data.rds"))
  estimates <- lapply(options$model_names, function(model_name) {
    model <- load_fitted_model(
      file.path(batch_dir, glue::glue("batch_1_fitted_model_{model_name}.RData")),
      model_name
    )
    model$results$Beta_evaluation[[options$model$n_comp]]
  })
  axis <- sort(unique(data$evaluation[, 1]))

  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  pdf(file.path(image_dir, "beta_representative.pdf"), width = 10, height = 7)
  on.exit(dev.off(), add = TRUE)
  par(mfrow = c(2, 3), mar = c(3, 3, 3, 1))

  for (response in seq_len(2L)) {
    fields <- c(
      list(data$truth$Beta_reference[, response]),
      lapply(estimates, function(value) value[, response])
    )
    limits <- range(unlist(fields, use.names = FALSE))
    labels <- c("Truth", options$model_labels)
    for (i in seq_along(fields)) {
      z <- matrix(fields[[i]], nrow = length(axis), ncol = length(axis))
      image(axis, axis, z, col = hcl.colors(40, "Blue-Red 3"), zlim = limits,
            xlab = "x", ylab = "y", main = glue::glue("beta{response}: {labels[i]}"))
      contour(axis, axis, z, add = TRUE, drawlabels = FALSE, col = "grey30")
    }
  }
  TRUE
}
