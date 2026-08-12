# = ========================================================================== =
# - Script: generate_options.R
# - Desc: Generates the one-dimensional GCV diagnostic experiment families.
# = ========================================================================== =

source("tests/1D/utils/generate_options.R")

gcv_model_catalog <- function() {
  list(
    names = "R1_fPLS",
    labels = "R1-fPLS",
    colors = RColorBrewer::brewer.pal(3, "Blues")[3]
  )
}

lambda_level_name <- function(lambda) {
  if (lambda == -1) return("gcv")
  if (lambda == 0) return("mv_pls")
  paste0("1e", as.integer(round(log10(lambda))))
}

standard_lambda_grid <- 10^(-9:2)
sensitivity_lambda_grid <- 10^(-9:-2)
component_lambda_grid <- if (SMOKE_TEST) c(1e-6, 1) else standard_lambda_grid

## Function: generate_options ----
# - Args:
#   * test_suite: name of the calling test suite
#   * name_main_test: requested GCV diagnostic family
#   * path_queue: directory where JSON option files are written
# - Desc:
#   Defines one explicit diagnostic family and writes one JSON per option cell.
generate_options <- function(test_suite, name_main_test, path_queue) {
  mkdir(path_queue)
  if (!name_main_test %in% test_groups$all) {
    stop(glue::glue("The test {name_main_test} does not exist"))
  }

  competitor_reference <- endsWith(name_main_test, "_competitors")
  high_NSRX <- grepl("high_NSRX", name_main_test, fixed = TRUE)
  componentwise_sensitivity <- identical(name_main_test, "sensitivity_componentwise")
  prefix_sensitivity <- name_main_test %in% c(
    "sensitivity", "sensitivity_high_NSRX"
  )
  models <- if (competitor_reference) paper_model_catalog() else gcv_model_catalog()
  near_zero_grid <- 10^c(-300, -200, -100, -50, -30, -20:-9)
  refined_m_lt_k_grid <- 10^c(-300, -200, -100, seq(-50, -30, by = 2), -20:-9)
  n_reps <- if (SMOKE_TEST) 1L else 30L
  gcv_probes <- if (SMOKE_TEST) 5L else 100L

  ## Family-specific dimensions and varying levels ----
  switch(name_main_test,
    sensitivity_componentwise = {
      varying <- c("lambda_1", "lambda_2")
      lambda <- -1
      lambda_1 <- c(-1, 0, component_lambda_grid)
      lambda_2 <- c(-1, 0, component_lambda_grid)
      n_stat_units <- 100L
      n_locs <- 200L
      source_k <- 51L
    },
    sensitivity =,
    sensitivity_high_NSRX = {
      varying <- "lambda"
      lambda <- if (SMOKE_TEST) c(-1, 0, 1e-6) else c(-1, 0, sensitivity_lambda_grid)
      n_stat_units <- 100L
      n_locs <- 200L
      source_k <- 51L
    },
    sensitivity_competitors =,
    sensitivity_high_NSRX_competitors = {
      varying <- "benchmark"
      lambda <- -1
      n_stat_units <- 100L
      n_locs <- 200L
      source_k <- 51L
    },
    lambda_to_zero = {
      varying <- "n_stat_units"
      lambda <- -1
      n_stat_units <- if (SMOKE_TEST) c(50L, 200L) else c(50L, 100L, 200L, 500L, 1000L, 2000L, 5000L)
      n_locs <- 100L
      source_k <- 51L
    },
    small_lambda_m_gt_k = {
      varying <- "lambda"
      lambda <- if (SMOKE_TEST) c(1e-300, 1e-20, 1e-9) else near_zero_grid
      n_stat_units <- 100L
      n_locs <- 100L
      source_k <- 51L
    },
    small_lambda_m_lt_k = {
      varying <- "lambda"
      lambda <- if (SMOKE_TEST) c(1e-50, 1e-40, 1e-30) else refined_m_lt_k_grid
      n_stat_units <- 100L
      n_locs <- 25L
      source_k <- 51L
    }
  )

  ## Explicit scientific and execution options ----
  options <- list(
    model_names = models$names,
    model_labels = models$labels,
    model_colors = models$colors,
    cpp_script = test_suite,
    benchmark = 1L,
    test_options = list(
      n_reps = n_reps,
      varying_options = varying,
      threading = "single",
      smoke_test = SMOKE_TEST
    ),
    model = list(
      dimension = 1L,
      n_comp = if (componentwise_sensitivity) 2L else 4L,
      center = FALSE,
      discretization = "spline"
    ),
    dimensions = list(
      n_stat_units = n_stat_units,
      n_locs = n_locs,
      source_k = source_k,
      n_reference_points = if (SMOKE_TEST) 201L else 500L
    ),
    data = list(
      family = name_main_test,
      location_seed = 0L,
      location_method = "jittered_grid_nearest_unique"
    ),
    noise = list(
      NSR_X_final_component = if (high_NSRX) 10 else 3,
      NSR_Y = 0.1
    ),
    regularization = list(
      lambda = lambda,
      calibration = "gcv",
      fixed_direction_lambda = 1e-9,
      fixed_loading_lambda = 1e-9,
      lambda_grid = if (prefix_sensitivity) sensitivity_lambda_grid else standard_lambda_grid,
      gcv_seed = 0L,
      gcv_probes = gcv_probes,
      max_iter = 1000L,
      tolerance = 1e-8
    ),
    competitors = list(
      basis_k = 11L,
      smoothing_lambda_grid = if (SMOKE_TEST) c(1e-4, 1e-2) else 10^seq(-9, 2, by = 0.1),
      pb_lambda_grid = standard_lambda_grid,
      pb_cv_folds = 5L
    ),
    provenance = list(
      models_in_run = models$names,
      comparator_scope = if (componentwise_sensitivity) {
        "R1_fPLS_componentwise_equal_direction_loading_schedule"
      } else if (competitor_reference) {
        "own_calibration_reference_at_fixed_DGP"
      } else {
        "R1_fPLS_common_lambda_sweep"
      },
      smoke_test = SMOKE_TEST
    )
  )

  if (componentwise_sensitivity) {
    options$data$n_true_comp <- 4L
  }
  if (componentwise_sensitivity || prefix_sensitivity) {
    options$evaluation <- list(truth_target = "prefix")
  }
  if (componentwise_sensitivity) {
    options$regularization$lambda_1 <- lambda_1
    options$regularization$lambda_2 <- lambda_2
  }

  name_fun <- function(opts_i, comb_row) {
    if (componentwise_sensitivity) {
      return(glue::glue(
        "{name_main_test}_lambda_1_{lambda_level_name(comb_row$lambda_1)}_",
        "lambda_2_{lambda_level_name(comb_row$lambda_2)}"
      ))
    }
    value <- comb_row[[varying]]
    level <- if (varying == "lambda") {
      lambda_level_name(value)
    } else if (varying == "benchmark") {
      "own_calibration"
    } else {
      sprintf("%05d", as.integer(value))
    }
    glue::glue("{name_main_test}_{varying}_{level}")
  }
  options_list <- explode_options(options, by = varying, name_fun = name_fun)

  if (componentwise_sensitivity) {
    options_list <- Filter(function(opts_i) {
      lambda_1_i <- opts_i$regularization$lambda_1
      lambda_2_i <- opts_i$regularization$lambda_2
      (lambda_1_i > 0 && lambda_2_i > 0) ||
        (lambda_1_i == lambda_2_i && lambda_1_i %in% c(-1, 0))
    }, options_list)
  }

  for (i in seq_along(options_list)) {
    if (componentwise_sensitivity) {
      lambda_1_i <- options_list[[i]]$regularization$lambda_1
      lambda_2_i <- options_list[[i]]$regularization$lambda_2
      value <- lambda_1_i
      if (value > 0) {
        schedule <- c(lambda_1_i, lambda_2_i)
        options_list[[i]]$regularization$lambda <- schedule
        options_list[[i]]$regularization$fixed_direction_lambda <- schedule
        options_list[[i]]$regularization$fixed_loading_lambda <- schedule
      } else {
        options_list[[i]]$regularization$lambda <- value
      }
    } else {
      value <- options_list[[i]]$regularization$lambda
    }
    if (value == -1) {
      options_list[[i]]$regularization$calibration <- "gcv"
    } else if (value == 0) {
      options_list[[i]]$regularization$calibration <- "multivariate"
    } else {
      options_list[[i]]$regularization$calibration <- "fixed"
      if (!componentwise_sensitivity) {
        options_list[[i]]$regularization$fixed_direction_lambda <- value
        options_list[[i]]$regularization$fixed_loading_lambda <- value
      }
    }
  }
  write_options_json(options_list, dir = path_queue, name_field = "name_test")
}
