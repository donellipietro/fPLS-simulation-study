source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

write_quantitative_figure(
  "2D_vary_n", "2D", "vary_n",
  c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations", "Beta2_locations"),
  legend_columns = 3L, limits = list(), include_fpcr = TRUE, vertical_legend = TRUE
)
