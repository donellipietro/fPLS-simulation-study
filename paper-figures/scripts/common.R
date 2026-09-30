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
source("src/utils/model_colors.R", local = TRUE)
source("src/utils/plotting_utils.R")
setwd(working_directory)

panel_path <- function(figure_id, filename) {
  directory <- file.path(panel_root, figure_id)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  file.path(directory, filename)
}

read_family <- function(suite, family) {
  file <- file.path(results_root, suite, "aggregate", family, paste0("loaded_", family, ".rds"))
  if (!file.exists(file)) stop("Missing aggregated simulation results: ", file)
  loaded <- readRDS(file)
  # retain the five paper methods when reading older one-dimensional aggregates
  if (suite == "1D") {
    keep <- loaded$model_names != "fPCR"
    loaded$model_names <- loaded$model_names[keep]
    loaded$model_labels <- loaded$model_labels[keep]
  }
  loaded$model_colors <- unname(model_palette[loaded$model_names])
  if (anyNA(loaded$model_colors)) stop("Missing model palette entry.")
  loaded
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
  function(values) {
    ticks <- unique(values[is.finite(values)])
    if (anyDuplicated(round(ticks, digits))) {
      while (!isTRUE(all.equal(ticks, round(ticks, digits), tolerance = 1e-10))) {
        digits <- digits + 1L
      }
    }
    formatC(values, format = "f", digits = digits, width = 5, flag = " ")
  }
}

check_beta_metrics <- function(loaded, metric, include_fpcr = TRUE) {
  if (startsWith(metric, "Beta") && !identical(loaded$beta_sign_alignment, FALSE)) {
    stop("Beta metrics use an obsolete sign convention. Re-run the suite's aggregate_results.R with saved fits before generating beta panels.")
  }
  if (startsWith(metric, "Beta") && include_fpcr && "fPCR" %in% loaded$model_names &&
      !identical(loaded$fpcr_score_map, "sequential_projection_v1")) {
    stop("Outdated fPCR score-to-beta map. Re-run make run_test for this suite to refit fPCR and rebuild its aggregates before generating fPCR beta panels.")
  }
}

write_metric_panel <- function(loaded, metric, filename, limits = NULL, include_fpcr = FALSE,
                              panel_height = 2.02, group_labels = NULL) {
  check_beta_metrics(loaded, metric, include_fpcr)
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

time_tick_labels <- function(x) {
  vapply(10^x, function(value) {
    format(signif(value, 2), trim = TRUE, scientific = FALSE)
  }, character(1))
}

write_time_panel <- function(loaded, filename, include_fpcr = FALSE, panel_height = 2.02) {
  data <- loaded$fit_seconds
  models <- if (include_fpcr) loaded$model_names else setdiff(loaded$model_names, "fPCR")
  data$Group <- data[[loaded$varying_options[1]]]
  for (model in models) data[[model]] <- log10(data[[model]])
  data <- tidyr::pivot_longer(data[, c("Group", models)], -Group,
                              names_to = "Model", values_to = "Seconds")
  groups <- sort(unique(data$Group))
  if (any(!is.finite(data$Group) | data$Group <= 0) ||
      any(!is.finite(data$Seconds))) stop("Log-log time panels require positive finite inputs.")
  variable <- switch(loaded$varying_options[1], source_k = "k", n_stat_units = "n",
                     n_locs = "m", NSR_X_final_component = "NSR[X]", NSR_Y = "NSR[Y]")
  if (is.null(variable)) stop("Unknown time-panel variable: ", loaded$varying_options[1])
  medians <- aggregate(Seconds ~ Group + Model, data, median)
  guides <- data.frame()
  if (variable == "k") {
    # Reference slopes only: vertical placement is arbitrary, not a complexity fit.
    dx <- min(0.28 * diff(range(log10(groups))), 0.30)
    start <- min(log10(groups)) + c(0.08, 0.60) * diff(range(log10(groups)))
    guides <- data.frame(
      x = 10^start, xend = 10^(start + dx),
      y = max(medians$Seconds) + 0.18,
      yend = max(medians$Seconds) + 0.18 + c(1, 2) * dx,
      label_x = 10^(start + dx / 2),
      label_y = max(medians$Seconds) + 0.36 + c(1, 2) * dx
    )
    if (variable == "k" && !include_fpcr) {
      guides <- data.frame(x = c(6, 30), xend = c(25, 85),
                           y = log10(c(0.6, 0.08)),
                           yend = log10(c(2.5, 0.08 * (85 / 30)^2)),
                           label_x = c(15, 70), label_y = log10(c(2.3, 0.20)))
    } else {
      guides[, c("y", "yend", "label_y")] <- guides[, c("y", "yend", "label_y")] - 1
      guides[2, c("y", "yend", "label_y")] <- guides[2, c("y", "yend", "label_y")] + 0.5
    }
  }
  y_range <- range(c(medians$Seconds, guides$y, guides$yend, guides$label_y))
  y_breaks <- seq(floor(y_range[1]), ceiling(y_range[2]))
  # Half-decades keep short time ranges readable without changing the log scale.
  if (sum(y_breaks >= y_range[1] & y_breaks <= y_range[2]) < 2L) {
    y_breaks <- seq(floor(2 * y_range[1]) / 2, ceiling(2 * y_range[2]) / 2, 0.5)
  }
  plot <- ggplot(data, aes(x = Group, y = Seconds, colour = Model, group = Model)) +
    geom_vline(xintercept = groups, linewidth = 0.2, colour = "grey") +
    stat_summary(fun = median, geom = "line", linewidth = 1.15) +
    scale_colour_manual(values = setNames(
      loaded$model_colors[match(models, loaded$model_names)], models
    )) +
    scale_x_log10(breaks = groups, labels = trimws(formatC(groups, format = "g", digits = 4))) +
    scale_y_continuous(breaks = y_breaks,
                       labels = time_tick_labels) +
    panel_theme()
  for (i in seq_len(nrow(guides))) {
    plot <- plot +
      annotate("segment", x = guides$x[i], xend = guides$xend[i],
               y = guides$y[i], yend = guides$yend[i],
               linetype = c("dashed", "dotdash")[i], colour = "grey25", linewidth = 0.45) +
      annotate("label", x = guides$label_x[i], y = guides$label_y[i],
               label = paste0("O(", variable, if (i == 2) "^2" else "", ")"),
               parse = TRUE, size = 2.5, colour = "grey25", fill = "white",
               linewidth = 0, label.padding = unit(0.5, "pt"))
  }
  save_panel(plot, filename, height = panel_height, y_axis_width = 8.5)
}

write_structure_panel <- function(loaded, suite, family, metric, filename,
                                  limits, y_breaks, panel_height = 2.02,
                                  group_labels = NULL) {
  structure_dir <- file.path(results_root, suite, "aggregate", family)
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
  model <- get(paste0("model_", model_name), envir = env, inherits = FALSE)
  if (model_name == "fPCR" &&
      !identical(model$results$telemetry$fpcr_score_map, "sequential_projection_v1")) {
    stop("Outdated fPCR score-to-beta map. Re-run make run_test for this suite to refit fPCR before generating its beta maps.")
  }
  model
}

normalize_shape <- function(values) {
  values <- as.matrix(values)
  values / sqrt(sum(values^2))
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
