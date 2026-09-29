# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the 2D paper, noise, and component-count families.
# = ========================================================================== =

paper_model_catalog <- function() {
  list(
    names = c("MV_PLS", "fPCR", "R1_fPLS"),
    labels = c("MV-PLS", "fPCR", "R1-fPLS"),
    colors = c(
      RColorBrewer::brewer.pal(3, "Greys")[3],
      RColorBrewer::brewer.pal(3, "Greens")[3],
      RColorBrewer::brewer.pal(3, "Blues")[3]
    )
  )
}

## Function: generate_options ----
# - Args:
#   * test_suite: name of the calling test suite
#   * name_main_test: requested 2D experiment family
#   * path_queue: directory where JSON option files are written
# - Desc:
#   Defines one explicit one-factor family and writes one JSON per level.
generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  models <- paper_model_catalog()
  lambda_grid <- 10^(-9:2)
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
    },
    vary_NSRX = {
      varying <- "NSR_X_final_component"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 36L else 1600L
      source_k <- if (SMOKE_TEST) 25L else 900L
    },
    vary_NSRY = {
      varying <- "NSR_Y"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 36L else 1600L
      source_k <- if (SMOKE_TEST) 25L else 900L
    },
    vary_H = {
      varying <- "n_comp"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 36L else 1600L
      source_k <- if (SMOKE_TEST) 25L else 900L
    }
  )

  NSR_X_final_component <- if (name_main_test == "vary_NSRX") c(1, 3, 5, 10) else 3
  NSR_Y <- if (name_main_test == "vary_NSRY") c(0.01, 0.1, 0.5, 1) else 0.1
  n_comp <- if (name_main_test == "vary_H") 5L else 4L

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
      smoke_test = SMOKE_TEST
    ),
    model = list(dimension = 2L, n_comp = n_comp, center = FALSE, discretization = "fem"),
    dimensions = list(
      n_stat_units = n_stat_units,
      n_locs = n_locs,
      source_k = source_k,
      mesh_nodes_per_axis = if (length(source_k) == 1L) as.integer(sqrt(source_k)) else 30L,
      n_reference_per_axis = if (SMOKE_TEST) 10L else 80L
    ),
    data = list(
      family = name_main_test,
      n_signal_components = 4L,
      location_seed = -1L,
      location_method = "base_R_equivalent_of_source_2d_stratified_snap"
    ),
    noise = list(
      NSR_X_final_component = NSR_X_final_component,
      NSR_Y = NSR_Y
    ),
    regularization = list(
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = lambda_grid,
      gcv_seed = 0L,
      gcv_probes = gcv_probes,
      max_iter = 1000L,
      tolerance = 1e-8
    ),
    provenance = list(
      template_commit = "e92e1a14b567572fea8b67a99c320c239e366dec",
      reference_implementation_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      representative_beta_scenario = name_main_test == "vary_n",
      metric_formula = "Y/X: sqrt(mean((estimate-truth)^2)); beta: unit-norm shape RMSE without sign alignment",
      smoke_test = SMOKE_TEST
    )
  )

  name_fun <- function(opts_i, comb_row) {
    value <- comb_row[[varying]]
    level <- if (grepl("NSR", varying)) {
      gsub("[.]", "p", format(value, scientific = FALSE, trim = TRUE))
    } else {
      sprintf("%04d", as.integer(value))
    }
    glue::glue("{name_main_test}_{varying}_{level}")
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
