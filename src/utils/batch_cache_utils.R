# = ========================================================================== =
# - Script: batch_cache_utils.R
# - Desc: Shared checks for reusing fitted simulation models.
# = ========================================================================== =

# require every requested saved model to pass its suite's compatibility checks
models_match_options <- function(files, names, options) {
  all(mapply(function(file, model_name) {
    if (!file.exists(file)) return(FALSE)
    object_name <- glue::glue("model_{model_name}")
    load(file)
    # compare saved solver controls, model schema and suite-specific telemetry
    native_model_matches_options(get(object_name), model_name, options)
  }, files, names))
}
