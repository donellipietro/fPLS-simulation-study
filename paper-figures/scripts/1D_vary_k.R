source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

write_quantitative_figure(
  "1D_vary_k", "1D", "vary_k",
  c("Y_reconstruction", "X_reconstruction_locations", "Beta1_locations"),
  limits = list(Y_reconstruction = c(0.067, 0.145), X_reconstruction_locations = c(0.055, 0.14), Beta1_locations = c(0, 0.035))
)
