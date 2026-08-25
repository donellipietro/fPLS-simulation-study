# = ========================================================================== =
# - Script: wrappers.R
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

git_diff_fingerprint <- function(path) {
  output <- system2(
    "git",
    c("-C", shQuote(normalizePath(path)), "diff", "--binary", "HEAD", "--"),
    stdout = TRUE,
    stderr = TRUE
  )
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop(glue::glue("cannot fingerprint git worktree at {path}"))
  }
  if (!length(output)) return("clean")
  file <- tempfile("git-diff-")
  on.exit(unlink(file), add = TRUE)
  writeLines(output, file, useBytes = TRUE)
  unname(tools::md5sum(file))
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

failed_native_model <- function(model_name, data, test_options, raw_dir,
                                run_stats, provenance, status) {
  n_comp <- test_options$model$n_comp
  n_units <- nrow(data$X)
  n_locs <- ncol(data$X)
  n_responses <- ncol(data$Y)
  n_evaluation <- nrow(data$evaluation)
  missing_components <- function(rows, cols) {
    replicate(n_comp, matrix(NaN, rows, cols), simplify = FALSE)
  }
  requested_lambda <- test_options$regularization$fixed_direction_lambda
  diagnostics <- data.frame(
    component = seq_len(n_comp),
    iterations = NaN,
    monotone = 0,
    objective = NaN,
    hit_max_iter = 0,
    finite_solution = 0
  )
  write.csv(diagnostics, file.path(raw_dir, "component_diagnostics.csv"), row.names = FALSE)
  write.csv(
    matrix(requested_lambda, n_comp, 1L),
    file.path(raw_dir, "direction_lambdas.csv"), row.names = FALSE
  )
  write.csv(
    matrix(test_options$regularization$fixed_loading_lambda, n_comp, 1L),
    file.path(raw_dir, "loading_lambdas.csv"), row.names = FALSE
  )
  for (h in seq_len(n_comp)) {
    write.csv(
      data.frame(objective = NaN),
      file.path(raw_dir, glue::glue("objective_history_h{h}.csv")),
      row.names = FALSE
    )
  }

  telemetry <- list(
    schema_version = 4L,
    model = model_name,
    mode = "native_fdaPDE_cpp",
    discretization = "spline",
    calibration = test_options$regularization$calibration,
    n_components = n_comp,
    max_iter = test_options$regularization$max_iter,
    tolerance = test_options$regularization$tolerance,
    gcv_probes = test_options$regularization$gcv_probes,
    gcv_seed = test_options$regularization$gcv_seed,
    lambda_grid = test_options$regularization$lambda_grid,
    fixed_direction_lambda = test_options$regularization$fixed_direction_lambda,
    fixed_loading_lambda = test_options$regularization$fixed_loading_lambda,
    wall_seconds = format_time(run_stats$execution_time),
    iteration_counts_available = FALSE,
    fit_failed = TRUE,
    exit_status = as.integer(status),
    provenance = provenance
  )
  write_json(
    telemetry, file.path(raw_dir, "telemetry.json"),
    auto_unbox = TRUE, digits = NA, pretty = TRUE
  )

  raw <- list(
    Y_hat = missing_components(n_units, n_responses),
    X_hat_locations = missing_components(n_units, n_locs),
    Beta_coefficients = missing_components(1L, n_responses),
    Beta_locations = missing_components(n_locs, n_responses),
    Beta_evaluation = missing_components(n_evaluation, n_responses),
    direction_lambdas = matrix(requested_lambda, n_comp, 1L),
    loading_lambdas = matrix(
      test_options$regularization$fixed_loading_lambda, n_comp, 1L
    ),
    fpca_lambdas = matrix(NaN, n_comp, 1L),
    iteration_counts = diagnostics$iterations,
    monotone = diagnostics$monotone,
    objective = diagnostics$objective,
    hit_max_iter = diagnostics$hit_max_iter,
    finite_solution = diagnostics$finite_solution,
    execution_time = telemetry$wall_seconds,
    peak_ram_mib = run_stats$peak_ram_mib,
    setup_seconds = NaN,
    fit_seconds = telemetry$wall_seconds,
    output_seconds = NaN,
    n_basis = NA_integer_,
    calibration = telemetry$calibration,
    telemetry = telemetry,
    provenance = provenance,
    raw_output_dir = raw_dir
  )
  list(
    MODE = model_name,
    results = raw,
    model_traits = list(is_functional = TRUE, has_interpolator = TRUE)
  )
}

fit_native_model <- function(model_name, data, path_list, test_options) {
  if (!model_name %in% c("R1_fPLS", "fPCR")) {
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
  log_file <- file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt"))

  write.csv(data$X, X_file, row.names = FALSE)
  write.csv(data$Y, Y_file, row.names = FALSE)
  write.csv(data$locations, locations_file, row.names = FALSE)
  write.csv(data$evaluation, evaluation_file, row.names = FALSE)

  outer_commit <- git_commit(cfg$PATH_FDAPDE_CPP)
  core_path <- file.path(cfg$PATH_FDAPDE_CPP, "fdaPDE", "core")
  core_commit <- git_commit(core_path)
  outer_diff_fingerprint <- git_diff_fingerprint(cfg$PATH_FDAPDE_CPP)
  core_diff_fingerprint <- git_diff_fingerprint(core_path)
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
      model = model_name,
      source_k = test_options$dimensions$source_k,
      n_stat_units = data$dimensions$n_stat_units,
      n_locations = data$dimensions$n_locs,
      NSR_X_final_component = test_options$noise$NSR_X_final_component,
      NSR_Y = test_options$noise$NSR_Y,
      runtime_profile = Sys.getenv("TESTBENCH_PROFILE", unset = "unknown"),
      outer_branch = cfg$FDAPDE_CPP_BRANCH,
      outer_commit = outer_commit,
      core_commit = core_commit,
      outer_diff_fingerprint = outer_diff_fingerprint,
      core_diff_fingerprint = core_diff_fingerprint
    )
  )
  params <- list(
    model = model_name,
    n_comp = test_options$model$n_comp,
    center = test_options$model$center,
    calibration = test_options$regularization$calibration,
    fixed_direction_lambda = test_options$regularization$fixed_direction_lambda,
    fixed_loading_lambda = test_options$regularization$fixed_loading_lambda,
    lambda_grid = test_options$regularization$lambda_grid,
    save_gcv_curves = identical(test_suite, "GCV") &&
      identical(test_options$regularization$calibration, "gcv"),
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
    ">> {shQuote(log_file)} 2>&1"
  )
  run_stats <- system_with_memory(command, ignore.stdout = IGNORE_CPP_OUTPUT)
  if (!identical(run_stats$status, 0L)) {
    if (startsWith(test_options$data$family, "small_lambda")) {
      return(failed_native_model(
        model_name, data, test_options, raw_dir, run_stats,
        provenance, run_stats$status
      ))
    }
    stop(glue::glue("C++ fit failed; see {log_file}"))
  }
  if (!is.finite(run_stats$peak_ram_mib)) stop("peak RAM measurement unavailable")

  telemetry <- fromJSON(file.path(raw_dir, "telemetry.json"), simplifyVector = TRUE)
  expected_discretization <- if (data$dimension == 1L) "spline" else "fem"
  if (!identical(telemetry$discretization, expected_discretization)) {
    stop("C++ discretization does not match the requested dimension")
  }
  if (!identical(telemetry$provenance$outer_commit, outer_commit) ||
      !identical(telemetry$provenance$core_commit, core_commit) ||
      !identical(
        telemetry$provenance$outer_diff_fingerprint, outer_diff_fingerprint
      ) ||
      !identical(
        telemetry$provenance$core_diff_fingerprint, core_diff_fingerprint
      )) {
    stop("C++ provenance does not match the prepared fdaPDE stack")
  }

  n_units <- nrow(data$X)
  n_locs <- ncol(data$X)
  n_responses <- ncol(data$Y)
  n_comp <- test_options$model$n_comp
  n_basis <- telemetry$n_basis
  n_evaluation <- nrow(data$evaluation)
  component_diagnostics <- suppressWarnings(read.csv(
    file.path(raw_dir, "component_diagnostics.csv"),
    check.names = FALSE
  ))
  if (!identical(component_diagnostics$component, seq_len(n_comp))) {
    stop("invalid component diagnostics")
  }

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
    Y_mean = read_cpp_matrix(file.path(raw_dir, "y_mean.csv")),
    fpca_lambdas = if (identical(model_name, "fPCR")) {
      read_cpp_matrix(file.path(raw_dir, "fpca_lambdas.csv"))
    } else {
      matrix(NaN, n_comp, 1L)
    },
    iteration_counts = component_diagnostics$iterations,
    monotone = component_diagnostics$monotone,
    objective = component_diagnostics$objective,
    hit_max_iter = component_diagnostics$hit_max_iter,
    finite_solution = component_diagnostics$finite_solution,
    objective_history = lapply(seq_len(n_comp), function(h) {
      as.numeric(read_cpp_matrix(file.path(raw_dir, glue::glue("objective_history_h{h}.csv"))))
    })
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
  check_matrix_shape(raw$fpca_lambdas, n_comp, 1L, "fPCA lambdas")
  if (!isTRUE(all.equal(as.numeric(telemetry$iteration_counts), raw$iteration_counts))) {
    stop("telemetry and component iteration counts do not agree")
  }

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
    MODE = model_name,
    results = c(
      raw,
      list(
        telemetry = telemetry,
        provenance = telemetry$provenance,
        raw_output_dir = raw_dir,
        execution_time = telemetry$wall_seconds,
        peak_ram_mib = run_stats$peak_ram_mib,
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
  if (identical(model_name, "R1_fPLS") &&
      identical(test_options$regularization$calibration, "multivariate")) {
    return(fit_mv_pls_competitor(data, test_options))
  }
  if (model_name %in% c("R1_fPLS", "fPCR")) {
    return(fit_native_model(model_name, data, path_list, test_options))
  }
  if (identical(model_name, "MV_PLS")) {
    return(fit_mv_pls_competitor(data, test_options))
  }
  fit_functional_competitor(model_name, data, test_options)
}
