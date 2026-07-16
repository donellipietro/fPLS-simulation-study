fit_rank_one_pls <- function(Y, X, n_comp) {
  Y <- as.matrix(Y)
  X <- as.matrix(X)
  n_units <- nrow(X)
  n_responses <- ncol(Y)
  n_predictors <- ncol(X)

  W <- matrix(0, n_predictors, n_comp)
  V <- matrix(0, n_responses, n_comp)
  T_scores <- matrix(0, n_units, n_comp)
  U_scores <- matrix(0, n_units, n_comp)
  R_loadings <- matrix(0, n_predictors, n_comp)
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
    if (score_norm <= .Machine$double.eps) stop("PLS score has zero norm")
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

nearest_evaluation <- function(locations, evaluation, values) {
  index <- vapply(seq_len(nrow(evaluation)), function(i) {
    delta <- locations - matrix(
      evaluation[i, ], nrow(locations), ncol(locations), byrow = TRUE
    )
    which.min(rowSums(delta^2))
  }, integer(1))
  values[index, , drop = FALSE]
}

competitor_provenance <- function(model_name, test_options, data) {
  c(
    test_options$provenance,
    list(
      suite = test_suite,
      family = test_options$data$family,
      scenario = test_options$name_test,
      batch_index = test_options$batch_index,
      data_seed = data$data_seed,
      model = model_name,
      comparator_implementation = "candidate_paper_definition",
      comparator_status = test_options$provenance$comparator_status,
      run_settings_status = test_options$test_options$run_settings_status
    )
  )
}

finish_r_model <- function(model_name, raw, elapsed, cpu_seconds, peak_ram_mib,
                           n_basis, calibration, selected_lambda, provenance) {
  n_comp <- length(raw$Y_hat)
  lambdas <- matrix(rep(selected_lambda, n_comp), ncol = 1L)
  raw$direction_lambdas <- lambdas
  raw$loading_lambdas <- lambdas
  raw$n_basis <- as.integer(n_basis)
  raw$execution_time <- elapsed
  raw$peak_ram_mib <- peak_ram_mib
  raw$cpu_seconds <- cpu_seconds
  raw$setup_seconds <- 0
  raw$fit_seconds <- elapsed
  raw$output_seconds <- 0
  raw$calibration <- calibration
  raw$provenance <- provenance
  raw$telemetry <- list(
    schema_version = 1L,
    model = model_name,
    calibration = calibration,
    n_basis = as.integer(n_basis),
    n_components = n_comp,
    selected_lambda = selected_lambda,
    wall_seconds = elapsed,
    cpu_seconds = cpu_seconds,
    peak_ram_mib = peak_ram_mib,
    provenance = provenance
  )

  list(
    MODE = model_name,
    results = raw,
    model_traits = list(
      is_functional = !identical(model_name, "MV_PLS"),
      has_interpolator = !identical(model_name, "MV_PLS")
    )
  )
}

fit_mv_pls_competitor <- function(data, test_options) {
  invisible(gc(reset = TRUE))
  wall_start <- proc.time()[["elapsed"]]
  cpu_start <- sum(proc.time()[c("user.self", "sys.self")])
  fit <- fit_rank_one_pls(data$Y, data$X, test_options$model$n_comp)

  beta_evaluation <- lapply(fit$Beta, function(beta) {
    nearest_evaluation(data$locations, data$evaluation, beta)
  })
  elapsed <- proc.time()[["elapsed"]] - wall_start
  cpu_seconds <- sum(proc.time()[c("user.self", "sys.self")]) - cpu_start
  raw <- list(
    X_space_directions = fit$X_space_directions,
    X_space_directions_locations = fit$X_space_directions,
    Y_space_directions = fit$Y_space_directions,
    X_latent_scores = fit$X_latent_scores,
    Y_latent_scores = fit$Y_latent_scores,
    X_loadings = fit$X_loadings,
    X_loadings_locations = fit$X_loadings,
    Y_loadings = fit$Y_loadings,
    Y_hat = fit$Y_hat,
    X_hat_locations = fit$X_hat,
    Beta_coefficients = fit$Beta,
    Beta_locations = fit$Beta,
    Beta_evaluation = beta_evaluation,
    X_mean_locations = matrix(0, 1L, ncol(data$X)),
    Y_mean = matrix(0, 1L, ncol(data$Y))
  )
  finish_r_model(
    "MV_PLS", raw, elapsed, cpu_seconds, r_peak_memory_mb(),
    ncol(data$X), "none", 0,
    competitor_provenance("MV_PLS", test_options, data)
  )
}
