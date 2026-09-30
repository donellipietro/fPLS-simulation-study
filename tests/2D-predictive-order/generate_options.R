# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the experimental 2D predictive-order experiment.
# = ========================================================================== =

# use the same model colours in simulation output and manuscript figures
source("src/utils/model_colors.R", local = TRUE)

predictive_order_model_catalog <- function() {
  model_names <- c("MV_PLS", "fPCR", "R1_fPLS")
  list(
    names = model_names,
    labels = c("MV-PLS", "fPCR", "R1-fPLS"),
    colors = unname(model_palette[model_names])
  )
}

## Function: generate_options ----
# - Args:
#   * test_suite: name of the calling test suite
#   * name_main_test: requested experiment family
#   * path_queue: directory where JSON option files are written
# - Desc:
#   Fits ten components once and evaluates every progressive prefix.
generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  models <- predictive_order_model_catalog()
  score_sd <- exp(seq(0, log(0.25), length.out = 10L))
  n_reps <- if (SMOKE_TEST) 1L else 30L

  options <- list(
    model_names = models$names,
    model_labels = models$labels,
    model_colors = models$colors,
    cpp_script = test_suite,
    test_options = list(
      n_reps = n_reps,
      varying_options = "n_comp",
      threading = "single",
      smoke_test = SMOKE_TEST
    ),
    model = list(dimension = 2L, n_comp = 10L, center = FALSE, discretization = "fem"),
    dimensions = list(
      n_stat_units = if (SMOKE_TEST) 12L else 100L,
      n_locs = if (SMOKE_TEST) 36L else 1600L,
      source_k = if (SMOKE_TEST) 25L else 900L,
      mesh_nodes_per_axis = if (SMOKE_TEST) 5L else 30L,
      n_reference_per_axis = if (SMOKE_TEST) 10L else 80L
    ),
    data = list(
      family = name_main_test,
      design_version = 4L,
      n_signal_components = 10L,
      predictive_components = c(9L, 10L),
      score_variance = score_sd^2,
      location_seed = -1L,
      location_method = "base_R_equivalent_of_source_2d_stratified_snap"
    ),
    noise = list(NSR_X_final_component = 3, NSR_Y = 0.1),
    regularization = list(
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = 10^(-9:2),
      gcv_seed = 0L,
      gcv_probes = if (SMOKE_TEST) 5L else 100L,
      max_iter = 1000L,
      tolerance = 1e-8
    ),
    provenance = list(
      metric_formula = paste(
        "Y/X: sqrt(mean((estimate-truth)^2));",
        "beta: unit-norm shape RMSE without sign alignment"
      ),
      smoke_test = SMOKE_TEST
    )
  )

  options_list <- explode_options(
    options,
    by = "n_comp",
    name_fun = function(opts_i, comb_row) {
      glue::glue("{name_main_test}_n_comp_{sprintf('%02d', comb_row$n_comp)}")
    }
  )
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
