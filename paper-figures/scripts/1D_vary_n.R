source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

write_quantitative_figure(
  "1D_vary_n", "1D", "vary_n",
  c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations"),
  limits = list()
)
