paper_normalized_rmse <- function(estimate, truth) {
  estimate <- as.matrix(estimate)
  truth <- as.matrix(truth)
  denominator <- nrow(truth) * ncol(truth) * norm(truth, "F")
  if (denominator == 0) return(NaN)
  norm(estimate - truth, "F") / denominator
}

evaluate_results <- function(model, data, test_options) {
  n_comp <- data$dimensions$n_comp
  n_responses <- data$dimensions$n_responses
  rmse <- list(
    Y_reconstruction = numeric(n_comp),
    X_reconstruction_locations = numeric(n_comp),
    Beta1_locations = numeric(n_comp),
    Beta2_locations = rep(NaN, n_comp)
  )

  for (h in seq_len(n_comp)) {
    rmse$Y_reconstruction[h] <- paper_normalized_rmse(
      model$results$Y_hat[[h]], data$truth$Y
    )
    rmse$X_reconstruction_locations[h] <- paper_normalized_rmse(
      model$results$X_hat_locations[[h]], data$truth$X_locations
    )
    rmse$Beta1_locations[h] <- paper_normalized_rmse(
      model$results$Beta_locations[[h]][, 1, drop = FALSE],
      data$truth$Beta_locations[, 1, drop = FALSE]
    )
    if (n_responses == 2L) {
      rmse$Beta2_locations[h] <- paper_normalized_rmse(
        model$results$Beta_locations[[h]][, 2, drop = FALSE],
        data$truth$Beta_locations[, 2, drop = FALSE]
      )
    }
  }

  list(
    rmse = rmse,
    data_seed = data$data_seed,
    location_seed = data$location_seed,
    dimension = data$dimension,
    n_stat_units = data$dimensions$n_stat_units,
    n_locations = data$dimensions$n_locs,
    source_k = data$dimensions$source_k,
    n_basis = model$results$n_basis,
    execution_time = model$results$execution_time,
    peak_ram_mib = model$results$peak_ram_mib,
    cpu_seconds = model$results$cpu_seconds,
    cpu_usage_percent = model$results$cpu_usage_percent,
    setup_seconds = model$results$setup_seconds,
    fit_seconds = model$results$fit_seconds,
    output_seconds = model$results$output_seconds,
    direction_lambda = model$results$direction_lambdas[, 1],
    loading_lambda = model$results$loading_lambdas[, 1],
    calibration = model$results$calibration,
    settings_status = test_options$regularization$status,
    metric_status = test_options$provenance$metric_status,
    provenance = model$results$provenance,
    paper_design_complete = FALSE,
    paper_results_reproduced = FALSE
  )
}
