source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

write_quantitative_figure(
  "S_2D_vary_m", "2D", "vary_m",
  c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations", "Beta2_locations"),
  legend_columns = 3L, limits = list(), include_fpcr = TRUE, vertical_legend = TRUE
)
