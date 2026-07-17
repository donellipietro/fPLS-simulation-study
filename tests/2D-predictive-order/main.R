# = ========================================================================== =
# - Test: Predictive component ordering on a 2D support
# - Desc: Fits ten components once and evaluates all progressive prefixes.
# - Args:
#   [1] name_main_test: vary_H
#   [2] file_options: one generated JSON option file
# = ========================================================================== =

rm(list = ls())
graphics.off()

## Load libraries ----
suppressMessages(library(jsonlite))

## Load general and suite-specific functions ----
source("src/utils/directories.R")
source("src/utils/load_results_utils.R")
source("tests/2D-predictive-order/config.R")
source("tests/2D/utils/generate_data.R")
source("tests/2D-predictive-order/utils/generate_data.R")
source("tests/2D/utils/competitors.R")
source("tests/2D/utils/wrappers.R")
source("tests/2D/utils/fit_and_evaluate.R")
source("tests/2D/utils/models_evaluation.R")

## Read the requested option ----
path_list <- create_paths(test_suite)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: main.R <test-name> <option-file>")

name_main_test <- args[1]
file_options <- args[2]
path_list$queue <- config_path(path_list$queue, name_main_test)
path_list$logs <- config_path(path_list$logs, name_main_test)
mkdir(c(path_list$queue, path_list$logs))

queue_file <- file.path(path_list$queue, file_options)
test_options <- fromJSON(queue_file, simplifyVector = TRUE)
path_list <- update_paths(path_list, name_main_test, test_options)

## Log file ----
run_message <- glue::glue("- Running: {test_suite} / {test_options$name_test}\n", .trim = FALSE)
cat(run_message)
sink(file.path(path_list$logs, "log.txt"), append = TRUE)
cat(run_message)
sink()
sink(
  file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt")),
  append = TRUE
)
cat(run_message)

batch_matches_options <- function(file, options, batch_index) {
  if (!file.exists(file)) return(FALSE)
  data <- readRDS(file)
  same <- function(left, right) isTRUE(all.equal(left, right))
  same(data$data_seed, batch_index) &&
    same(data$dimensions$n_stat_units, options$dimensions$n_stat_units) &&
    same(data$dimensions$n_comp, options$model$n_comp) &&
    same(data$dimensions$n_signal_components, options$data$n_signal_components) &&
    same(data$design$version, options$data$design_version) &&
    same(data$dimensions$n_locs_requested, options$dimensions$n_locs) &&
    same(data$dimensions$source_k, options$dimensions$source_k) &&
    same(nrow(data$evaluation), options$dimensions$n_reference_per_axis^2) &&
    same(data$design$score_variance, options$data$score_variance) &&
    same(data$noise$requested_NSR_X_final_component, options$noise$NSR_X_final_component) &&
    same(data$noise$requested_NSR_Y, options$noise$NSR_Y)
}

models_match_options <- function(files, names, options) {
  all(mapply(function(file, model_name) {
    if (!file.exists(file)) return(FALSE)
    object_name <- glue::glue("model_{model_name}")
    load(file)
    native_model_matches_options(get(object_name), model_name, options)
  }, files, names))
}

## Run every repetition ----
for (batch_index in seq_len(test_options$test_options$n_reps)) {
  cat(glue::glue("\nBatch {batch_index}:\n", .trim = FALSE))
  path_list$batch <- config_path(path_list$results, glue::glue("batch_{batch_index}"))
  mkdir(path_list$batch)

  data_file <- file.path(path_list$batch, "generated_data.rds")
  evaluation_file <- file.path(
    path_list$batch, glue::glue("batch_{batch_index}_results_evaluation.RData")
  )
  model_files <- file.path(
    path_list$batch,
    glue::glue("batch_{batch_index}_fitted_model_{test_options$model_names}.RData")
  )
  data_current <- batch_matches_options(data_file, test_options, batch_index)
  if (!FORCE_FIT && !FORCE_EVALUATE && data_current &&
      file.exists(evaluation_file) &&
      models_match_options(model_files, test_options$model_names, test_options)) {
    cat("- Existing complete batch; skipped\n")
    next
  }

  if (data_current) {
    cat("- Reuse generated data\n")
    data <- readRDS(data_file)
  } else {
    cat("- Generate data\n")
    data <- generate_fpls_data(test_options, data_seed = batch_index)
    saveRDS(data, data_file)
    if (batch_index == 1L) {
      saveRDS(data, file.path(path_list$data, glue::glue("{test_options$name_test}.rds")))
    }
  }

  test_options$batch_index <- batch_index
  test_options$force_refit_batch <- !data_current
  cat("- Fit models\n")
  fit_and_evaluate_models(
    path_list = path_list,
    data = data,
    domain = NULL,
    batch_index = batch_index,
    test_options = test_options
  )
}

## Test finalization ----
unlink(queue_file)
sink()
