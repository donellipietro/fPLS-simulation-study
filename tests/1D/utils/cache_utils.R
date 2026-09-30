# = ========================================================================== =
# - Script: cache_utils.R
# - Desc: Checks saved 1D data against the requested repetition and simulation settings.
# = ========================================================================== =

# require the same seed, dimensions, reference grid and requested noise levels
batch_matches_options <- function(file, options, batch_index) {
  if (!file.exists(file)) return(FALSE)
  data <- readRDS(file)
  same <- function(left, right) isTRUE(all.equal(left, right))
  same(data$data_seed, batch_index) &&
    same(data$dimensions$n_stat_units, options$dimensions$n_stat_units) &&
    same(data$dimensions$n_comp, options$model$n_comp) &&
    same(data$dimensions$n_locs_requested, options$dimensions$n_locs) &&
    same(data$dimensions$source_k, options$dimensions$source_k) &&
    same(nrow(data$evaluation), options$dimensions$n_reference_points) &&
    same(data$noise$requested_NSR_X_final_component, options$noise$NSR_X_final_component) &&
    same(data$noise$requested_NSR_Y, options$noise$NSR_Y)
}
