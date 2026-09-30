# Run from the repository root: Rscript tests/check_beta_rmse.R
check_beta_rmse <- function() {
  directory <- tempfile("beta-rmse-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)

  for (suite in c("1D", "2D")) {
    env <- new.env(parent = globalenv())
    sys.source(file.path("tests", suite, "utils", "models_evaluation.R"), env)
    sys.source(file.path("tests", suite, "utils", "fit_and_evaluate.R"), env)
    sys.source("src/utils/load_results_utils.R", env)
    truth <- cbind(c(1, 2), c(2, -1))
    estimate <- cbind(-3 * truth[, 1], 4 * truth[, 2])
    stopifnot(
      env$source_figure_beta_rmse(3 * truth[, 1], truth[, 1]) < 1e-14,
      abs(env$source_figure_beta_rmse(estimate[, 1], truth[, 1]) - sqrt(2)) < 1e-14,
      is.nan(env$source_figure_beta_rmse(c(0, 0), truth[, 1]))
    )

    data <- list(
      dimensions = list(n_comp = 1L, n_responses = 2L, n_locs = 2L, n_stat_units = 2L),
      truth = list(Y = diag(2), X_locations = diag(2), Beta_locations = truth)
    )
    model_R1_fPLS <- list(results = list(
      Y_hat = list(data$truth$Y), X_hat_locations = list(data$truth$X_locations),
      Beta_locations = list(estimate), direction_lambdas = matrix(1),
      loading_lambdas = matrix(1)
    ))
    options <- list(
      model_names = "R1_fPLS", model_labels = "R1-fPLS", model_colors = "blue",
      name_test = "signed_beta", test_options = list(n_reps = 1L, varying_options = "n_comp")
    )
    evaluation <- env$evaluate_results(model_R1_fPLS, data, options)
    stopifnot(
      abs(evaluation$rmse$Beta1_locations - sqrt(2)) < 1e-14,
      evaluation$rmse$Beta2_locations < 1e-14,
      evaluation$rmse$Y_reconstruction == 0, evaluation$rmse$X_reconstruction_locations == 0,
      identical(evaluation$beta_sign_alignment, FALSE)
    )
    if (suite == "1D") {
      data$truth$prefix <- lapply(data$truth, function(value) list(value))
      options$evaluation <- list(truth_target = "prefix")
      prefix <- env$evaluate_results(model_R1_fPLS, data, options)
      stopifnot(
        abs(prefix$rmse$Beta1_locations - sqrt(2)) < 1e-14,
        abs(env$cosine_similarity(-truth, truth) + 1) < 1e-14,
        abs(env$cosine_similarity(-truth, truth, absolute = TRUE) - 1) < 1e-14
      )
    }

    batch <- file.path(directory, suite, "batch_1")
    dir.create(batch, recursive = TRUE)
    saveRDS(data, file.path(batch, "generated_data.rds"))
    model_file <- file.path(batch, "batch_1_fitted_model_R1_fPLS.RData")
    save(model_R1_fPLS, file = model_file)
    model_hash <- tools::md5sum(model_file)
    evaluation_file <- file.path(batch, "batch_1_results_evaluation.RData")
    for (marker in list(NULL, TRUE)) {
      evaluation$beta_sign_alignment <- marker
      evaluation$rmse$Beta1_locations <- 0
      results_evaluation <- list(R1_fPLS = evaluation)
      save(results_evaluation, file = evaluation_file)
      stopifnot(!env$evaluation_uses_signed_beta(evaluation_file, options$model_names))
      refreshed <- env$load_batch_evaluations(options, batch, 1L)
      stopifnot(
        abs(refreshed$R1_fPLS$rmse$Beta1_locations - sqrt(2)) < 1e-14,
        env$evaluation_uses_signed_beta(evaluation_file, options$model_names),
        identical(tools::md5sum(model_file), model_hash)
      )
    }
    loaded <- env$load_quantitative_results(options, list(results = dirname(batch)))
    stopifnot(
      identical(loaded$beta_sign_alignment, FALSE),
      abs(loaded$rmse$Beta1_locations$R1_fPLS - sqrt(2)) < 1e-14
    )

    # fPCR cache compatibility belongs to the two-dimensional comparison
    if (suite == "1D") next
    model_fPCR <- model_R1_fPLS
    model_fPCR$MODE <- "fPCR"
    model_fPCR$results$telemetry <- list(
      schema_version = 4L, timing_scope = "compute_v2", model = "fPCR",
      calibration = "fixed", n_components = 1L, max_iter = 1000L, tolerance = 1e-8,
      lambda_grid = 1e-4, fixed_direction_lambda = 1e-4, fixed_loading_lambda = 1e-4,
      provenance = list(outer_commit = "commit", core_commit = "commit",
                        outer_diff_fingerprint = "clean", core_diff_fingerprint = "clean")
    )
    options$model_names <- options$model_labels <- "fPCR"
    options$model <- list(n_comp = 1L)
    options$regularization <- model_fPCR$results$telemetry
    env$test_suite <- suite
    env$load_config <- function() list(PATH_FDAPDE_CPP = directory)
    env$git_commit <- function(...) "commit"
    env$git_diff_fingerprint <- function(...) "clean"
    stopifnot(!env$native_model_matches_options(model_fPCR, "fPCR", options))
    unaffected <- model_fPCR
    unaffected$MODE <- unaffected$results$telemetry$model <- "R1_fPLS"
    stopifnot(env$native_model_matches_options(unaffected, "R1_fPLS", options))

    model_file <- file.path(batch, "batch_1_fitted_model_fPCR.RData")
    save(model_fPCR, file = model_file)
    evaluation$beta_sign_alignment <- FALSE
    results_evaluation <- list(fPCR = evaluation)
    save(results_evaluation, file = evaluation_file)
    old_hashes <- tools::md5sum(c(model_file, evaluation_file))
    stopifnot(!env$evaluation_uses_signed_beta(evaluation_file, "fPCR"))
    for (read_old in list(
      function() env$evaluate_results(model_fPCR, data, options),
      function() env$load_batch_evaluations(options, batch, 1L),
      function() env$load_quantitative_results(options, list(results = dirname(batch)))
    )) {
      message <- tryCatch({ read_old(); "" }, error = conditionMessage)
      stopifnot(
        grepl("Outdated fPCR", message, fixed = TRUE),
        identical(tools::md5sum(c(model_file, evaluation_file)), old_hashes)
      )
    }

    model_fPCR$results$telemetry$fpcr_score_map <- "sequential_projection_v1"
    model_fPCR$results$telemetry$schema_version <- 5L
    # the public model schema and corrected score map make the fixed fPCR cache current
    stopifnot(env$native_model_matches_options(model_fPCR, "fPCR", options))
    save(model_fPCR, file = model_file)
    refreshed <- env$load_batch_evaluations(options, batch, 1L)
    loaded <- env$load_quantitative_results(options, list(results = dirname(batch)))
    stopifnot(
      env$evaluation_uses_signed_beta(evaluation_file, "fPCR"),
      identical(refreshed$fPCR$fpcr_score_map, "sequential_projection_v1"),
      identical(loaded$fpcr_score_map, "sequential_projection_v1")
    )
  }
  # Load only the panel functions, without reading archives or generating figures.
  panels <- new.env(parent = globalenv())
  for (script in c("common.R", "S_1D_gcv_sensitivity.R")) {
    for (expr in parse(file.path("paper-figures/scripts", script))) {
      if (is.call(expr) && identical(expr[[1]], as.name("<-")) &&
          is.call(expr[[3]]) && identical(expr[[3]][[1]], as.name("function"))) {
        eval(expr, panels)
      }
    }
  }
  for (loaded in list(list(), list(beta_sign_alignment = TRUE))) {
    for (draw in list(
      function() panels$write_metric_panel(loaded, "Beta1_locations", NULL),
      function() panels$write_performance_panel(loaded, "Beta1_locations", 1L, NULL)
    )) {
      message <- tryCatch({ draw(); "" }, error = conditionMessage)
      stopifnot(grepl("obsolete sign convention", message, fixed = TRUE))
    }
  }
  panels$check_beta_metrics(list(beta_sign_alignment = FALSE), "Beta1_locations")
  panels$check_beta_metrics(list(), "Y_reconstruction")
  outdated <- list(beta_sign_alignment = FALSE, model_names = "fPCR")
  message <- tryCatch({
    panels$write_metric_panel(outdated, "Beta1_locations", NULL, include_fpcr = TRUE)
    ""
  }, error = conditionMessage)
  stopifnot(grepl("Outdated fPCR", message, fixed = TRUE))
  panels$check_beta_metrics(outdated, "Beta1_locations", include_fpcr = FALSE)
  panels$check_beta_metrics(outdated, "Y_reconstruction")
  outdated$fpcr_score_map <- "sequential_projection_v1"
  panels$check_beta_metrics(outdated, "Beta1_locations")
  model_fPCR$results$telemetry$fpcr_score_map <- NULL
  model_file <- file.path(directory, "qualitative_fPCR.RData")
  save(model_fPCR, file = model_file)
  message <- tryCatch({ panels$load_model(model_file, "fPCR"); "" }, error = conditionMessage)
  stopifnot(grepl("Outdated fPCR", message, fixed = TRUE))
  model_fPCR$results$telemetry$fpcr_score_map <- "sequential_projection_v1"
  save(model_fPCR, file = model_file)
  stopifnot(identical(panels$load_model(model_file, "fPCR"), model_fPCR))
  stopifnot(all(panels$normalize_shape(c(-3, -4))[, 1] == c(-0.6, -0.8)))
  cat("Signed beta RMSE, fPCR cache compatibility and panel guards verified.\n")
}

check_beta_rmse()
