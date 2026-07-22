# = ========================================================================== =
# - Script: fit_and_evaluate.R
# - Desc: Fits and evaluates every requested 1D model for one batch.
# = ========================================================================== =

native_model_matches_options <- function(model, model_name, test_options) {
  timing_current <- identical(model$results$telemetry$timing_scope, "fit_pipeline_v1")
  if (!model_name %in% c("R1_fPLS", "fPCR")) {
    telemetry <- model$results$telemetry
    return(isTRUE(telemetry$schema_version == 3L) &&
             timing_current &&
             (model_name == "MV_PLS" ||
                (isTRUE(all.equal(telemetry$tolerance, test_options$regularization$tolerance)) &&
                 isTRUE(all.equal(telemetry$max_iter, test_options$regularization$max_iter)))))
  }
  if (identical(test_options$regularization$calibration, "multivariate")) {
    return(identical(model$MODE, "MV_PLS") &&
             isTRUE(model$results$telemetry$schema_version == 3L) && timing_current)
  }
  telemetry <- model$results$telemetry
  if (is.null(telemetry)) return(FALSE)
  same <- function(left, right) isTRUE(all.equal(left, right))
  timing_current &&
    same(telemetry$schema_version, 3L) &&
    identical(telemetry$model, model_name) &&
    identical(telemetry$calibration, test_options$regularization$calibration) &&
    same(telemetry$n_components, test_options$model$n_comp) &&
    same(telemetry$max_iter, test_options$regularization$max_iter) &&
    same(telemetry$tolerance, test_options$regularization$tolerance) &&
    same(as.numeric(telemetry$lambda_grid), test_options$regularization$lambda_grid) &&
    (telemetry$calibration != "fixed" || if (model_name == "fPCR") {
      same(telemetry$fixed_loading_lambda, test_options$regularization$fixed_loading_lambda)
    } else {
      same(telemetry$fixed_direction_lambda, test_options$regularization$fixed_direction_lambda) &&
        same(telemetry$fixed_loading_lambda, test_options$regularization$fixed_loading_lambda)
    }) &&
    (model_name != "R1_fPLS" || telemetry$calibration != "gcv" ||
       (same(telemetry$gcv_probes, test_options$regularization$gcv_probes) &&
        same(telemetry$gcv_seed, test_options$regularization$gcv_seed)))
}

fit_and_evaluate_models <- function(path_list, data, domain, batch_index, test_options) {
  results_evaluation <- list()
  evaluation_file <- file.path(
    path_list$batch,
    glue::glue("batch_{batch_index}_results_evaluation.RData")
  )

  for (model_name in test_options$model_names) {
    model_file <- file.path(
      path_list$batch,
      glue::glue("batch_{batch_index}_fitted_model_{model_name}.RData")
    )
    object_name <- glue::glue("model_{model_name}")

    reuse_model <- FALSE
    if (file.exists(model_file) && !FORCE_FIT &&
        !isTRUE(test_options$force_refit_batch)) {
      load(model_file)
      model <- get(object_name)
      reuse_model <- native_model_matches_options(model, model_name, test_options)
    }
    if (!reuse_model) {
      cat(glue::glue("- Fitting model: {model_name} ... ", .trim = FALSE))
      model_start <- proc.time()[["elapsed"]]
      model <- fit_model(model_name, domain, data, path_list, test_options)
      model_elapsed <- proc.time()[["elapsed"]] - model_start
      model$results$fit_seconds <- model_elapsed
      model$results$telemetry$fit_seconds <- model_elapsed
      model$results$telemetry$timing_scope <- "fit_pipeline_v1"
      cat(glue::glue(
        "finished after {round(model_elapsed, 3)} secs\n",
        .trim = FALSE
      ))
      assign(object_name, model)
      save(list = object_name, file = model_file)
      rm(list = object_name)
    }
    results_evaluation[[model_name]] <- evaluate_results(model, data, test_options)
  }

  save(index_batch = batch_index, results_evaluation, file = evaluation_file)
  cat(glue::glue("- Batch {batch_index} completed.\n", .trim = FALSE))
}
