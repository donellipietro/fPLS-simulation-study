# = ========================================================================== =
# - Script: fit_and_evaluate.R
# - Desc: Fits and evaluates every requested 2D paper model for one batch.
# = ========================================================================== =

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

    if (file.exists(model_file) && !FORCE_FIT) {
      load(model_file)
      model <- get(object_name)
    } else {
      cat(glue::glue("  fitting {model_name}\n", .trim = FALSE))
      model <- fit_model(model_name, domain, data, path_list, test_options)
      assign(object_name, model)
      save(list = object_name, file = model_file)
      rm(list = object_name)
    }
    results_evaluation[[model_name]] <- evaluate_results(model, data, test_options)
  }

  save(index_batch = batch_index, results_evaluation, file = evaluation_file)
  cat("  batch complete\n")
}
