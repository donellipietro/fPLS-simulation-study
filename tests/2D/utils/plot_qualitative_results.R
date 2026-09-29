# = ========================================================================== =
# - Script: plot_qualitative_results.R
# - Desc: Produces the submitted representative 2D beta maps when available.
# = ========================================================================== =

representative_beta_setting_2d <- list(
  n_stat_units = 100L,
  source_k = 900L,
  n_locs = 1600L
)

load_fitted_model <- function(file, model_name) {
  env <- new.env(parent = emptyenv())
  load(file, envir = env)
  get(glue::glue("model_{model_name}"), envir = env, inherits = FALSE)
}

plot_representative_beta_2d <- function(path_list, family_options, image_dir) {
  selected <- family_options[vapply(family_options, function(options) {
    !isTRUE(options$test_options$smoke_test) &&
      options$dimensions$n_stat_units == representative_beta_setting_2d$n_stat_units &&
      options$dimensions$source_k == representative_beta_setting_2d$source_k &&
      options$dimensions$n_locs == representative_beta_setting_2d$n_locs
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
  boundary <- data.frame(
    long = c(0, 1, 1, 0, 0),
    lat = c(0, 0, 1, 1, 0)
  )

  dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
  pdf(file.path(image_dir, "beta_representative.pdf"), width = 10, height = 7)
  on.exit(dev.off(), add = TRUE)
  plots <- list()

  for (response in seq_len(2L)) {
    truth <- normalize_beta_shape(data$truth$Beta_reference[, response])[, 1]
    fields <- c(
      list(truth),
      lapply(estimates, function(value) {
        normalize_beta_shape(value[, response])[, 1]
      })
    )
    limits <- range(truth)
    labels <- c("Truth", options$model_labels)
    for (i in seq_along(fields)) {
      plots[[length(plots) + 1L]] <- plot.field_tile(
        data$evaluation, fields[[i]], boundary = boundary, limits = limits,
        palette = cool_to_warm_extended_palette, ISOLINES = TRUE
      ) +
        labs(title = glue::glue("beta{response}: {labels[i]}")) +
        std_plot_settings_fields()
    }
  }
  gridExtra::grid.arrange(grobs = plots, nrow = 2)
  TRUE
}
