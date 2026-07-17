# = ========================================================================== =
# - Script: diagnostic_plot_utils.R
# - Desc: Helpers for simulation diagnostic rows and plots.
# = ========================================================================== =

lambda_log10_grid <- -9:2
lambda_log10_limits <- range(lambda_log10_grid)

## Function: finite_model_values
# - Args:
#   * data: wide model-by-result data.frame
#   * model_names: model result columns
# - Desc:
#   Checks whether at least one model column contains finite data.
finite_model_values <- function(data, model_names) {
  if (is.null(data) || nrow(data) == 0L) return(FALSE)
  any(vapply(model_names, function(model) {
    values <- data[[model]]
    any(is.finite(values))
  }, logical(1)))
}


## Function: diagnostic_rows
# - Args:
#   * loaded: standard loaded result object
#   * family: experiment family name
#   * name: result entry to extract
#   * label: output metric label
# - Desc:
#   Converts a loaded wide result table to long diagnostic rows.
diagnostic_rows <- function(loaded, family, name, label = name,
                            componentwise = TRUE) {
  table <- loaded[[name]]
  if (is.null(table)) return(NULL)

  varying <- loaded$varying_options[1]
  levels <- as.numeric(table[[varying]])
  repetitions <- ave(seq_along(levels), table$Group, levels, FUN = seq_along)

  rows <- do.call(rbind, lapply(loaded$model_names, function(model_name) {
    data.frame(
      family = family,
      diagnostic = label,
      component = as.integer(table$Group),
      level = levels,
      repetition = repetitions,
      model = model_name,
      value = table[[model_name]],
      stringsAsFactors = FALSE
    )
  }))
  if (!componentwise) {
    rows <- rows[rows$component == min(rows$component), , drop = FALSE]
    rows$component <- NA_integer_
  }
  rows
}


## Function: positive_log10_table
# - Args:
#   * table: wide model-by-result data.frame
#   * model_names: model result columns
# - Desc:
#   Returns a copy with model values transformed to log10 when positive.
positive_log10_table <- function(table, model_names) {
  out <- table
  for (model_name in model_names) {
    values <- out[[model_name]]
    out[[model_name]] <- ifelse(is.finite(values) & values > 0, log10(values), NaN)
  }
  out
}


## Function: write_diagnostic_plot
# - Args:
#   * loaded: standard loaded result object
#   * data: wide model-by-result data.frame
#   * file: target PDF path
#   * title: plot title prefix
#   * values_name: y-axis label
# - Desc:
#   Writes a standard aggregate plot when finite values are available.
write_diagnostic_plot <- function(loaded, data, file, title, values_name,
                                  limits = NULL, horizontal_lines = NULL,
                                  y_breaks = NULL) {
  if (!finite_model_values(data, loaded$model_names)) return(FALSE)

  pdf(file, width = 8, height = 5)
  on.exit(dev.off(), add = TRUE)
  plot.aggregated_data(
    loaded, data, title, values_name,
    limits = limits,
    plots_catalog = list(
      boxplots = TRUE, lines = FALSE, logx = FALSE,
      loglog = FALSE, normalized = FALSE
    ),
    horizontal_lines = horizontal_lines,
    y_breaks = y_breaks
  )
  TRUE
}


## Function: write_family_diagnostics
# - Args:
#   * loaded: standard loaded result object
#   * family: experiment family name
#   * aggregate_dir: directory for aggregate CSV output
#   * image_dir: directory for family plot output
# - Desc:
#   Writes telemetry/lambda CSV rows and family diagnostic plots.
write_family_diagnostics <- function(
    loaded, family, aggregate_dir, image_dir,
    lambda_limits = lambda_log10_limits, lambda_breaks = lambda_log10_grid) {
  scalar_diagnostics <- c(
    execution_time = "Execution time (s)",
    peak_ram_mib = "Peak RAM (MiB)"
  )
  component_diagnostics <- c(
    iteration_count = "Iteration count",
    monotone = "Monotonic fit",
    hit_max_iter = "Reached iteration cap",
    finite_solution = "Finite solution",
    objective = "Final objective",
    direction_lambda = "Direction lambda",
    loading_lambda = "Loading lambda",
    fpca_lambda = "fPCA lambda"
  )
  selected_lambda_diagnostics <- c(
    pre_smoothing_lambda = "B-fPLS smoothing lambda",
    pb_penalty_lambda = "PB-fPLS penalty lambda"
  )

  rows <- c(
    lapply(names(scalar_diagnostics), function(name) {
      diagnostic_rows(loaded, family, name, scalar_diagnostics[[name]])
    }),
    lapply(names(component_diagnostics), function(name) {
      diagnostic_rows(loaded, family, name, component_diagnostics[[name]])
    }),
    lapply(names(selected_lambda_diagnostics), function(name) {
      diagnostic_rows(
        loaded, family, name, selected_lambda_diagnostics[[name]],
        componentwise = FALSE
      )
    })
  )
  rows <- do.call(rbind, rows[!vapply(rows, is.null, logical(1))])
  write.csv(rows, file.path(aggregate_dir, glue::glue("{family}_diagnostics.csv")),
            row.names = FALSE)

  plot_status <- list()
  for (name in names(scalar_diagnostics)) {
    plot_status[[name]] <- write_diagnostic_plot(
      loaded, loaded[[name]],
      file.path(image_dir, glue::glue("{name}.pdf")),
      scalar_diagnostics[[name]], scalar_diagnostics[[name]]
    )
  }
  plot_status$iteration_count <- write_diagnostic_plot(
    loaded, loaded$iteration_count,
    file.path(image_dir, "iteration_count.pdf"),
    component_diagnostics[["iteration_count"]],
    component_diagnostics[["iteration_count"]]
  )
  plot_status$monotone <- write_diagnostic_plot(
    loaded, loaded$monotone,
    file.path(image_dir, "monotone.pdf"),
    component_diagnostics[["monotone"]], "Monotonic fit (1 = yes)",
    limits = c(0, 1)
  )
  for (name in c("hit_max_iter", "finite_solution")) {
    plot_status[[name]] <- write_diagnostic_plot(
      loaded, loaded[[name]],
      file.path(image_dir, glue::glue("{name}.pdf")),
      component_diagnostics[[name]], paste0(component_diagnostics[[name]], " (1 = yes)"),
      limits = c(0, 1)
    )
  }
  plot_status$objective <- write_diagnostic_plot(
    loaded, loaded$objective,
    file.path(image_dir, "objective.pdf"),
    component_diagnostics[["objective"]],
    component_diagnostics[["objective"]]
  )

  for (name in c("direction_lambda", "loading_lambda", "fpca_lambda")) {
    plot_data <- positive_log10_table(loaded[[name]], loaded$model_names)
    plot_status[[name]] <- write_diagnostic_plot(
      loaded, plot_data,
      file.path(image_dir, glue::glue("{name}.pdf")),
      component_diagnostics[[name]], "log10(lambda)",
      limits = lambda_limits, horizontal_lines = lambda_limits,
      y_breaks = lambda_breaks
    )
  }
  for (name in names(selected_lambda_diagnostics)) {
    if (is.null(loaded[[name]])) {
      plot_status[[name]] <- FALSE
      next
    }
    plot_data <- positive_log10_table(loaded[[name]], loaded$model_names)
    plot_status[[name]] <- write_diagnostic_plot(
      loaded, plot_data,
      file.path(image_dir, glue::glue("{name}.pdf")),
      selected_lambda_diagnostics[[name]], "log10(lambda)",
      limits = lambda_limits, horizontal_lines = lambda_limits,
      y_breaks = lambda_breaks
    )
  }

  list(rows = rows, plots = plot_status)
}
