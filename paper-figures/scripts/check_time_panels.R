# Run from any directory with Rscript; checks existing aggregates without exporting.
source(file.path(dirname(normalizePath(sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]))), "common.R"))
gcv <- parse(file.path(script_dir, "S_1D_gcv_sensitivity.R"))
for (expr in gcv[-c(1L, length(gcv))]) eval(expr)
save_panel <- function(plot, filename, ...) {
  built <- ggplot_build(plot)$data
  if (inherits(plot$layers[[1]]$geom, "GeomBoxplot")) {
    expected <- aggregate(value ~ tuning, plot$data, median)$value
    stopifnot(length(plot$layers) == 1L,
              isTRUE(all.equal(sort(built[[1]]$middle), sort(expected))))
  } else {
    expected <- aggregate(Seconds ~ Group + Model, plot$data, median)
    stopifnot(length(plot$layers) == if (family == "vary_k") 6L else 2L,
              isTRUE(all.equal(sort(built[[2]]$y), sort(expected$Seconds))),
              isTRUE(all.equal(sort(as.numeric(built[[2]]$x)), sort(log10(expected$Group)))),
              isTRUE(all.equal(sort(built[[1]]$xintercept), sort(unique(log10(expected$Group))))))
    if (family == "vary_k") {
      for (i in 1:2) {
        guide <- built[[2 * i + 1]]
        stopifnot(abs((guide$yend - guide$y) / (guide$xend - guide$x) - i) < 1e-10)
      }
      stopifnot(built[[3]]$linetype != built[[5]]$linetype)
    }
  }
  stopifnot(identical(plot$scales$get_scales("y")$get_labels(c(-2, -1, 0)), c("0.01", "0.1", "1")),
            identical(plot$theme$legend.position, "none"),
            inherits(plot$theme$axis.title, "element_blank"))
}
for (suite in c("1D", "2D")) {
  for (family in c("vary_k", "vary_n", "vary_m", "vary_NSRX", "vary_NSRY")) {
    write_time_panel(read_family(suite, family), NULL, include_fpcr = suite == "2D")
  }
}
for (family in families) write_fit_time_panel(read_gcv_family(family), NULL)
message("All 10 log-log time panels and 2 GCV boxplot panels passed.")
