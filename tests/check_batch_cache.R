# run from the repository root with Rscript tests/check_batch_cache.R
# check data and saved-model compatibility across all four simulation suites
check_batch_cache <- function() {
  directory <- tempfile("batch-cache-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)

  for (suite in c("1D", "2D", "GCV", "2D-predictive-order")) {
    env <- new.env(parent = globalenv())
    sys.source("src/utils/load_results_utils.R", env)
    sys.source("src/utils/batch_cache_utils.R", env)
    sys.source(file.path("tests", suite, "utils", "cache_utils.R"), env)
    sys.source(file.path("tests", suite, "generate_options.R"), env)
    catalog <- switch(suite,
      "1D" = env$paper_model_catalog(),
      "2D" = env$paper_model_catalog(),
      "GCV" = env$gcv_model_catalog(),
      "2D-predictive-order" = env$predictive_order_model_catalog()
    )
    # the one-dimensional comparisons retain five paper methods; fPCR remains a 2D competitor
    stopifnot(if (suite == "1D") {
      length(catalog$names) == 5L && !"fPCR" %in% catalog$names
    } else if (suite == "GCV") {
      identical(catalog$names, "R1_fPLS")
    } else {
      "fPCR" %in% catalog$names
    })
    if (suite == "1D") {
      # older aggregates may include fPCR; paper readers select the current methods without rewriting archives
      env$results_root <- directory
      definition <- Filter(function(expr) {
        is.call(expr) && identical(expr[[1]], as.name("<-")) &&
          identical(expr[[2]], as.name("read_family"))
      }, as.list(parse("paper-figures/scripts/common.R")))
      eval(definition[[1]], env)
      aggregate_file <- file.path(directory, suite, "aggregate", "all", "loaded_old.rds")
      dir.create(dirname(aggregate_file), recursive = TRUE)
      old <- list(model_names = c(catalog$names, "fPCR"),
                  model_labels = c(catalog$labels, "fPCR"))
      saveRDS(old, aggregate_file)
      before <- tools::md5sum(aggregate_file)
      loaded <- env$read_family(suite, "old")
      stopifnot(identical(loaded$model_names, catalog$names),
                identical(loaded$model_labels, catalog$labels),
                identical(loaded$model_colors, catalog$colors),
                identical(before, tools::md5sum(aggregate_file)))
    }
    options <- list(
      dimensions = list(n_stat_units = 10L, n_locs = 5L, source_k = 11L,
                        n_reference_points = 4L, n_reference_per_axis = 2L),
      model = list(n_comp = 2L), model_names = catalog$names,
      noise = list(NSR_X_final_component = 0.1, NSR_Y = 0.2),
      data = list(n_true_comp = 3L, n_signal_components = 1L,
                  design_version = "design-v1", score_variance = c(1, 0.5)),
      evaluation = list(truth_target = "prefix")
    )
    data <- list(
      data_seed = 1L, evaluation = matrix(0, 4L, 1L),
      dimensions = list(n_stat_units = 10L, n_comp = 2L, n_true_comp = 3L,
                        n_locs_requested = 5L, source_k = 11L, n_signal_components = 1L),
      noise = list(requested_NSR_X_final_component = 0.1, requested_NSR_Y = 0.2),
      truth = list(prefix = list()),
      design = list(version = "design-v1", score_variance = c(1, 0.5))
    )
    data_file <- file.path(directory, "generated_data.rds")
    saveRDS(data, data_file)
    # matching metadata accept the sample, while another repetition or noise level rejects it
    stopifnot(env$batch_matches_options(data_file, options, 1L),
              !env$batch_matches_options(data_file, options, 2L))
    stale <- options
    stale$noise$NSR_Y <- 0.3
    stopifnot(!env$batch_matches_options(data_file, stale, 1L))
    # one-dimensional point counts and two-dimensional axis sizes select the correct grid check
    stale <- options
    if (suite %in% c("1D", "GCV")) {
      stale$dimensions$n_reference_points <- 5L
    } else {
      stale$dimensions$n_reference_per_axis <- 3L
    }
    stopifnot(!env$batch_matches_options(data_file, stale, 1L))

    if (suite == "GCV") {
      stale <- options
      stale$data$n_true_comp <- 4L
      # the generative rank may differ from the fitted rank, but must match its saved value
      stopifnot(!env$batch_matches_options(data_file, stale, 1L))
      missing_truth <- data
      missing_truth$truth$prefix <- NULL
      saveRDS(missing_truth, data_file)
      # missing prefix truth invalidates prefix evaluation without invalidating aggregate truth
      stopifnot(!env$batch_matches_options(data_file, options, 1L))
      stale <- options
      stale$evaluation$truth_target <- "full"
      stopifnot(env$batch_matches_options(data_file, stale, 1L))
      data$dimensions$n_true_comp <- NULL
      stale$data$n_true_comp <- NULL
      saveRDS(data, data_file)
      # legacy data and options both fall back to the fitted component count
      stopifnot(env$batch_matches_options(data_file, stale, 1L))
    }
    if (suite == "2D-predictive-order") {
      for (field in c("design_version", "n_signal_components", "score_variance")) {
        stale <- options
        stale$data[[field]] <- if (field == "design_version") "design-v2" else 9
        # changing any predictive-order design control invalidates the saved sample
        stopifnot(!env$batch_matches_options(data_file, stale, 1L))
      }
    }

    env$native_model_matches_options <- function(model, name, options) {
      identical(model$name, name) && identical(model$n_comp, options$model$n_comp)
    }
    model_files <- file.path(directory, paste0(options$model_names, ".RData"))
    for (index in seq_along(model_files)) {
      object_name <- paste0("model_", options$model_names[index])
      assign(object_name, list(name = options$model_names[index], n_comp = 2L), env)
      save(list = object_name, envir = env, file = model_files[index])
    }
    before <- tools::md5sum(c(data_file, model_files))
    # every named saved model must pass the suite validator, and checks preserve all saved files
    stopifnot(env$models_match_options(model_files, options$model_names, options),
              identical(before, tools::md5sum(c(data_file, model_files))))
    stale <- options
    stale$model$n_comp <- 3L
    stopifnot(!env$models_match_options(model_files, options$model_names, stale))
    unlink(model_files[length(model_files)])
    # an incomplete model set or absent generated sample cannot be reused as a complete batch
    stopifnot(!env$models_match_options(model_files, options$model_names, options))
    unlink(data_file)
    stopifnot(!env$batch_matches_options(data_file, options, 1L))

    if (suite == "GCV") {
      metric <- rep(0, options$model$n_comp)
      evaluation <- list(
        beta_sign_alignment = FALSE,
        truth_target = "prefix",
        rmse = list(Y_reconstruction = metric, X_reconstruction_locations = metric,
                    Beta1_locations = metric),
        cosine = list(Beta_locations = metric, X_direction_locations = metric,
                      X_loading_locations = metric, X_latent_scores = metric)
      )
      results_evaluation <- list(R1_fPLS = evaluation)
      file <- file.path(directory, "evaluation.RData")
      save(results_evaluation, file = file)
      # prefix evaluations must contain every requested component for the fitted fPLS model
      stopifnot(env$evaluation_matches_options(file, options))
      results_evaluation$R1_fPLS$rmse$Beta1_locations <- 0
      save(results_evaluation, file = file)
      stopifnot(!env$evaluation_matches_options(file, options))
    }
    cat("OK batch cache:", suite, "\n")
  }
}

check_batch_cache()
