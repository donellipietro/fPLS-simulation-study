# = ========================================================================== =
# - Script: native_wrapper.R
# - Desc: Thin file/process adapter around the native fdaPDE-cpp driver.
# = ========================================================================== =

git_commit <- function(path) {
  output <- system2(
    "git",
    c("-C", shQuote(normalizePath(path)), "rev-parse", "HEAD"),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop(glue::glue("cannot resolve git commit at {path}"))
  trimws(output[1])
}

read_cpp_matrix <- function(file) {
  value <- as.matrix(suppressWarnings(read.csv(file, check.names = FALSE)))
  storage.mode(value) <- "double"
  value
}

check_matrix_shape <- function(value, rows, cols, label) {
  if (!identical(dim(value), c(as.integer(rows), as.integer(cols)))) {
    stop(glue::glue(
      "{label} shape mismatch: got {paste(dim(value), collapse = ' x ')}, ",
      "expected {rows} x {cols}"
    ))
  }
}

fit_native_fpls <- function(model_name, data, path_list, test_options) {
  if (!identical(model_name, "R1_fPLS")) {
    stop(glue::glue("The model {model_name} does not exist"))
  }

  cfg <- load_config()
  raw_dir <- file.path(path_list$batch, "raw", model_name)
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  X_file <- file.path(raw_dir, "X.csv")
  Y_file <- file.path(raw_dir, "Y.csv")
  locations_file <- file.path(raw_dir, "locations.csv")
  evaluation_file <- file.path(raw_dir, "evaluation.csv")
  params_file <- file.path(raw_dir, "params.json")
  log_file <- file.path(
    path_list$logs,
    glue::glue("{test_options$name_test}_batch_{test_options$batch_index}_{model_name}.log")
  )

  write.csv(data$X, X_file, row.names = FALSE)
  write.csv(data$Y, Y_file, row.names = FALSE)
  write.csv(data$locations, locations_file, row.names = FALSE)
  write.csv(data$evaluation, evaluation_file, row.names = FALSE)

  outer_commit <- git_commit(cfg$PATH_FDAPDE_CPP)
  core_commit <- git_commit(file.path(cfg$PATH_FDAPDE_CPP, "fdaPDE", "core"))
  provenance <- c(
    test_options$provenance,
    list(
      suite = test_suite,
      family = test_options$data$family,
      scenario = test_options$name_test,
      batch_index = test_options$batch_index,
      data_seed = data$data_seed,
      location_seed = data$location_seed,
      location_method = test_options$data$location_method,
      location_seed_status = test_options$data$location_seed_status,
      source_k = test_options$dimensions$source_k,
      n_stat_units = data$dimensions$n_stat_units,
      n_locations = data$dimensions$n_locs,
      NSR_X_final_component = test_options$noise$NSR_X_final_component,
      NSR_Y = test_options$noise$NSR_Y,
      runtime_profile = Sys.getenv("TESTBENCH_PROFILE", unset = "unknown"),
      run_settings_status = test_options$test_options$run_settings_status,
      outer_branch = cfg$FDAPDE_CPP_BRANCH,
      outer_commit = outer_commit,
      core_commit = core_commit
    )
  )
  params <- list(
    n_comp = test_options$model$n_comp,
    center = test_options$model$center,
    calibration = test_options$regularization$calibration,
    fixed_direction_lambda = test_options$regularization$fixed_direction_lambda,
    fixed_loading_lambda = test_options$regularization$fixed_loading_lambda,
    lambda_grid = test_options$regularization$lambda_grid,
    gcv_seed = test_options$regularization$gcv_seed,
    gcv_probes = test_options$regularization$gcv_probes,
    max_iter = test_options$regularization$max_iter,
    tolerance = test_options$regularization$tolerance,
    X_file = X_file,
    Y_file = Y_file,
    locations_file = locations_file,
    evaluation_file = evaluation_file,
    output_dir = raw_dir,
    provenance = provenance
  )
  if (test_options$model$dimension == 1L) {
    params$n_mesh_nodes <- test_options$dimensions$source_k
  } else {
    params$n_mesh_nodes_per_axis <- test_options$dimensions$mesh_nodes_per_axis
  }
  write_json(params, params_file, auto_unbox = TRUE, digits = NA, pretty = TRUE)

  binary <- file.path(path_list$cpp_script, "fit_model")
  runner <- file.path(path_list$repo, "cpp", "run.sh")
  command <- glue::glue(
    "{shQuote(runner)} --quiet -- {shQuote(binary)} {shQuote(params_file)} ",
    "> {shQuote(log_file)} 2>&1"
  )
  run_stats <- system_with_memory(command, ignore.stdout = IGNORE_CPP_OUTPUT)
  if (!identical(run_stats$status, 0L)) {
    stop(glue::glue("C++ fit failed; see {log_file}"))
  }
  if (!is.finite(run_stats$peak_ram_mib)) stop("peak RAM measurement unavailable")

  telemetry <- fromJSON(file.path(raw_dir, "telemetry.json"), simplifyVector = TRUE)
  expected_discretization <- if (data$dimension == 1L) "spline" else "fem"
  if (!identical(telemetry$discretization, expected_discretization)) {
    stop("C++ discretization does not match the requested dimension")
  }
  if (!identical(telemetry$provenance$outer_commit, outer_commit) ||
      !identical(telemetry$provenance$core_commit, core_commit)) {
    stop("C++ provenance does not match the prepared fdaPDE stack")
  }

  n_units <- nrow(data$X)
  n_locs <- ncol(data$X)
  n_responses <- ncol(data$Y)
  n_comp <- test_options$model$n_comp
  n_basis <- telemetry$n_basis
  n_evaluation <- nrow(data$evaluation)

  raw <- list(
    X_space_directions = read_cpp_matrix(file.path(raw_dir, "x_space_directions_coefficients.csv")),
    X_space_directions_locations = read_cpp_matrix(file.path(raw_dir, "x_space_directions_locations.csv")),
    Y_space_directions = read_cpp_matrix(file.path(raw_dir, "y_space_directions.csv")),
    X_latent_scores = read_cpp_matrix(file.path(raw_dir, "x_latent_scores.csv")),
    Y_latent_scores = read_cpp_matrix(file.path(raw_dir, "y_latent_scores.csv")),
    X_loadings = read_cpp_matrix(file.path(raw_dir, "x_loadings_coefficients.csv")),
    X_loadings_locations = read_cpp_matrix(file.path(raw_dir, "x_loadings_locations.csv")),
    Y_loadings = read_cpp_matrix(file.path(raw_dir, "y_loadings.csv")),
    direction_lambdas = read_cpp_matrix(file.path(raw_dir, "direction_lambdas.csv")),
    loading_lambdas = read_cpp_matrix(file.path(raw_dir, "loading_lambdas.csv")),
    X_mean_locations = read_cpp_matrix(file.path(raw_dir, "x_mean_locations.csv")),
    Y_mean = read_cpp_matrix(file.path(raw_dir, "y_mean.csv"))
  )
  check_matrix_shape(raw$X_space_directions, n_basis, n_comp, "X directions")
  check_matrix_shape(raw$X_space_directions_locations, n_locs, n_comp, "located X directions")
  check_matrix_shape(raw$Y_space_directions, n_responses, n_comp, "Y directions")
  check_matrix_shape(raw$X_latent_scores, n_units, n_comp, "X scores")
  check_matrix_shape(raw$Y_latent_scores, n_units, n_comp, "Y scores")
  check_matrix_shape(raw$X_loadings, n_basis, n_comp, "X loadings")
  check_matrix_shape(raw$X_loadings_locations, n_locs, n_comp, "located X loadings")
  check_matrix_shape(raw$Y_loadings, n_responses, n_comp, "Y loadings")
  check_matrix_shape(raw$direction_lambdas, n_comp, 1L, "direction lambdas")
  check_matrix_shape(raw$loading_lambdas, n_comp, 1L, "loading lambdas")
  check_matrix_shape(raw$X_mean_locations, 1L, n_locs, "X mean")
  check_matrix_shape(raw$Y_mean, 1L, n_responses, "Y mean")

  raw$Y_hat <- vector("list", n_comp)
  raw$X_hat_locations <- vector("list", n_comp)
  raw$Beta_coefficients <- vector("list", n_comp)
  raw$Beta_locations <- vector("list", n_comp)
  raw$Beta_evaluation <- vector("list", n_comp)
  for (h in seq_len(n_comp)) {
    suffix <- glue::glue("_h{h}.csv")
    raw$Y_hat[[h]] <- read_cpp_matrix(file.path(raw_dir, glue::glue("y_hat{suffix}")))
    raw$X_hat_locations[[h]] <- read_cpp_matrix(file.path(raw_dir, glue::glue("x_hat_locations{suffix}")))
    raw$Beta_coefficients[[h]] <- read_cpp_matrix(file.path(raw_dir, glue::glue("beta_coefficients{suffix}")))
    raw$Beta_locations[[h]] <- read_cpp_matrix(file.path(raw_dir, glue::glue("beta_locations{suffix}")))
    raw$Beta_evaluation[[h]] <- read_cpp_matrix(file.path(raw_dir, glue::glue("beta_evaluation{suffix}")))
    check_matrix_shape(raw$Y_hat[[h]], n_units, n_responses, glue::glue("Y hat h={h}"))
    check_matrix_shape(raw$X_hat_locations[[h]], n_units, n_locs, glue::glue("X hat h={h}"))
    check_matrix_shape(raw$Beta_coefficients[[h]], n_basis, n_responses, glue::glue("beta coefficients h={h}"))
    check_matrix_shape(raw$Beta_locations[[h]], n_locs, n_responses, glue::glue("beta locations h={h}"))
    check_matrix_shape(raw$Beta_evaluation[[h]], n_evaluation, n_responses, glue::glue("beta evaluation h={h}"))
  }

  list(
    MODE = "R1_fPLS",
    results = c(
      raw,
      list(
        telemetry = telemetry,
        provenance = telemetry$provenance,
        raw_output_dir = raw_dir,
        execution_time = telemetry$wall_seconds,
        peak_ram_mib = run_stats$peak_ram_mib,
        cpu_seconds = telemetry$cpu_seconds,
        cpu_usage_percent = telemetry$cpu_usage_percent,
        setup_seconds = telemetry$setup_seconds,
        fit_seconds = telemetry$fit_seconds,
        output_seconds = telemetry$output_seconds,
        n_basis = telemetry$n_basis,
        calibration = telemetry$calibration
      )
    ),
    model_traits = list(is_functional = TRUE, has_interpolator = TRUE)
  )
}

## Function: fit_model ----
# - Desc: Standard testbench wrapper signature for native and R competitors.
fit_model <- function(model_name, domain, data, path_list, test_options) {
  if (identical(model_name, "R1_fPLS")) {
    return(fit_native_fpls(model_name, data, path_list, test_options))
  }
  if (identical(model_name, "MV_PLS")) {
    return(fit_mv_pls_competitor(data, test_options))
  }
  fit_functional_competitor(model_name, data, test_options)
}
