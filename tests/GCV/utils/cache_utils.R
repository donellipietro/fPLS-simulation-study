# = ========================================================================== =
# - Script: cache_utils.R
# - Desc: Checks saved GCV data and component-prefix evaluations before reuse.
# = ========================================================================== =

# require the same seed, dimensions, reference grid and requested noise levels
batch_matches_options <- function(file, options, batch_index) {
  if (!file.exists(file)) return(FALSE)
  data <- readRDS(file)
  same <- function(left, right) isTRUE(all.equal(left, right))
  # older datasets store the true component count in n_comp
  expected_true_components <- if (is.null(options$data$n_true_comp)) {
    options$model$n_comp
  } else {
    options$data$n_true_comp
  }
  cached_true_components <- if (is.null(data$dimensions$n_true_comp)) {
    data$dimensions$n_comp
  } else {
    data$dimensions$n_true_comp
  }
  # prefix evaluations require the corresponding component-wise ground truth
  prefix_truth_current <- !identical(options$evaluation$truth_target, "prefix") ||
    !is.null(data$truth$prefix)
  same(data$data_seed, batch_index) &&
    same(data$dimensions$n_stat_units, options$dimensions$n_stat_units) &&
    same(data$dimensions$n_comp, options$model$n_comp) &&
    same(cached_true_components, expected_true_components) &&
    same(data$dimensions$n_locs_requested, options$dimensions$n_locs) &&
    same(data$dimensions$source_k, options$dimensions$source_k) &&
    same(nrow(data$evaluation), options$dimensions$n_reference_points) &&
    same(data$noise$requested_NSR_X_final_component, options$noise$NSR_X_final_component) &&
    same(data$noise$requested_NSR_Y, options$noise$NSR_Y) &&
    prefix_truth_current
}

# require signed beta metrics and the requested component-prefix truth target
evaluation_matches_options <- function(file, options) {
  if (!evaluation_uses_signed_beta(file, options$model_names)) return(FALSE)
  if (!identical(options$evaluation$truth_target, "prefix")) return(TRUE)

  # inspect the saved evaluation without loading its objects into the calling script
  contents <- new.env(parent = emptyenv())
  loaded <- tryCatch({
    load(file, envir = contents)
    TRUE
  }, error = function(error) FALSE)
  if (!loaded || !exists("results_evaluation", envir = contents, inherits = FALSE)) {
    return(FALSE)
  }

  # require one value per fitted component for every metric used in the prefix analysis
  expected_rmse <- c(
    "Y_reconstruction", "X_reconstruction_locations", "Beta1_locations"
  )
  expected_cosine <- c(
    "Beta_locations", "X_direction_locations",
    "X_loading_locations", "X_latent_scores"
  )
  all(vapply(options$model_names, function(model_name) {
    evaluation <- contents$results_evaluation[[model_name]]
    if (is.null(evaluation) || !identical(evaluation$truth_target, "prefix")) {
      return(FALSE)
    }
    metrics <- c(evaluation$rmse[expected_rmse], evaluation$cosine[expected_cosine])
    length(metrics) == length(c(expected_rmse, expected_cosine)) &&
      all(vapply(metrics, length, integer(1)) == options$model$n_comp)
  }, logical(1)))
}
