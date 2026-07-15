# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the three requested severe-noise 2D experiment families.
# = ========================================================================== =

paper_model_catalog <- function() {
  list(
    names = c("MV_PLS", "R1_fPLS"),
    labels = c("MV-PLS", "R1-fPLS (GCV Calibration)"),
    colors = c(
      RColorBrewer::brewer.pal(3, "Greys")[3],
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
  n_reps <- if (SMOKE_TEST) 1L else 30L
  gcv_probes <- if (SMOKE_TEST) 5L else 100L

  ## Family-specific dimensions ----
  switch(name_main_test,
    vary_k = {
      varying <- "source_k"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 36L else 1600L
      source_k <- if (SMOKE_TEST) 25L else c(25L, 100L, 400L, 900L, 1600L, 2500L)
    },
    vary_n = {
      varying <- "n_stat_units"
      n_stat_units <- if (SMOKE_TEST) 12L else c(50L, 100L, 200L)
      n_locs <- if (SMOKE_TEST) 36L else 1600L
      source_k <- if (SMOKE_TEST) 25L else 900L
    },
    vary_m = {
      varying <- "n_locs"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 36L else c(900L, 1600L, 2400L)
      source_k <- if (SMOKE_TEST) 25L else 900L
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
    model = list(dimension = 2L, n_comp = 4L, center = FALSE, discretization = "fem"),
    dimensions = list(
      n_stat_units = n_stat_units,
      n_locs = n_locs,
      source_k = source_k,
      mesh_nodes_per_axis = if (length(source_k) == 1L) as.integer(sqrt(source_k)) else 30L,
      n_reference_per_axis = if (SMOKE_TEST) 10L else 80L
    ),
    data = list(
      family = name_main_test,
      location_seed = -1L,
      location_seed_status = "source_2d_seed",
      location_method = "base_R_equivalent_of_source_2d_stratified_snap"
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
    competitors = list(implementation_status = "candidate_pending_explicit_acceptance"),
    provenance = list(
      template_commit = "e92e1a14b567572fea8b67a99c320c239e366dec",
      historical_design_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      submitted_paper_models = models$names,
      family_scope = if (name_main_test == "vary_n") "submitted_main_paper_family" else "pietro_requested_historical_family",
      representative_beta_scenario = name_main_test == "vary_n",
      settings_status = "provisional_source_era",
      metric_status = "provisional_submitted_paper_formula",
      metric_formula = "frobenius_error/(nrow*ncol*frobenius_truth)",
      source_k_status = "historical_scenario_label_pending_basis_semantics_decision",
      comparator_status = "candidate_pending_explicit_acceptance",
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
      options_list[[i]]$dimensions$mesh_nodes_per_axis <- as.integer(
        sqrt(options_list[[i]]$dimensions$source_k)
      )
    }
  }
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
