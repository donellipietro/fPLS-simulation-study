# = ========================================================================== =
# - Script: generate_data.R
# - Desc: Generates ten variance-ordered 2D components with late Y relevance.
# = ========================================================================== =

predictive_order_loading <- function(points, component) {
  frequencies <- matrix(c(
    4, 0,
    0, 4,
    3, 3,
    3, 0,
    0, 3,
    2, 2,
    2, 1,
    1, 2,
    1, 0,
    0, 1
  ), ncol = 2L, byrow = TRUE)
  cos(pi * frequencies[component, 1] * points[, 1]) *
    cos(pi * frequencies[component, 2] * points[, 2])
}

orthogonal_component_scores <- function(n_units, score_variance, seed) {
  n_comp <- length(score_variance)
  if (n_units <= n_comp) stop("n_stat_units must exceed the number of signal components")
  set.seed(seed)
  raw <- scale(
    matrix(rnorm(n_units * n_comp), nrow = n_units),
    center = TRUE, scale = FALSE
  )
  basis <- qr.Q(qr(raw))[, seq_len(n_comp), drop = FALSE]
  sweep(basis, 2L, sqrt((n_units - 1L) * score_variance), "*")
}

## Function: generate_fpls_data ----
# - Args:
#   * test_options: one generated experiment option
#   * data_seed: repetition seed
# - Desc:
#   Produces exact decreasing X component variances while linking Y only to
#   the smooth low-variance components 9 and 10.
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

  raw_loadings <- vapply(
    seq_len(n_comp),
    function(component) predictive_order_loading(reference, component),
    numeric(nrow(reference))
  )
  observed_gram_root <- chol(crossprod(
    raw_loadings[location_index, , drop = FALSE]
  ))
  loadings <- raw_loadings %*% solve(observed_gram_root) * sqrt(nrow(locations))
  loadings_locations <- loadings[location_index, , drop = FALSE]
  if (max(abs(crossprod(loadings_locations) / nrow(locations) - diag(n_comp))) > 1e-10) {
    stop("observed spatial components are not orthonormal")
  }
  scores <- orthogonal_component_scores(n_units, score_variance, data_seed)
  if (!isTRUE(all.equal(diag(cov(scores)), score_variance, tolerance = 1e-10))) {
    stop("score variances do not match the requested decreasing order")
  }

  response_loadings <- matrix(0, nrow = 2L, ncol = n_comp)
  response_loadings[1L, predictive_components[1L]] <-
    1 / sqrt(score_variance[predictive_components[1L]])
  response_loadings[2L, predictive_components[2L]] <-
    1 / sqrt(score_variance[predictive_components[2L]])

  X_true_reference <- scores %*% t(loadings)
  Y_true <- scores %*% t(response_loadings)
  Beta_true_reference <- loadings %*%
    solve(crossprod(loadings), t(response_loadings))
  if (max(abs(X_true_reference %*% Beta_true_reference - Y_true)) > 1e-8) {
    stop("the predictive-order regression truth is not exact")
  }

  X_true_locations <- X_true_reference[, location_index, drop = FALSE]
  Beta_true_locations <- Beta_true_reference[location_index, , drop = FALSE]
  X_last_component <- scores[, n_comp, drop = FALSE] %*%
    t(loadings_locations[, n_comp, drop = FALSE])

  sigma_X <- sqrt(
    test_options$noise$NSR_X_final_component * mean(X_last_component^2)
  )
  sigma_Y <- sqrt(test_options$noise$NSR_Y * colMeans(Y_true^2))
  set.seed(data_seed * 10000L)
  X_noise <- scale(
    matrix(rnorm(n_units * nrow(locations), sd = sigma_X), nrow = n_units),
    center = TRUE, scale = FALSE
  )
  Y_noise <- sweep(
    matrix(rnorm(n_units * nrow(response_loadings)), nrow = n_units),
    2L, sigma_Y, "*"
  )
  Y_noise <- scale(Y_noise, center = TRUE, scale = FALSE)

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
      X_latent_scores = scores,
      X_loadings_locations = loadings_locations
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
      realized_NSR_X = sigma_X^2 / mean(X_true_locations^2),
      requested_NSR_X_final_component = test_options$noise$NSR_X_final_component,
      requested_NSR_Y = test_options$noise$NSR_Y
    ),
    provenance = list(
      generator = "experimental predictive-component ordering design",
      location_method = test_options$data$location_method
    )
  )
}
