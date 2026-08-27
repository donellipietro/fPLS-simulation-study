source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

loaded <- read_family("1D", "vary_k")
models <- c("MV_PLS", "B_fPLS", "B_fPLS_smooth", "PB_fPLS", "R1_fPLS")
colours <- setNames(loaded$model_colors, loaded$model_names)
labels <- setNames(loaded$model_labels, loaded$model_names)

for (k in c(11L, 101L)) {
  batch <- file.path(results_root, "1D", "vary_k", sprintf("vary_k_source_k_%04d", k), "batch_1")
  data <- readRDS(file.path(batch, "generated_data.rds"))
  truth <- normalize_shape(data$truth$Beta_reference[, 1])[, 1]
  truth_locations <- normalize_shape(data$truth$Beta_locations[, 1])[, 1]
  observed <- data$evaluation[, 1] >= min(data$locations[, 1]) & data$evaluation[, 1] <= max(data$locations[, 1])
  estimates <- lapply(models, function(model) {
    fitted <- load_model(file.path(batch, paste0("batch_1_fitted_model_", model, ".RData")), model)
    list(
      evaluation = aligned_shape(fitted$results$Beta_evaluation[[4L]][, 1], truth),
      locations = aligned_shape(fitted$results$Beta_locations[[4L]][, 1], truth_locations)
    )
  })
  names(estimates) <- models
  values <- c(truth, estimates$MV_PLS$locations, unlist(lapply(estimates[-1], `[[`, "evaluation"))[rep(observed, length(models) - 1L)])

  grDevices::cairo_pdf(panel_path("1D_qualitative", paste0("k_", k, ".pdf")), width = 3.33, height = 2.08, pointsize = 8, family = "Arial")
  par(mar = rep(0, 4), family = "Arial")
  plot(data$evaluation[, 1], truth, type = "n", ylim = range(values), xlab = "", ylab = "", xaxt = "n", yaxt = "n")
  grid(col = "grey90", lty = 3, lwd = 0.4)
  lines(data$evaluation[, 1], truth, col = "black", lty = 2, lwd = 1.15)
  lines(data$locations[, 1], estimates$MV_PLS$locations, col = "grey70", lty = 2, lwd = 0.55)
  points(data$locations[, 1], estimates$MV_PLS$locations, col = "grey70", pch = 16, cex = 0.48)
  for (model in models[-1]) lines(data$evaluation[observed, 1], estimates[[model]]$evaluation[observed], col = colours[[model]], lwd = if (model %in% c("B_fPLS_smooth", "R1_fPLS")) 1.35 else 0.8)
  grDevices::dev.off()

  x_limits <- c(0.20, 0.50)
  selected <- data$evaluation[, 1] >= x_limits[1] & data$evaluation[, 1] <= x_limits[2]
  location_selected <- data$locations[, 1] >= x_limits[1] & data$locations[, 1] <= x_limits[2]
  zoom_values <- c(
    truth[selected], estimates$MV_PLS$locations[location_selected],
    unlist(lapply(estimates[-1], function(estimate) estimate$evaluation[selected]))
  )
  grDevices::cairo_pdf(panel_path("1D_qualitative", paste0("k_", k, "_zoom.pdf")), width = 1.41, height = 0.78, pointsize = 8, family = "Arial")
  par(mar = rep(0, 4), family = "Arial")
  plot(data$evaluation[selected, 1], truth[selected], type = "n", xlim = x_limits, ylim = range(zoom_values),
       xlab = "", ylab = "", xaxt = "n", yaxt = "n", bty = "n")
  lines(data$evaluation[selected, 1], truth[selected], col = "black", lty = 2, lwd = 1.15)
  lines(data$locations[location_selected, 1], estimates$MV_PLS$locations[location_selected], col = "grey70", lty = 2, lwd = 0.55)
  points(data$locations[location_selected, 1], estimates$MV_PLS$locations[location_selected], col = "grey70", pch = 16, cex = 0.48)
  for (model in models[-1]) lines(data$evaluation[selected, 1], estimates[[model]]$evaluation[selected], col = colours[[model]], lwd = if (model %in% c("B_fPLS_smooth", "R1_fPLS")) 1.35 else 0.8)
  box(col = "grey80", lwd = 0.8)
  grDevices::dev.off()
}

grDevices::cairo_pdf(panel_path("1D_qualitative", "legend.pdf"), width = 6.85, height = 0.62, family = "Arial")
grid.newpage()
legend_items <- list(
  list("Ground truth", "black", 2, 1.5, NA, 5, 12.2),
  list(labels[["MV_PLS"]], "grey70", 2, 1, 16, 5, 7.9),
  list(labels[["R1_fPLS"]], colours[["R1_fPLS"]], 1, 2, NA, 5, 3.6),
  list(labels[["B_fPLS"]], colours[["B_fPLS"]], 1, 1, NA, 91, 12.2),
  list(labels[["B_fPLS_smooth"]], colours[["B_fPLS_smooth"]], 1, 2, NA, 91, 7.9),
  list(labels[["PB_fPLS"]], colours[["PB_fPLS"]], 1, 1, NA, 91, 3.6)
)
for (item in legend_items) {
  grid.lines(
    x = unit(c(item[[6]], item[[6]] + 8), "mm"), y = unit(c(item[[7]], item[[7]]), "mm"),
    gp = gpar(col = item[[2]], lty = item[[3]], lwd = item[[4]])
  )
  if (!is.na(item[[5]])) {
    grid.points(x = unit(item[[6]] + 4, "mm"), y = unit(item[[7]], "mm"),
                pch = item[[5]], size = unit(1.8, "mm"), gp = gpar(col = item[[2]]))
  }
  grid.text(item[[1]], x = unit(item[[6]] + 11, "mm"), y = unit(item[[7]], "mm"),
            just = c("left", "centre"), gp = gpar(fontfamily = "Arial", fontsize = 9))
}
grDevices::dev.off()
