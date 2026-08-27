source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

write_quantitative_figure(
  "S_1D_vary_nsry", "1D", "vary_NSRY",
  c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations"),
  limits = list()
)
