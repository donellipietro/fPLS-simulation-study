# = ========================================================================== =
# - Script: generate_data.R
# - Desc: Generates ten variance-ordered 2D components with late Y relevance.
# = ========================================================================== =

## Function: generate_fpls_data ----
# - Args:
#   * test_options: one generated experiment option
#   * data_seed: repetition seed
# - Desc:
#   Reuses the submitted 2D generator with ten components, linking Y only to
#   components 9 and 10.
generate_fpls_data <- function(test_options, data_seed) {
  n_units <- test_options$dimensions$n_stat_units
  n_comp <- test_options$data$n_signal_components
  n_locs_requested <- test_options$dimensions$n_locs
  score_variance <- as.numeric(test_options$data$score_variance)
  predictive_components <- as.integer(test_options$data$predictive_components)
  if (test_options$model$dimension != 2L || n_comp != 10L) {
    stop("the predictive-order suite requires ten components on a 2D support")
  }

  axis <- seq(0, 1, length.out = test_options$dimensions$n_reference_per_axis)
  reference <- as.matrix(expand.grid(x = axis, y = axis))
  locations <- snap_2d_locations(
    n_locs_requested, reference, test_options$data$location_seed
  )
  location_index <- reference_index(reference, locations)

  loadings <- vapply(
    seq_len(n_comp),
    function(component) square_loading(reference, component),
    numeric(nrow(reference))
  )
  score_sd <- sqrt(score_variance)
  set.seed(data_seed)
  sampled_scores <- MASS::mvrnorm(
    n_units,
    mu = rep(0, n_comp),
    Sigma = diag(score_sd^2)
  )
  scores <- scale(sampled_scores, center = TRUE, scale = FALSE)

  response_loadings <- matrix(0, nrow = 2L, ncol = n_comp)
  response_loadings[1L, predictive_components[1L]] <-
    1 / score_sd[predictive_components[1L]]
  response_loadings[2L, predictive_components[2L]] <-
    1 / score_sd[predictive_components[2L]]

  X_true_reference <- scores %*% t(loadings)
  Y_true <- scores %*% t(response_loadings)
  truth_pls <- rank_one_pls_truth(Y_true, X_true_reference, n_comp)
  if (max(abs(Y_true - truth_pls$Y_hat[[n_comp]])) > 1e-8 ||
      max(abs(X_true_reference - truth_pls$X_hat[[n_comp]])) > 1e-8) {
    stop("source PLS truth failed its exact reconstruction check")
  }
  X_true_locations <- X_true_reference[, location_index, drop = FALSE]
  Beta_true_reference <- truth_pls$Beta[[n_comp]]
  Beta_true_locations <- Beta_true_reference[location_index, , drop = FALSE]
  X_loadings_locations <- truth_pls$X_loadings[location_index, , drop = FALSE]
  X_directions_locations <- truth_pls$X_space_directions[location_index, , drop = FALSE]
  X_last_component <- truth_pls$X_latent_scores[, n_comp, drop = FALSE] %*%
    t(X_loadings_locations[, n_comp, drop = FALSE])

  signal_X_power <- mean(X_true_locations^2)
  final_component_power <- mean(X_last_component^2)
  sigma_X <- sqrt(test_options$noise$NSR_X_final_component * final_component_power)
  realized_NSR_X <- sigma_X^2 / signal_X_power
  sigma_Y <- sqrt(test_options$noise$NSR_Y * colMeans(Y_true^2))
  set.seed(data_seed * 10000L)
  noise <- MASS::mvrnorm(
    n_units,
    mu = rep(0, nrow(locations) + nrow(response_loadings)),
    Sigma = diag(c(rep(sigma_X^2, nrow(locations)), sigma_Y^2))
  )
  X_noise <- scale(
    noise[, seq_len(nrow(locations)), drop = FALSE],
    center = TRUE, scale = FALSE
  )
  Y_noise <- scale(
    noise[, nrow(locations) + seq_len(nrow(response_loadings)), drop = FALSE],
    center = TRUE, scale = FALSE
  )

  list(
    dimension = 2L,
    X = X_true_locations + X_noise,
    Y = Y_true + Y_noise,
    locations = locations,
    evaluation = reference,
    data_seed = data_seed,
    location_seed = test_options$data$location_seed,
    dimensions = list(
      n_stat_units = n_units,
      n_comp = test_options$model$n_comp,
      n_signal_components = n_comp,
      n_locs_requested = n_locs_requested,
      n_locs = nrow(locations),
      n_responses = nrow(response_loadings),
      source_k = test_options$dimensions$source_k
    ),
    truth = list(
      Y = Y_true,
      X_locations = X_true_locations,
      X_reference = X_true_reference,
      Beta_locations = Beta_true_locations,
      Beta_reference = Beta_true_reference,
      Y_space_directions = truth_pls$Y_space_directions,
      X_space_directions_locations = X_directions_locations,
      X_latent_scores = truth_pls$X_latent_scores,
      Y_latent_scores = truth_pls$Y_latent_scores,
      X_loadings_locations = X_loadings_locations,
      Y_loadings = truth_pls$Y_loadings
    ),
    design = list(
      version = test_options$data$design_version,
      score_variance = score_variance,
      response_loadings = response_loadings,
      predictive_components = predictive_components
    ),
    noise = list(
      sigma_X = sigma_X,
      sigma_Y = sigma_Y,
      realized_NSR_X = realized_NSR_X,
      requested_NSR_X_final_component = test_options$noise$NSR_X_final_component,
      requested_NSR_Y = test_options$noise$NSR_Y
    ),
    provenance = list(
      generator = "submitted paper design extended to ten components",
      location_method = test_options$data$location_method
    )
  )
}
