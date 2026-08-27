source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

figure_id <- "S_2D_vary_H_extended"
loaded <- read_family("2D-predictive-order", "vary_H")
panel_height <- 47 / 25.4
h_labels <- paste("H =", sort(unique(loaded$rmse$Y_reconstruction$n_comp)))

for (metric in c("Y_reconstruction", "X_reconstruction_locations",
                 "Beta1_locations", "Beta2_locations")) {
  write_metric_panel(
    loaded, metric, panel_path(figure_id, paste0(metric, ".pdf")),
    limits = NULL, include_fpcr = TRUE, panel_height = panel_height,
    group_labels = h_labels
  )
}

write_structure_panel(
  loaded, "2D-predictive-order", "vary_H", "Y_variance_explained",
  panel_path(figure_id, "Y_variance_explained.pdf"),
  limits = c(0, 100), y_breaks = seq(0, 100, 25), panel_height = panel_height,
  group_labels = h_labels
)
write_structure_panel(
  loaded, "2D-predictive-order", "vary_H", "X_variance_explained",
  panel_path(figure_id, "X_variance_explained.pdf"),
  limits = c(0, 100), y_breaks = seq(0, 100, 25), panel_height = panel_height,
  group_labels = h_labels
)
write_structure_panel(
  loaded, "2D-predictive-order", "vary_H", "XY_cross_covariance_explained",
  panel_path(figure_id, "XY_cross_covariance_explained.pdf"),
  limits = c(90, 100), y_breaks = seq(90, 100, 2), panel_height = panel_height,
  group_labels = h_labels
)

write_legend(
  loaded, panel_path(figure_id, "legend.pdf"),
  columns = 3L, include_fpcr = TRUE, compact = TRUE
)
write_legend(
  loaded, panel_path(figure_id, "legend_vertical.pdf"),
  columns = 3L, include_fpcr = TRUE, vertical = TRUE,
  vertical_height = panel_height
)
