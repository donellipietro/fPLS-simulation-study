source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

batch <- file.path(results_root, "2D", "vary_n", "vary_n_n_stat_units_0100", "batch_1")
data_file <- file.path(batch, "generated_data.rds")
if (!file.exists(data_file)) stop("Missing Simulation 2 representative data: ", data_file)
data <- readRDS(data_file)
models <- c("MV_PLS", "fPCR", "R1_fPLS")

for (response in 1:2) {
  truth <- normalize_shape(data$truth$Beta_reference[, response])[, 1]
  fields <- c(list(Truth = truth), setNames(lapply(models, function(model) {
    fitted <- load_model(file.path(batch, paste0("batch_1_fitted_model_", model, ".RData")), model)
    aligned_shape(fitted$results$Beta_evaluation[[4L]][, response], truth)
  }), models))
  limits <- range(truth)
  for (name in names(fields)) {
    write_field_panel(data$evaluation, fields[[name]], limits, panel_path("2D_qualitative", paste0("beta_", response, "_", name, ".pdf")))
  }
  write_field_legend(limits, panel_path("2D_qualitative", paste0("beta_", response, "_legend.pdf")))
}
