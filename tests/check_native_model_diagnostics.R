# validate cached fPCR calibration controls and the native saved-GCV curve schema
# run from the repository root with Rscript tests/check_native_model_diagnostics.R
source("tests/2D/utils/fit_and_evaluate.R")
regularization <- list(
  calibration = "gcv", max_iter = 15L, tolerance = 1e-8,
  lambda_grid = c(0.001, 0.1), gcv_probes = 12L, gcv_seed = 42L
)
options <- list(regularization = regularization, model = list(n_comp = 2L))
telemetry <- c(list(
  schema_version = 5L, model = "fPCR", fpcr_score_map = "sequential_projection_v1",
  timing_scope = "compute_v2", n_components = 2L
), regularization)
model <- list(MODE = "fPCR", results = list(telemetry = telemetry))
# a current saved fit matches every requested calibration and solver control
stopifnot(native_model_matches_options(model, "fPCR", options))
model$results$telemetry$gcv_seed <- 0L
# a different explicit EDF seed invalidates the saved GCV fit
stopifnot(!native_model_matches_options(model, "fPCR", options))
model$results$telemetry$gcv_seed <- 42L
model$results$telemetry$gcv_probes <- 13L
# a different probe count invalidates the EDF evaluations retained with the saved fit
stopifnot(!native_model_matches_options(model, "fPCR", options))
model$results$telemetry$gcv_probes <- 12L
model$results$telemetry$schema_version <- 4L
# the former schema cannot identify public-model calibration with explicit EDF controls
stopifnot(!native_model_matches_options(model, "fPCR", options))

# extract the curve validator without running the aggregation campaign
code <- parse("tests/GCV/aggregate_results.R")
selected <- Filter(function(value) {
  is.call(value) && identical(value[[1]], as.name("<-")) &&
    identical(value[[2]], as.name("validate_gcv_curves"))
}, as.list(code))
eval(selected[[1]])
options <- list(regularization = list(lambda_grid = c(0.001, 0.1)), model = list(n_comp = 1L))
tmp <- tempfile("saved-gcv-curves-")
dir.create(tmp)
curve <- data.frame(
  lambda = c(0.001, 0.1), edf = c(10, 4), gcv = c(2, 1), selected_by_fit = c(0, 1)
)
for (prefix in c("direction", "loading")) {
  write.csv(curve, file.path(tmp, paste0(prefix, "_gcv_h1.csv")), row.names = FALSE)
}
validate_gcv_curves(tmp, options)
curve$selected_by_fit <- c(1, 0)
write.csv(curve, file.path(tmp, "direction_gcv_h1.csv"), row.names = FALSE)
# a selection inconsistent with the saved GCV minimum is rejected by the production consumer
stopifnot(inherits(try(validate_gcv_curves(tmp, options), silent = TRUE), "try-error"))
unlink(tmp, recursive = TRUE)
cat("R cache invalidation and saved-grid minimum validation passed\n")
