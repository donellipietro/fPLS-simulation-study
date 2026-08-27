# Shared helpers for the simulation-study panels. Run the figure scripts with Rscript.

script_file <- sub(
  "^--file=", "", commandArgs(trailingOnly = FALSE)[grep(
    "^--file=", commandArgs(trailingOnly = FALSE)
  )][1]
)
if (is.na(script_file) || !nzchar(script_file)) stop("Run these scripts with Rscript.")
script_dir <- dirname(normalizePath(script_file))
figure_root <- normalizePath(file.path(script_dir, ".."), mustWork = TRUE)
panel_root <- file.path(figure_root, "panels")

simulation_root <- Sys.getenv(
  "FPLS_SIMULATION_STUDY",
  unset = file.path(figure_root, "..")
)
simulation_root <- normalizePath(simulation_root, mustWork = TRUE)
results_root <- normalizePath(
  Sys.getenv("FPLS_RESULTS", unset = file.path(simulation_root, "results")),
  mustWork = TRUE
)

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(grid)
  library(tidyr)
})
working_directory <- getwd()
setwd(simulation_root)
source("src/utils/plotting_utils.R")
setwd(working_directory)

panel_path <- function(figure_id, filename) {
  directory <- file.path(panel_root, figure_id)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  file.path(directory, filename)
}

read_family <- function(suite, family) {
  file <- file.path(results_root, suite, "aggregate", "all", paste0("loaded_", family, ".rds"))
  if (!file.exists(file)) stop("Missing aggregated simulation results: ", file)
  readRDS(file)
}

final_component <- function(data) {
  component <- suppressWarnings(as.integer(as.character(data$Group)))
  data[component == max(component, na.rm = TRUE), , drop = FALSE]
}

panel_theme <- function() {
  theme_classic(base_size = 6, base_family = "Arial") +
    theme(
      axis.title = element_blank(),
      axis.text = element_text(size = 6, colour = "black"),
      axis.line = element_line(linewidth = 0.3),
      axis.ticks = element_line(linewidth = 0.3),
      panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      legend.position = "none",
      plot.margin = margin(4, 7, 4, 4, "pt")
    )
}

save_panel <- function(plot, filename, width = 3.33, height = 2.02, y_axis_width = NULL) {
  grDevices::cairo_pdf(filename, width = width, height = height, family = "Arial", bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  if (!is.null(y_axis_width)) {
    plot <- ggplotGrob(plot)
    axis_column <- unique(plot$layout$l[plot$layout$name == "axis-l"])
    plot$widths[axis_column] <- unit(y_axis_width, "mm")
  }
  grid.newpage()
  grid.draw(plot)
}

fixed_y_labels <- function(digits) {
  function(values) formatC(values, format = "f", digits = digits, width = 5, flag = " ")
}

write_metric_panel <- function(loaded, metric, filename, limits = NULL, include_fpcr = FALSE,
                              panel_height = 2.02, group_labels = NULL) {
  data <- final_component(loaded$rmse[[metric]])
  models <- if (include_fpcr) loaded$model_names else setdiff(loaded$model_names, "fPCR")
  data$Group <- data[[loaded$varying_options[1]]]
  plot <- plot.grouped_boxplots(
    data[, c("Group", models)], group_name = NULL, group_labels = group_labels,
    values_name = NULL,
    subgroup_labels = loaded$model_labels[match(models, loaded$model_names)],
    subgroup_colors = loaded$model_colors[match(models, loaded$model_names)],
    limits = limits, Y_LABELS = fixed_y_labels(2), LEGEND = FALSE
  ) + panel_theme()
  save_panel(plot, filename, height = panel_height, y_axis_width = 8.5)
}

write_time_panel <- function(loaded, filename, include_fpcr = FALSE, panel_height = 2.02) {
  data <- loaded$fit_seconds
  models <- if (include_fpcr) loaded$model_names else setdiff(loaded$model_names, "fPCR")
  data$Group <- data[[loaded$varying_options[1]]]
  for (model in models) data[[model]] <- log10(data[[model]])
  plot <- plot.grouped_boxplots(
    data[, c("Group", models)], group_name = NULL, values_name = NULL,
    subgroup_labels = loaded$model_labels[match(models, loaded$model_names)],
    subgroup_colors = loaded$model_colors[match(models, loaded$model_names)],
    Y_LABELS = fixed_y_labels(1), LEGEND = FALSE, MEDIAN_LINES = TRUE
  ) + panel_theme()
  save_panel(plot, filename, height = panel_height, y_axis_width = 8.5)
}

write_structure_panel <- function(loaded, suite, family, metric, filename,
                                  limits, y_breaks, panel_height = 2.02,
                                  group_labels = NULL) {
  structure_dir <- file.path(results_root, suite, "aggregate", "all")
  candidates <- file.path(
    structure_dir,
    c(paste0(family, "_explained_structure.csv"), "explained_structure.csv")
  )
  file <- candidates[file.exists(candidates)][1]
  if (is.na(file)) stop("Missing explained-structure results for ", suite, "/", family)
  rows <- read.csv(file, stringsAsFactors = FALSE)
  values <- rows[rows$metric == metric, c("batch", "n_comp", "model", "value")]
  wide <- reshape(values, idvar = c("batch", "n_comp"), timevar = "model",
                  direction = "wide")
  names(wide) <- sub("^value[.]", "", names(wide))
  models <- loaded$model_names
  for (model in models) {
    if (is.null(wide[[model]])) wide[[model]] <- NaN
  }
  wide <- wide[order(wide$n_comp, wide$batch), c("n_comp", models)]
  data <- data.frame(Group = wide$n_comp, wide[models] * 100)
  plot <- plot.grouped_boxplots(
    data, group_name = NULL, group_labels = group_labels, values_name = NULL,
    subgroup_labels = loaded$model_labels[match(models, loaded$model_names)],
    subgroup_colors = loaded$model_colors[match(models, loaded$model_names)],
    limits = limits, Y_BREAKS = y_breaks, Y_LABELS = fixed_y_labels(0), LEGEND = FALSE
  ) + panel_theme()
  save_panel(plot, filename, height = panel_height, y_axis_width = 8.5)
}

write_legend <- function(loaded, filename, columns = 3L, include_fpcr = FALSE,
                         vertical = FALSE, vertical_height = 2.02, compact = FALSE) {
  models <- if (include_fpcr) loaded$model_names else setdiff(loaded$model_names, "fPCR")
  labels <- loaded$model_labels[match(models, loaded$model_names)]
  colors <- loaded$model_colors[match(models, loaded$model_names)]
  if (vertical) {
    grDevices::cairo_pdf(filename, width = 1.65, height = vertical_height, family = "Arial")
    on.exit(grDevices::dev.off(), add = TRUE)
    grid.newpage()
    y <- seq(1.55, 0.55, length.out = length(labels))
    for (i in seq_along(labels)) {
      grid.rect(
        x = unit(5, "mm"), y = unit(y[i], "in"), width = unit(5, "mm"), height = unit(3.4, "mm"),
        just = c("left", "centre"), gp = gpar(col = NA, fill = colors[i])
      )
      grid.rect(
        x = unit(5.7, "mm"), y = unit(y[i], "in"), width = unit(3.6, "mm"), height = unit(1.2, "mm"),
        just = c("left", "centre"), gp = gpar(col = NA, fill = "black")
      )
      grid.text(
        labels[i], x = unit(12, "mm"), y = unit(y[i], "in"), just = c("left", "centre"),
        gp = gpar(fontfamily = "Arial", fontsize = 9)
      )
    }
    return(invisible(NULL))
  }
  grDevices::cairo_pdf(filename, width = 6.85, height = 0.52, family = "Arial")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid.newpage()
  if (compact) {
    text_widths <- vapply(labels, function(label) {
      convertWidth(
        grobWidth(textGrob(label, gp = gpar(fontfamily = "Arial", fontsize = 9))),
        "mm", valueOnly = TRUE
      )
    }, numeric(1))
    item_widths <- 7 + text_widths
    item_gap <- 10
    page_width <- 6.85 * 25.4
    x <- cumsum(c((page_width - sum(item_widths) - item_gap * (length(labels) - 1)) / 2,
                  head(item_widths + item_gap, -1)))
    y <- 6.5
    for (i in seq_along(labels)) {
      grid.rect(
        x = unit(x[i], "mm"), y = unit(y, "mm"), width = unit(5, "mm"), height = unit(3.4, "mm"),
        just = c("left", "centre"), gp = gpar(col = NA, fill = colors[i])
      )
      grid.rect(
        x = unit(x[i] + 0.7, "mm"), y = unit(y, "mm"), width = unit(3.6, "mm"), height = unit(1.2, "mm"),
        just = c("left", "centre"), gp = gpar(col = NA, fill = "black")
      )
      grid.text(
        labels[i], x = unit(x[i] + 7, "mm"), y = unit(y, "mm"), just = c("left", "centre"),
        gp = gpar(fontfamily = "Arial", fontsize = 9)
      )
    }
    return(invisible(NULL))
  }
  rows <- ceiling(length(labels) / columns)
  column_x <- c(6, 62, 122)
  row_y <- if (rows == 1L) 6.5 else c(9.1, 3.9)
  if (length(labels) == 5L && columns == 3L) {
    column <- c(1L, 1L, 2L, 2L, 3L)
    y <- c(9.1, 3.9, 9.1, 3.9, 6.5)
  } else {
    column <- (seq_along(labels) - 1L) %% columns + 1L
    row <- (seq_along(labels) - 1L) %/% columns + 1L
    y <- row_y[row]
  }
  for (i in seq_along(labels)) {
    x <- column_x[column[i]]
    grid.rect(
      x = unit(x, "mm"), y = unit(y[i], "mm"), width = unit(5, "mm"), height = unit(3.4, "mm"),
      just = c("left", "centre"), gp = gpar(col = NA, fill = colors[i])
    )
    grid.rect(
      x = unit(x + 0.7, "mm"), y = unit(y[i], "mm"), width = unit(3.6, "mm"), height = unit(1.2, "mm"),
      just = c("left", "centre"), gp = gpar(col = NA, fill = "black")
    )
    grid.text(
      labels[i], x = unit(x + 7, "mm"), y = unit(y[i], "mm"), just = c("left", "centre"),
      gp = gpar(fontfamily = "Arial", fontsize = 9)
    )
  }
}

write_quantitative_figure <- function(figure_id, suite, family, metrics,
                                      legend_columns = 3L, limits = list(), include_fpcr = FALSE,
                                      vertical_legend = FALSE) {
  loaded <- read_family(suite, family)
  for (metric in metrics) {
    write_metric_panel(
      loaded, metric,
      panel_path(figure_id, paste0(metric, ".pdf")), limits[[metric]], include_fpcr
    )
  }
  write_time_panel(loaded, panel_path(figure_id, "fit_time.pdf"), include_fpcr)
  write_legend(loaded, panel_path(figure_id, "legend.pdf"), legend_columns, include_fpcr)
  if (vertical_legend) {
    write_legend(loaded, panel_path(figure_id, "legend_vertical.pdf"), legend_columns, include_fpcr, vertical = TRUE)
  }
}

load_model <- function(file, model_name) {
  env <- new.env(parent = emptyenv())
  load(file, envir = env)
  get(paste0("model_", model_name), envir = env, inherits = FALSE)
}

normalize_shape <- function(values) {
  values <- as.matrix(values)
  values / sqrt(sum(values^2))
}

aligned_shape <- function(values, truth) {
  values <- normalize_shape(values)[, 1]
  if (sqrt(mean((values - truth)^2)) > sqrt(mean((-values - truth)^2))) values <- -values
  values
}

write_field_panel <- function(nodes, values, limits, filename, size = 36 / 25.4) {
  boundary <- data.frame(long = c(0, 1, 1, 0, 0), lat = c(0, 0, 1, 1, 0))
  plot <- plot.field_tile(
    nodes, values, boundary = boundary, limits = limits,
    palette = cool_to_warm_extended_palette, ISOLINES = TRUE, LEGEND = FALSE
  ) + theme_void(base_family = "Arial", base_size = 8) +
    theme(plot.margin = margin(0, 0, 0, 0, "pt"))
  save_panel(plot, filename, width = size, height = size)
}

write_field_legend <- function(limits, filename, width = 18 / 25.4, height = 36 / 25.4) {
  grDevices::cairo_pdf(filename, width = width, height = height, family = "Arial", bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  colors <- cool_to_warm_extended_palette
  n <- length(colors)
  grid.newpage()
  for (i in seq_len(n)) {
    grid.rect(
      x = unit(2, "mm"), y = unit((i - 0.5) / n, "npc"),
      width = unit(3.5, "mm"), height = unit(1 / n, "npc"),
      gp = gpar(col = NA, fill = colors[i])
    )
  }
  grid.rect(x = unit(2, "mm"), y = unit(0.5, "npc"), width = unit(3.5, "mm"), height = unit(1, "npc"), gp = gpar(fill = NA, col = "black", lwd = 0.3))
  values <- c(limits[1], mean(limits), limits[2])
  positions <- c(0, 0.5, 1)
  label_positions <- unit(c(1.8, 18, 34.2), "mm")
  for (i in seq_along(values)) {
    grid.segments(x0 = unit(3.8, "mm"), x1 = unit(4.7, "mm"), y0 = unit(positions[i], "npc"), y1 = unit(positions[i], "npc"), gp = gpar(lwd = 0.3))
    grid.text(formatC(values[i], format = "f", digits = 2), x = unit(5.1, "mm"), y = label_positions[i], just = c("left", "centre"), gp = gpar(fontfamily = "Arial", fontsize = 9))
  }
}
