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
  raw$cpu_usage_percent <- if (elapsed > 0) 100 * cpu_seconds / elapsed else 0
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

symmetric_sqrt <- function(value) {
  decomposition <- eigen((value + t(value)) / 2, symmetric = TRUE)
  if (min(decomposition$values) <= 0) stop("functional metric is not positive definite")
  decomposition$vectors %*%
    diag(sqrt(decomposition$values), nrow = length(decomposition$values)) %*%
    t(decomposition$vectors)
}

fit_basis_coefficients <- function(X, Psi, penalty, lambda) {
  system <- crossprod(Psi) + lambda * penalty
  t(solve(system, crossprod(Psi, t(X))))
}

select_modal_gcv_lambda <- function(X, Psi, penalty, lambda_grid) {
  gram <- crossprod(Psi)
  systems <- lapply(lambda_grid, function(lambda) solve(gram + lambda * penalty))
  effective_df <- vapply(systems, function(inverse) sum(diag(inverse %*% gram)), numeric(1))
  selected_index <- vapply(seq_len(nrow(X)), function(i) {
    y <- X[i, ]
    scores <- vapply(seq_along(lambda_grid), function(j) {
      coefficients <- systems[[j]] %*% crossprod(Psi, y)
      residual <- y - Psi %*% coefficients
      mean(residual^2) / (1 - effective_df[j] / nrow(Psi))^2
    }, numeric(1))
    which.min(scores)
  }, integer(1))
  counts <- tabulate(selected_index, nbins = length(lambda_grid))
  list(
    lambda = lambda_grid[which.max(counts)],
    selected_by_curve = lambda_grid[selected_index],
    counts = counts
  )
}

fit_metric_pls <- function(Y, A, mass, penalty, lambda, n_comp) {
  metric_sqrt <- symmetric_sqrt(mass + lambda * penalty)
  inverse_sqrt <- solve(metric_sqrt)
  transformed_X <- A %*% mass %*% inverse_sqrt
  list(
    fit = fit_rank_one_pls(Y, transformed_X, n_comp),
    metric_sqrt = metric_sqrt,
    inverse_sqrt = inverse_sqrt
  )
}

select_pb_lambda <- function(Y, A, mass, penalty, lambda_grid, n_comp, folds, seed) {
  n_units <- nrow(A)
  folds <- min(as.integer(folds), n_units)
  set.seed(seed)
  fold_id <- sample(rep(seq_len(folds), length.out = n_units))
  cv_error <- vapply(lambda_grid, function(lambda) {
    fold_error <- vapply(seq_len(folds), function(fold) {
      train <- fold_id != fold
      validation <- !train
      metric <- fit_metric_pls(Y[train, , drop = FALSE], A[train, , drop = FALSE],
                               mass, penalty, lambda, n_comp)
      transformed_validation <- A[validation, , drop = FALSE] %*%
        mass %*% metric$inverse_sqrt
      prediction <- transformed_validation %*% metric$fit$Beta[[n_comp]]
      mean((Y[validation, , drop = FALSE] - prediction)^2)
    }, numeric(1))
    mean(fold_error)
  }, numeric(1))
  list(lambda = lambda_grid[which.min(cv_error)], cv_error = cv_error, fold_id = fold_id)
}

fit_functional_competitor <- function(model_name, data, test_options) {
  if (!model_name %in% c("B_fPLS", "B_fPLS_smooth", "PB_fPLS")) {
    stop(glue::glue("Unknown functional competitor: {model_name}"))
  }
  if (data$dimension != 1L || ncol(data$Y) != 1L) {
    stop("B-fPLS and PB-fPLS are paper competitors only in the 1D scalar-response suite")
  }

  invisible(gc(reset = TRUE))
  wall_start <- proc.time()[["elapsed"]]
  cpu_start <- sum(proc.time()[c("user.self", "sys.self")])
  basis_k <- as.integer(test_options$competitors$basis_k)
  basis <- fda::create.bspline.basis(c(0, 1), breaks = seq(0, 1, length.out = basis_k))
  Psi <- fda::eval.basis(data$locations[, 1], basis)
  Psi_evaluation <- fda::eval.basis(data$evaluation[, 1], basis)
  mass <- fda::bsplinepen(basis, Lfdobj = 0)
  penalty <- fda::bsplinepen(basis, Lfdobj = 2)

  smoothing <- list(lambda = 0, selected_by_curve = numeric(), counts = integer())
  if (identical(model_name, "B_fPLS_smooth")) {
    smoothing <- select_modal_gcv_lambda(
      data$X, Psi, penalty, test_options$competitors$smoothing_lambda_grid
    )
  }
  A <- fit_basis_coefficients(data$X, Psi, penalty, smoothing$lambda)

  component_lambda <- 0
  cv <- list(cv_error = numeric(), fold_id = integer())
  if (identical(model_name, "PB_fPLS")) {
    cv <- select_pb_lambda(
      data$Y, A, mass, penalty, test_options$competitors$pb_lambda_grid,
      test_options$model$n_comp, test_options$competitors$cv_folds,
      test_options$competitors$cv_seed + data$data_seed
    )
    component_lambda <- cv$lambda
  }

  metric <- fit_metric_pls(
    data$Y, A, mass, penalty, component_lambda, test_options$model$n_comp
  )
  fit <- metric$fit
  directions <- metric$inverse_sqrt %*% fit$X_space_directions
  loadings <- solve(mass, metric$metric_sqrt %*% fit$X_loadings)
  directions_locations <- Psi %*% directions
  loadings_locations <- Psi %*% loadings
  X_hat_locations <- lapply(seq_len(test_options$model$n_comp), function(h) {
    fit$X_latent_scores[, seq_len(h), drop = FALSE] %*%
      t(loadings_locations[, seq_len(h), drop = FALSE])
  })

  beta_coefficients <- lapply(fit$Beta, function(beta_transformed) {
    metric$inverse_sqrt %*% beta_transformed
  })
  for (h in seq_along(beta_coefficients)) {
    beta_prediction <- A %*% mass %*% beta_coefficients[[h]]
    if (max(abs(beta_prediction - fit$Y_hat[[h]])) > 1e-8) {
      stop("functional beta coefficients do not reproduce the fitted response")
    }
  }
  beta_locations <- lapply(beta_coefficients, function(beta) Psi %*% beta)
  beta_evaluation <- lapply(beta_coefficients, function(beta) Psi_evaluation %*% beta)

  elapsed <- proc.time()[["elapsed"]] - wall_start
  cpu_seconds <- sum(proc.time()[c("user.self", "sys.self")]) - cpu_start
  raw <- list(
    X_space_directions = directions,
    X_space_directions_locations = directions_locations,
    Y_space_directions = fit$Y_space_directions,
    X_latent_scores = fit$X_latent_scores,
    Y_latent_scores = fit$Y_latent_scores,
    X_loadings = loadings,
    X_loadings_locations = loadings_locations,
    Y_loadings = fit$Y_loadings,
    Y_hat = fit$Y_hat,
    X_hat_locations = X_hat_locations,
    Beta_coefficients = beta_coefficients,
    Beta_locations = beta_locations,
    Beta_evaluation = beta_evaluation,
    X_mean_locations = matrix(0, 1L, ncol(data$X)),
    Y_mean = matrix(0, 1L, ncol(data$Y)),
    smoothing_lambda = smoothing$lambda,
    smoothing_lambdas_by_curve = smoothing$selected_by_curve,
    smoothing_lambda_counts = smoothing$counts,
    component_lambda = component_lambda,
    cv_error = cv$cv_error,
    cv_fold_id = cv$fold_id,
    cv_seed = if (model_name == "PB_fPLS") {
      test_options$competitors$cv_seed + data$data_seed
    } else {
      NA_integer_
    },
    basis_k_source = basis_k,
    beta_mapping = "functional_inner_product"
  )
  calibration <- switch(
    model_name,
    B_fPLS = "regression_spline",
    B_fPLS_smooth = "per_curve_gcv_modal_lambda",
    PB_fPLS = "five_fold_cv_penalty"
  )
  finish_r_model(
    model_name, raw, elapsed, cpu_seconds, r_peak_memory_mb(),
    ncol(Psi), calibration,
    if (model_name == "B_fPLS_smooth") smoothing$lambda else component_lambda,
    competitor_provenance(model_name, test_options, data)
  )
}
