# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the 1D paper and noise-robustness experiment families.
# = ========================================================================== =

# use the same model colours in simulation output and manuscript figures
source("src/utils/model_colors.R", local = TRUE)

paper_model_catalog <- function() {
  model_names <- c(
    "MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS", "R1_fPLS"
  )
  list(
    names = model_names,
    labels = c(
      "MV-PLS", "B-fPLS (Regression Splines)",
      "B-fPLS (Smoothing Splines)", "PB-fPLS", "R1-fPLS"
    ),
    colors = unname(model_palette[model_names])
  )
}

## Function: generate_options ----
# - Args:
#   * test_suite: name of the calling test suite
#   * name_main_test: requested 1D experiment family
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
  smoothing_lambda_grid <- if (SMOKE_TEST) c(1e-4, 1e-2) else 10^seq(-9, 2, by = 0.1)
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
    },
    vary_NSRX = {
      varying <- "NSR_X_final_component"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 17L else 200L
      source_k <- if (SMOKE_TEST) 11L else 51L
      competitor_basis_k <- 11L
    },
    vary_NSRY = {
      varying <- "NSR_Y"
      n_stat_units <- if (SMOKE_TEST) 12L else 100L
      n_locs <- if (SMOKE_TEST) 17L else 200L
      source_k <- if (SMOKE_TEST) 11L else 51L
      competitor_basis_k <- 11L
    }
  )

  NSR_X_final_component <- if (name_main_test == "vary_NSRX") c(1, 3, 5, 10) else 3
  NSR_Y <- if (name_main_test == "vary_NSRY") c(0.01, 0.1, 0.5, 1) else 0.1

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
      location_method = "jittered_grid_nearest_unique"
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
    competitors = list(
      basis_k = competitor_basis_k,
      smoothing_lambda_grid = smoothing_lambda_grid,
      pb_lambda_grid = lambda_grid,
      pb_cv_folds = 5L
    ),
    provenance = list(
      template_commit = "e92e1a14b567572fea8b67a99c320c239e366dec",
      reference_implementation_commit = "7fb91720b97661c8f83f675f8915ac96f7465912",
      models_in_run = models$names,
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
      options_list[[i]]$competitors$basis_k <- options_list[[i]]$dimensions$source_k
    }
  }
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
