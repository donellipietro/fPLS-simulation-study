source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

write_quantitative_figure(
  "S_1D_vary_nsrx", "1D", "vary_NSRX",
  c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations"),
  limits = list()
)
