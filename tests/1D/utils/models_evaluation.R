source_figure_rmse <- function(estimate, truth) {
  sqrt(mean((as.matrix(estimate) - as.matrix(truth))^2))
}

normalize_beta_shape <- function(value) {
  value <- as.matrix(value)
  value_norm <- norm(value, "F")
  if (!is.finite(value_norm) || value_norm == 0) return(value * NaN)
  value / value_norm
}

source_figure_beta_rmse <- function(estimate, truth) {
  source_figure_rmse(normalize_beta_shape(estimate), normalize_beta_shape(truth))
}

cosine_similarity <- function(estimate, truth, absolute = FALSE) {
  estimate <- as.numeric(estimate)
  truth <- as.numeric(truth)
  estimate_norm <- sqrt(sum(estimate^2))
  truth_norm <- sqrt(sum(truth^2))
  if (length(estimate) != length(truth) ||
      any(!is.finite(c(estimate, truth))) ||
      !is.finite(estimate_norm) || !is.finite(truth_norm) ||
      estimate_norm == 0 || truth_norm == 0) {
    return(NaN)
  }
  value <- sum(estimate * truth) / (estimate_norm * truth_norm)
  value <- max(-1, min(1, value))
  if (absolute) abs(value) else value
}

matrix_component <- function(value, component, n_rows) {
  if (is.null(value) || length(dim(value)) != 2L ||
      nrow(value) != n_rows || ncol(value) < component) {
    return(rep(NaN, n_rows))
  }
  value[, component]
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
  n_true_comp <- data$dimensions$n_true_comp
  if (is.null(n_true_comp)) n_true_comp <- n_comp
  n_responses <- data$dimensions$n_responses
  truth_target <- test_options$evaluation$truth_target
  if (is.null(truth_target)) truth_target <- "final"
  if (!truth_target %in% c("final", "prefix")) {
    stop("truth_target must be either 'final' or 'prefix'")
  }
  if (identical(truth_target, "prefix") &&
      (is.null(data$truth$prefix) || n_comp > length(data$truth$prefix$Y))) {
    stop("prefix truth is unavailable for every fitted component")
  }
  rmse <- list(
    Y_reconstruction = numeric(n_comp),
    X_reconstruction_locations = numeric(n_comp),
    Beta1_locations = numeric(n_comp),
    Beta2_locations = rep(NaN, n_comp)
  )
  if (identical(truth_target, "prefix")) {
    cosine <- list(
      Beta_locations = numeric(n_comp),
      X_direction_locations = numeric(n_comp),
      X_loading_locations = numeric(n_comp),
      X_latent_scores = numeric(n_comp)
    )
  }

  for (h in seq_len(n_comp)) {
    truth <- if (identical(truth_target, "prefix")) {
      list(
        Y = data$truth$prefix$Y[[h]],
        X_locations = data$truth$prefix$X_locations[[h]],
        Beta_locations = data$truth$prefix$Beta_locations[[h]]
      )
    } else {
      data$truth
    }
    rmse$Y_reconstruction[h] <- source_figure_rmse(
      model$results$Y_hat[[h]], truth$Y
    )
    rmse$X_reconstruction_locations[h] <- source_figure_rmse(
      model$results$X_hat_locations[[h]], truth$X_locations
    )
    rmse$Beta1_locations[h] <- source_figure_beta_rmse(
      model$results$Beta_locations[[h]][, 1, drop = FALSE],
      truth$Beta_locations[, 1, drop = FALSE]
    )
    if (n_responses == 2L) {
      rmse$Beta2_locations[h] <- source_figure_beta_rmse(
        model$results$Beta_locations[[h]][, 2, drop = FALSE],
        truth$Beta_locations[, 2, drop = FALSE]
      )
    }
    if (identical(truth_target, "prefix")) {
      cosine$Beta_locations[h] <- cosine_similarity(
        model$results$Beta_locations[[h]], truth$Beta_locations
      )
      cosine$X_direction_locations[h] <- cosine_similarity(
        matrix_component(
          model$results$X_space_directions_locations, h, data$dimensions$n_locs
        ),
        data$truth$X_space_directions_locations[, h],
        absolute = TRUE
      )
      cosine$X_loading_locations[h] <- cosine_similarity(
        matrix_component(
          model$results$X_loadings_locations, h, data$dimensions$n_locs
        ),
        data$truth$X_loadings_locations[, h],
        absolute = TRUE
      )
      cosine$X_latent_scores[h] <- cosine_similarity(
        matrix_component(
          model$results$X_latent_scores, h, data$dimensions$n_stat_units
        ),
        data$truth$X_latent_scores[, h],
        absolute = TRUE
      )
    }
  }

  evaluation <- list(
    rmse = rmse,
    beta_sign_alignment = FALSE,
    data_seed = data$data_seed,
    location_seed = data$location_seed,
    dimension = data$dimension,
    truth_target = truth_target,
    n_true_components = n_true_comp,
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
    monotone = component_result(model, "monotone", n_comp),
    objective = component_result(model, "objective", n_comp),
    hit_max_iter = component_result(model, "hit_max_iter", n_comp),
    finite_solution = component_result(model, "finite_solution", n_comp),
    direction_lambda = model$results$direction_lambdas[, 1],
    loading_lambda = model$results$loading_lambdas[, 1],
    fpca_lambda = component_result(model, "fpca_lambdas", n_comp),
    pre_smoothing_lambda = component_result(model, "pre_smoothing_lambda", n_comp),
    pb_penalty_lambda = component_result(model, "pb_penalty_lambda", n_comp),
    calibration = model$results$calibration,
    provenance = model$results$provenance
  )
  if (identical(truth_target, "prefix")) evaluation$cosine <- cosine
  evaluation
}
