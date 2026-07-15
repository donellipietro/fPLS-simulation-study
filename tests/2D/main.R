# = ========================================================================== =
# - Test: fPLS paper simulation on a 2D support
# - Desc: Runs one option through MV-PLS and native R1-fPLS for all batches.
# - Args:
#   [1] name_main_test: vary_k, vary_n, or vary_m
#   [2] file_options: one generated JSON option file
# = ========================================================================== =

rm(list = ls())
graphics.off()

## Load libraries ----
suppressMessages(library(jsonlite))

## Load general and suite-specific functions ----
source("src/utils/directories.R")
source("src/utils/load_results_utils.R")
source("tests/2D/config.R")
source("tests/2D/utils/generate_data.R")
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

## Run every repetition ----
cat(glue::glue("- Running: {test_suite} / {test_options$name_test}\n", .trim = FALSE))
for (batch_index in seq_len(test_options$test_options$n_reps)) {
  cat(glue::glue(
    "- Batch {batch_index} of {test_options$test_options$n_reps}\n",
    .trim = FALSE
  ))
  path_list$batch <- config_path(path_list$results, glue::glue("batch_{batch_index}"))
  mkdir(path_list$batch)

  data <- generate_fpls_data(test_options, data_seed = batch_index)
  saveRDS(data, file.path(path_list$batch, "generated_data.rds"))
  if (batch_index == 1L) {
    saveRDS(data, file.path(path_list$data, glue::glue("{test_options$name_test}.rds")))
  }

  test_options$batch_index <- batch_index
  fit_and_evaluate_models(
    path_list = path_list,
    data = data,
    domain = NULL,
    batch_index = batch_index,
    test_options = test_options
  )
}

## Remove the processed option from the queue ----
unlink(queue_file)
