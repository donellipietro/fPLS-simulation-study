# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the three severe-noise 1D paper experiment families.
# = ========================================================================== =

paper_model_catalog <- function() {
  list(
    names = c(
      "MV_PLS", "B_fPLS", "B_fPLS_smooth",
      "PB_fPLS_submitted", "PB_fPLS_paper", "R1_fPLS"
    ),
    labels = c(
      "MV-PLS", "B-fPLS (Regression Splines)",
      "B-fPLS (Smoothing Splines)", "PB-fPLS (Submitted CV)",
      "PB-fPLS (Paper CV)",
      "R1-fPLS"
    ),
    colors = c(
      RColorBrewer::brewer.pal(3, "Greys")[3],
      RColorBrewer::brewer.pal(9, "RdPu")[c(4, 6, 8, 9)],
      RColorBrewer::brewer.pal(3, "Blues")[3]
    )
  )
}

## Function: generate_options ----
# - Args:
#   * test_suite: name of the calling test suite
#   * name_main_test: vary_k, vary_n, or vary_m
#   * path_queue: directory where JSON option files are written
# - Desc:
#   Defines one explicit one-factor family and writes one JSON per level.
generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  models <- paper_model_catalog()
  lambda_grid <- if (SMOKE_TEST) c(1e-4, 1e-2) else 10^seq(-9, 2, by = 0.1)
  pb_lambda_grid <- 10^(-9:2)
  n_reps <- if (SMOKE_TEST) 1L else 30L
  gcv_probes <- if (SMOKE_TEST) 5L else 100L

  ## Family-specific dimensions ----
  switch(name_main_test,
    vary_k = {
      varying <- "source_k"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 17L else 200L
      source_k <- if (SMOKE_TEST) 11L else c(5L, 11L, 21L, 51L, 101L)
      competitor_basis_k <- source_k
    },
    vary_n = {
      varying <- "n_stat_units"
      n_stat_units <- if (SMOKE_TEST) 12L else c(50L, 100L, 200L)
      n_locs <- if (SMOKE_TEST) 17L else 200L
      source_k <- if (SMOKE_TEST) 11L else 51L
      competitor_basis_k <- 11L
    },
    vary_m = {
      varying <- "n_locs"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 17L else c(50L, 100L, 200L)
      source_k <- if (SMOKE_TEST) 11L else 51L
      competitor_basis_k <- 11L
    }
  )

  ## Explicit scientific and execution options ----
  options <- list(
    model_names = models$names,
    model_labels = models$labels,
    model_colors = models$colors,
    cpp_script = test_suite,
    test_options = list(
      n_reps = n_reps,
      varying_options = varying,
      threading = "single",
      smoke_test = SMOKE_TEST,
      run_settings_status = if (SMOKE_TEST) "infrastructure_smoke_override" else "provisional_source_era"
    ),
    model = list(dimension = 1L, n_comp = 4L, center = FALSE, discretization = "spline"),
    dimensions = list(
      n_stat_units = n_stat_units,
      n_locs = n_locs,
      source_k = source_k,
      n_reference_points = if (SMOKE_TEST) 41L else 500L
    ),
    data = list(
      family = name_main_test,
      location_seed = 0L,
      location_seed_status = "provisional_replacement_for_unrecorded_source_rng",
      location_method = "jittered_grid_nearest_unique"
    ),
    noise = list(NSR_X_final_component = 3, NSR_Y = 0.1),
    regularization = list(
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = lambda_grid,
      gcv_seed = 0L,
      gcv_probes = gcv_probes,
      max_iter = 20L,
      tolerance = 1e-6,
      status = if (SMOKE_TEST) "infrastructure_smoke_override" else "provisional_source_era"
    ),
    competitors = list(
      basis_k = competitor_basis_k,
      smoothing_lambda_grid = lambda_grid,
      pb_lambda_grid = pb_lambda_grid,
      pb_submitted_cv_folds = 5L,
      pb_paper_cv_folds = 10L,
      implementation_status = "paired_pb_cv_comparison_pending_full_validation"
    ),
    provenance = list(
      template_commit = "e92e1a14b567572fea8b67a99c320c239e366dec",
      historical_design_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      submitted_paper_models = c("MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS", "R1_fPLS"),
      models_in_run = models$names,
      family_scope = if (name_main_test == "vary_m") "submitted_supplement_family" else "submitted_main_paper_family",
      settings_status = "provisional_source_era",
      metric_status = "provisional_source_figure_metric",
      metric_formula = "Y/X: sqrt(mean((estimate-truth)^2)); beta: sign-aligned unit-norm shape RMSE",
      submitted_metric_status = "provisional_submitted_paper_formula",
      submitted_metric_formula = "frobenius_error/(nrow*ncol*frobenius_truth)",
      source_k_status = "historical_scenario_label_actual_basis_count_may_differ",
      comparator_status = "paired_pb_cv_comparison_pending_full_validation",
      beta_mapping = "historical_corrected_source_projection",
      pb_cv_status = "submitted_five_fold_untransformed_vs_paper_ten_fold_transformed_fixed_component_trajectory",
      smoke_override = SMOKE_TEST,
      paper_design_complete = FALSE,
      paper_results_reproduced = FALSE
    )
  )

  name_fun <- function(opts_i, comb_row) {
    glue::glue("{name_main_test}_{varying}_{sprintf('%04d', as.integer(comb_row[[varying]]))}")
  }
  options_list <- explode_options(options, by = varying, name_fun = name_fun)
  if (name_main_test == "vary_k") {
    for (i in seq_along(options_list)) {
      options_list[[i]]$competitors$basis_k <- options_list[[i]]$dimensions$source_k
    }
  }
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
