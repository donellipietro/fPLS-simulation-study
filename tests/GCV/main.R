# = ========================================================================== =
# - Test: fPLS GCV and numerical-stability diagnostics
# - Desc: Runs one GCV option through its requested models and repetitions.
# - Args:
#   [1] name_main_test: one GCV diagnostic family
#   [2] file_options: one generated JSON option file
# = ========================================================================== =

## Start a clean simulation session ----
rm(list = ls())
graphics.off()

## Load libraries ----
suppressMessages(library(jsonlite))
suppressMessages(library(fda))

## Load simulation helpers and cache checks ----
source("src/utils/directories.R")
source("src/utils/load_results_utils.R")
source("src/utils/batch_cache_utils.R")
source("tests/GCV/config.R")
source("tests/GCV/utils/cache_utils.R")
source("tests/1D/utils/generate_data.R")
source("tests/1D/utils/competitors.R")
source("tests/1D/utils/wrappers.R")
source("tests/1D/utils/fit_and_evaluate.R")
source("tests/1D/utils/models_evaluation.R")

## Prepare suite directories and read the queued option ----
path_list <- create_paths(test_suite)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: main.R <test-name> <option-file>")

# locate the queued JSON file within the requested simulation family
name_main_test <- args[1]
file_options <- args[2]
path_list$queue <- config_path(path_list$queue, name_main_test)
path_list$logs <- config_path(path_list$logs, name_main_test)
mkdir(c(path_list$queue, path_list$logs))

# resolve the full path of the queued JSON option selected by the runner
queue_file <- file.path(path_list$queue, file_options)

# read the data-generation, model and repetition settings for this option
test_options <- fromJSON(queue_file, simplifyVector = TRUE)

# prepare output directories and resolve the compiled driver for this option
path_list <- update_paths(path_list, name_main_test, test_options)

## Record progress in family and option logs ----
run_message <- glue::glue(
  "- Running: {test_suite} / {test_options$name_test}\n",
  .trim = FALSE
)
cat(run_message)

# record the option in the family log before redirecting batch progress to its own log
sink(file.path(path_list$logs, "log.txt"), append = TRUE)
cat(run_message)
sink()
sink(
  file.path(path_list$logs, glue::glue("log_{test_options$name_test}.txt")),
  append = TRUE
)
cat(run_message)

## Run simulation repetitions ----
for (batch_index in seq_len(test_options$test_options$n_reps)) {
  cat(glue::glue("\nBatch {batch_index}:\n", .trim = FALSE))

  # keep the data, fitted models and evaluation together for this repetition
  path_list$batch <- config_path(path_list$results, glue::glue("batch_{batch_index}"))
  mkdir(path_list$batch)

  # identify the saved artifacts used to resume an interrupted or completed option
  data_file <- file.path(path_list$batch, "generated_data.rds")
  evaluation_file <- file.path(
    path_list$batch, glue::glue("batch_{batch_index}_results_evaluation.RData")
  )
  model_files <- file.path(
    path_list$batch,
    glue::glue("batch_{batch_index}_fitted_model_{test_options$model_names}.RData")
  )

  # check whether the saved sample matches this repetition and its generation settings
  can_reuse_data <- batch_matches_options(data_file, test_options, batch_index)

  # keep completed repetitions unless a fit or evaluation refresh is requested
  if (!FORCE_FIT && !FORCE_EVALUATE &&
      can_reuse_data && evaluation_matches_options(evaluation_file, test_options) &&
      models_match_options(model_files, test_options$model_names, test_options)) {
    cat("- Existing complete batch; skipped\n")
    next
  }

  # reuse the same simulated sample when refreshing fits or evaluations
  if (can_reuse_data) {
    cat("- Reuse generated data\n")
    data <- readRDS(data_file)
  } else {
    cat("- Generate data\n")

    # regenerate stale or missing data reproducibly from the repetition index
    data <- generate_fpls_data(test_options, data_seed = batch_index)
    saveRDS(data, data_file)

    # save the first repetition as the representative dataset for this option
    if (batch_index == 1L) {
      saveRDS(data, file.path(path_list$data, glue::glue("{test_options$name_test}.rds")))
    }
  }

  # invalidate saved fits when their input sample has been regenerated
  test_options$batch_index <- batch_index
  test_options$force_refit_batch <- !can_reuse_data
  cat("- Fit models\n")

  # fit or reuse the requested models, then refresh their quantitative evaluation
  fit_and_evaluate_models(
    path_list = path_list,
    data = data,
    domain = NULL,
    batch_index = batch_index,
    test_options = test_options
  )
}

## Finalize the completed option ----
# remove the queue entry only after every repetition has finished successfully
unlink(queue_file)
# close the option log and restore console output
sink()
