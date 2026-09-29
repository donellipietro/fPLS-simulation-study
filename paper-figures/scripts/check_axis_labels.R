# Run with Rscript; no panels are exported.
source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))

labels <- fixed_y_labels(2)
stopifnot(
  identical(labels(c(0, 0.01, 0.02)), c(" 0.00", " 0.01", " 0.02")),
  identical(labels(c(0, 0.005, 0.01, 0.015)), c(" 0.000", " 0.005", " 0.010", " 0.015")),
  identical(labels(c(0.0025, 0.005, 0.0075)), c(" 0.0025", " 0.0050", " 0.0075")),
  identical(labels(c(0.01, 0.01, NA)), c(" 0.01", " 0.01", "   NA"))
)
message("Axis labels retain existing precision unless distinct ticks would coincide.")
