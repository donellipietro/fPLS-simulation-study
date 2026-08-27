source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

data_file <- file.path(results_root, "1D", "vary_k", "vary_k_source_k_0011", "batch_1", "generated_data.rds")
if (!file.exists(data_file)) stop("Missing Simulation 1 data: ", data_file)
data <- readRDS(data_file)

response_width <- 2.02
response_height <- 2.02

grDevices::cairo_pdf(panel_path("1D_data", "response.pdf"), width = response_width, height = response_height, pointsize = 8, family = "Arial")
response_range <- range(data$truth$Y[, 1], data$Y[, 1])
# Axis labels and titles are placed in Affinity; this PDF is the plot only.
par(mar = rep(0, 4), family = "Arial")
plot(data$truth$Y[, 1], data$Y[, 1], xlim = response_range, ylim = response_range, asp = 1,
     xlab = "", ylab = "", xaxt = "n", yaxt = "n", type = "n")
grid(col = "grey88", lty = 3)
abline(0, 1, col = "grey55", lty = 2, lwd = 0.7)
points(data$truth$Y[, 1], data$Y[, 1], pch = 20, cex = 0.45)
grDevices::dev.off()

predictor_width <- 4.42
predictor_height <- response_height
grDevices::cairo_pdf(panel_path("1D_data", "predictors.pdf"), width = predictor_width, height = predictor_height, pointsize = 8, family = "Arial")
units <- seq_len(min(4L, nrow(data$X)))
colours <- RColorBrewer::brewer.pal(5, "RdPu")[2:5]
predictor_range <- range(data$truth$X_reference[units, , drop = FALSE], data$X[units, , drop = FALSE])
# Axis labels and titles are placed in Affinity; this PDF is the plot only.
par(mar = rep(0, 4), family = "Arial")
plot(NA_real_, NA_real_, xlim = range(data$evaluation[, 1]), ylim = predictor_range,
     xlab = "", ylab = "", xaxt = "n", yaxt = "n")
grid(col = "grey88", lty = 3)
matlines(data$evaluation[, 1], t(data$truth$X_reference[units, , drop = FALSE]), lwd = 1.1, col = colours)
matlines(data$locations[, 1], t(data$X[units, , drop = FALSE]), lty = 2, lwd = 0.65, col = colours)
matpoints(data$locations[, 1], t(data$X[units, , drop = FALSE]), pch = 20, cex = 0.32, col = colours)
grDevices::dev.off()
