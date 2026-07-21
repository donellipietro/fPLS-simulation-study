# = ========================================================================== =
# - Script: generate_data.R
# - Desc: Generates the submitted 1D/2D paper simulation data.
# = ========================================================================== =

rank_one_pls_truth <- function(Y, X, n_comp) {
  n_units <- nrow(X)
  n_responses <- ncol(Y)
  n_locations <- ncol(X)

  W <- matrix(0, n_locations, n_comp)
  V <- matrix(0, n_responses, n_comp)
  T_scores <- matrix(0, n_units, n_comp)
  U_scores <- matrix(0, n_units, n_comp)
  R_loadings <- matrix(0, n_locations, n_comp)
  C_loadings <- matrix(0, n_responses, n_comp)
  X_hat <- vector("list", n_comp)
  Y_hat <- vector("list", n_comp)
  Beta <- vector("list", n_comp)

  X_residual <- X
  Y_residual <- Y
  for (h in seq_len(n_comp)) {
    decomposition <- svd(crossprod(Y_residual, X_residual), nu = 1L, nv = 1L)
    W[, h] <- decomposition$v[, 1]
    V[, h] <- decomposition$u[, 1]
    T_scores[, h] <- X_residual %*% W[, h]
    U_scores[, h] <- Y_residual %*% V[, h]

    score_norm <- sum(T_scores[, h]^2)
    R_loadings[, h] <- crossprod(X_residual, T_scores[, h]) / score_norm
    C_loadings[, h] <- crossprod(Y_residual, T_scores[, h]) / score_norm

    X_residual <- X_residual - T_scores[, h] %*% t(R_loadings[, h])
    Y_residual <- Y_residual - T_scores[, h] %*% t(C_loadings[, h])

    W_h <- W[, seq_len(h), drop = FALSE]
    R_h <- R_loadings[, seq_len(h), drop = FALSE]
    C_h <- C_loadings[, seq_len(h), drop = FALSE]
    Beta[[h]] <- W_h %*% solve(crossprod(R_h, W_h), t(C_h))
    X_hat[[h]] <- T_scores[, seq_len(h), drop = FALSE] %*% t(R_h)
    Y_hat[[h]] <- X %*% Beta[[h]]
  }

  list(
    X_space_directions = W,
    Y_space_directions = V,
    X_latent_scores = T_scores,
    Y_latent_scores = U_scores,
    X_loadings = R_loadings,
    Y_loadings = C_loadings,
    X_hat = X_hat,
    Y_hat = Y_hat,
    Beta = Beta
  )
}

fourier_loading <- function(points, component) {
  frequency <- c(1, 1, 2, 2)[component]
  sine <- c(FALSE, TRUE, FALSE, TRUE)[component]
  angle <- 2 * pi * frequency * points[, 1]
  sqrt(2) * if (sine) sin(angle) else cos(angle)
}

snap_1d_locations <- function(n_locs, reference, seed) {
  if (n_locs > nrow(reference)) stop("1D reference grid is too small")
  set.seed(seed)
  proposed <- seq(0, 1, length.out = n_locs) + rnorm(n_locs, 0, 0.25 / n_locs)
  available <- seq_len(nrow(reference))
  index <- integer(n_locs)
  for (i in seq_len(n_locs)) {
    selected <- which.min((reference[available, 1] - proposed[i])^2)
    index[i] <- available[selected]
    available <- available[-selected]
  }
  reference[sort(index), , drop = FALSE]
}

reference_index <- function(reference, locations) {
  if (ncol(reference) == 1L) {
    return(vapply(locations[, 1], function(x) which.min(abs(reference[, 1] - x)), integer(1)))
  }

  vapply(seq_len(nrow(locations)), function(i) {
    which.min(rowSums((reference - matrix(locations[i, ], nrow(reference), ncol(reference), byrow = TRUE))^2))
  }, integer(1))
}

generate_fpls_data <- function(test_options, data_seed) {
  dimension <- test_options$model$dimension
  n_units <- test_options$dimensions$n_stat_units
  n_comp <- test_options$model$n_comp
  n_locs_requested <- test_options$dimensions$n_locs
  if (dimension != 1L) stop("the 1D suite requires model dimension 1")

  reference <- matrix(
    seq(0, 1, length.out = test_options$dimensions$n_reference_points),
    ncol = 1L
  )
  locations <- snap_1d_locations(
    n_locs_requested,
    reference,
    test_options$data$location_seed
  )
  loading_generator <- fourier_loading
  response_loadings <- matrix(rep(1, n_comp), nrow = 1L)

  n_responses <- nrow(response_loadings)
  loadings <- vapply(
    seq_len(n_comp),
    function(component) loading_generator(reference, component),
    numeric(nrow(reference))
  )
  score_sd <- exp(seq(0, log(0.25), length.out = n_comp))
  set.seed(data_seed)
  sampled_scores <- MASS::mvrnorm(
    n_units,
    mu = rep(0, n_comp),
    Sigma = diag(score_sd^2)
  )
  scores <- scale(sampled_scores, center = TRUE, scale = FALSE)

  X_true_reference <- scores %*% t(loadings)
  Y_true <- scores %*% t(response_loadings)
  truth_pls <- rank_one_pls_truth(Y_true, X_true_reference, n_comp)
  if (max(abs(Y_true - truth_pls$Y_hat[[n_comp]])) > 1e-8 ||
      max(abs(X_true_reference - truth_pls$X_hat[[n_comp]])) > 1e-8) {
    stop("source PLS truth failed its exact reconstruction check")
  }

  location_index <- reference_index(reference, locations)
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
    mu = rep(0, nrow(locations) + n_responses),
    Sigma = diag(c(rep(sigma_X^2, nrow(locations)), sigma_Y^2))
  )
  X_noise <- scale(
    noise[, seq_len(nrow(locations)), drop = FALSE],
    center = TRUE,
    scale = FALSE
  )
  Y_noise <- scale(
    noise[, nrow(locations) + seq_len(n_responses), drop = FALSE],
    center = TRUE,
    scale = FALSE
  )

  list(
    dimension = dimension,
    X = X_true_locations + X_noise,
    Y = Y_true + Y_noise,
    locations = locations,
    evaluation = reference,
    data_seed = data_seed,
    location_seed = test_options$data$location_seed,
    dimensions = list(
      n_stat_units = n_units,
      n_comp = n_comp,
      n_locs_requested = n_locs_requested,
      n_locs = nrow(locations),
      n_responses = n_responses,
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
    noise = list(
      sigma_X = sigma_X,
      sigma_Y = sigma_Y,
      realized_NSR_X = realized_NSR_X,
      requested_NSR_X_final_component = test_options$noise$NSR_X_final_component,
      requested_NSR_Y = test_options$noise$NSR_Y
    ),
    provenance = list(
      generator = "submitted paper design",
      reference_implementation_commit = test_options$provenance$reference_implementation_commit,
      location_method = test_options$data$location_method
    )
  )
}

write_data_illustration <- function(data, file) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  pdf(file, width = 11, height = 5)
  layout(matrix(1:2, nrow = 1L), widths = c(1, 2))

  par(mar = c(4, 4, 3, 1))
  response_range <- range(data$truth$Y[, 1], data$Y[, 1])
  plot(
    data$truth$Y[, 1], data$Y[, 1], type = "n",
    xlim = response_range, ylim = response_range, asp = 1,
    xlab = expression(Y[true]), ylab = expression(Y),
    main = expression(bolditalic(Y~vs~Y[true]))
  )
  grid()
  abline(0, 1, col = "grey70", lty = 2)
  points(data$truth$Y[, 1], data$Y[, 1], pch = 20)

  units <- seq_len(min(4L, nrow(data$X)))
  colors <- RColorBrewer::brewer.pal(5, "RdPu")[2:5]
  predictor_range <- range(
    data$truth$X_reference[units, , drop = FALSE],
    data$X[units, , drop = FALSE]
  )
  par(mar = c(4, 3, 3, 1))
  plot(
    NA_real_, NA_real_, xlim = range(data$evaluation[, 1]), ylim = predictor_range,
    xlab = "t", ylab = expression(X(t)), yaxt = "n",
    main = expression(bolditalic(X~vs~X[true]))
  )
  grid()
  matlines(
    data$evaluation[, 1], t(data$truth$X_reference[units, , drop = FALSE]),
    lty = 1, lwd = 2, col = colors
  )
  matlines(
    data$locations[, 1], t(data$X[units, , drop = FALSE]),
    lty = 2, lwd = 1, col = colors
  )
  matpoints(
    data$locations[, 1], t(data$X[units, , drop = FALSE]),
    pch = 20, cex = 0.55, col = colors
  )
  dev.off()
}
