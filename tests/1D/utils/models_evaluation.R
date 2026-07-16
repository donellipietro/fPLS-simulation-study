source_figure_rmse <- function(estimate, truth) {
  sqrt(mean((as.matrix(estimate) - as.matrix(truth))^2))
}

normalize_beta_shape <- function(value) {
  value <- as.matrix(value)
  value_norm <- norm(value, "F")
  if (value_norm == 0) return(value * NaN)
  value / value_norm
}

align_beta_shape <- function(estimate, truth) {
  estimate <- normalize_beta_shape(estimate)
  truth <- normalize_beta_shape(truth)
  if (source_figure_rmse(estimate, truth) > source_figure_rmse(-estimate, truth)) {
    estimate <- -estimate
  }
  estimate
}

source_figure_beta_rmse <- function(estimate, truth) {
  source_figure_rmse(align_beta_shape(estimate, truth), normalize_beta_shape(truth))
}

submitted_paper_normalized_rmse <- function(estimate, truth) {
  estimate <- as.matrix(estimate)
  truth <- as.matrix(truth)
  denominator <- nrow(truth) * ncol(truth) * norm(truth, "F")
  if (denominator == 0) return(NaN)
  norm(estimate - truth, "F") / denominator
}

component_result <- function(model, name, n_comp) {
  value <- model$results[[name]]
  if (is.null(value)) value <- model$results$telemetry[[name]]
  if (is.null(value)) return(rep(NaN, n_comp))
  value <- as.numeric(value)
  if (length(value) == 1L) return(rep(value, n_comp))
  if (length(value) != n_comp) return(rep(NaN, n_comp))
  value
}

evaluate_results <- function(model, data, test_options) {
  n_comp <- data$dimensions$n_comp
  n_responses <- data$dimensions$n_responses
  rmse <- submitted_normalized_rmse <- list(
    Y_reconstruction = numeric(n_comp),
    X_reconstruction_locations = numeric(n_comp),
    Beta1_locations = numeric(n_comp),
    Beta2_locations = rep(NaN, n_comp)
  )

  for (h in seq_len(n_comp)) {
    rmse$Y_reconstruction[h] <- source_figure_rmse(
      model$results$Y_hat[[h]], data$truth$Y
    )
    rmse$X_reconstruction_locations[h] <- source_figure_rmse(
      model$results$X_hat_locations[[h]], data$truth$X_locations
    )
    rmse$Beta1_locations[h] <- source_figure_beta_rmse(
      model$results$Beta_locations[[h]][, 1, drop = FALSE],
      data$truth$Beta_locations[, 1, drop = FALSE]
    )
    submitted_normalized_rmse$Y_reconstruction[h] <- submitted_paper_normalized_rmse(
      model$results$Y_hat[[h]], data$truth$Y
    )
    submitted_normalized_rmse$X_reconstruction_locations[h] <- submitted_paper_normalized_rmse(
      model$results$X_hat_locations[[h]], data$truth$X_locations
    )
    submitted_normalized_rmse$Beta1_locations[h] <- submitted_paper_normalized_rmse(
      model$results$Beta_locations[[h]][, 1, drop = FALSE],
      data$truth$Beta_locations[, 1, drop = FALSE]
    )
    if (n_responses == 2L) {
      rmse$Beta2_locations[h] <- source_figure_beta_rmse(
        model$results$Beta_locations[[h]][, 2, drop = FALSE],
        data$truth$Beta_locations[, 2, drop = FALSE]
      )
      submitted_normalized_rmse$Beta2_locations[h] <- submitted_paper_normalized_rmse(
        model$results$Beta_locations[[h]][, 2, drop = FALSE],
        data$truth$Beta_locations[, 2, drop = FALSE]
      )
    }
  }

  list(
    rmse = rmse,
    submitted_normalized_rmse = submitted_normalized_rmse,
    data_seed = data$data_seed,
    location_seed = data$location_seed,
    dimension = data$dimension,
    n_stat_units = data$dimensions$n_stat_units,
    n_locations = data$dimensions$n_locs,
    source_k = data$dimensions$source_k,
    n_basis = model$results$n_basis,
    execution_time = model$results$execution_time,
    peak_ram_mib = model$results$peak_ram_mib,
    setup_seconds = model$results$setup_seconds,
    fit_seconds = model$results$fit_seconds,
    output_seconds = model$results$output_seconds,
    iteration_count = component_result(model, "iteration_counts", n_comp),
    direction_lambda = model$results$direction_lambdas[, 1],
    loading_lambda = model$results$loading_lambdas[, 1],
    pre_smoothing_lambda = component_result(model, "pre_smoothing_lambda", n_comp),
    pb_penalty_lambda = component_result(model, "pb_penalty_lambda", n_comp),
    calibration = model$results$calibration,
    settings_status = test_options$regularization$status,
    metric_status = "provisional_source_figure_metric",
    submitted_metric_status = "provisional_submitted_paper_formula",
    provenance = model$results$provenance,
    paper_design_complete = FALSE,
    paper_results_reproduced = FALSE
  )
}
