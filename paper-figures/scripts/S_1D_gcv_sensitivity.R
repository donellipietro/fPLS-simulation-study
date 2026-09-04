# GCV sensitivity figure panels for Affinity. Run with:
# Rscript paper-figures/scripts/S_1D_gcv_sensitivity.R

source(file.path(dirname(normalizePath(sub(
  "^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]
))), "common.R"))

panel_root_override <- Sys.getenv("FPLS_GCV_PANEL_ROOT", unset = "")
if (nzchar(panel_root_override)) {
  panel_root <- normalizePath(panel_root_override, mustWork = FALSE)
}
families <- trimws(strsplit(
  Sys.getenv("FPLS_GCV_FAMILIES", unset = "sensitivity,sensitivity_high_NSRX"), ",",
  fixed = TRUE
)[[1]])
families <- families[nzchar(families)]
aggregate_request <- Sys.getenv("FPLS_GCV_AGGREGATE", unset = "all")

read_gcv_family <- function(family) {
  file <- file.path(
    results_root, "GCV", "aggregate", aggregate_request, paste0("loaded_", family, ".rds")
  )
  if (!file.exists(file)) stop("Missing aggregated GCV results: ", file)
  readRDS(file)
}

tuning_levels <- c("gcv", "mv_pls", paste0("1e", -9:-2))
tuning_labels <- c("GCV", "MV-PLS", as.character(-9:-2))
tuning_axis_labels <- c("GCV", "MV", as.character(-9:-2))
tuning_colors <- c(
  "GCV" = "#377EB8", "MV-PLS" = "#666666",
  stats::setNames(rep("#9ECAE1", 8L), as.character(-9:-2))
)
selection_color <- "#C58A00"

family_suffix <- function(family) {
  if (grepl("_high_NSRX$", family)) "_high_nsrx" else ""
}

tuning_key <- function(lambda) {
  key <- rep(NA_character_, length(lambda))
  key[lambda == -1] <- "gcv"
  key[lambda == 0] <- "mv_pls"
  fixed <- lambda > 0
  key[fixed] <- paste0("1e", as.integer(round(log10(lambda[fixed]))))
  key
}

prepare_tuning_data <- function(data, component = NULL, log_values = FALSE) {
  if (!is.null(component)) data <- dplyr::filter(data, Group == as.character(component))
  data <- dplyr::filter(data, tuning_key(lambda) %in% tuning_levels)
  data$tuning <- factor(tuning_key(data$lambda), levels = tuning_levels, labels = tuning_labels)
  data$value <- data$R1_fPLS
  if (log_values) data$value <- log10(data$value)
  data
}

gcv_panel_theme <- function() {
  panel_theme() +
    theme(
      axis.text.x = element_text(size = 5.5, margin = margin(t = 1.5, unit = "pt")),
      axis.text.y = element_text(size = 5.5),
      plot.margin = margin(3, 4, 3, 3, "pt")
    )
}

gcv_scale_factor <- function(update) {
  if (identical(update, "direction")) 1e-1 else 1e5
}

five_curve_ticks <- function(values) {
  span <- diff(range(values, na.rm = TRUE))
  base <- 10^floor(log10(max(span / 4, .Machine$double.eps)))
  step <- base * c(1, 2, 2.5, 5, 10)[which(c(1, 2, 2.5, 5, 10) >= span / (4 * base))[1]]
  lower <- floor(min(values, na.rm = TRUE) / step) * step
  lower + 0:4 * step
}

fixed_axis_grob <- function(plot, width = 9.5) {
  grob <- ggplotGrob(plot)
  axis_column <- unique(grob$layout$l[grob$layout$name == "axis-l"])
  grob$widths[axis_column] <- unit(width, "mm")
  grob
}

write_performance_panel <- function(loaded, metric, component, filename) {
  data <- prepare_tuning_data(loaded$rmse[[metric]], component)
  plot <- ggplot(data, aes(x = tuning, y = value, fill = tuning)) +
    geom_boxplot(width = 0.62, outlier.size = 0.65, linewidth = 0.28,
                 colour = "#333333") +
    scale_fill_manual(values = tuning_colors, guide = "none") +
    scale_x_discrete(labels = tuning_axis_labels) +
    scale_y_continuous(labels = fixed_y_labels(3), expand = expansion(mult = c(0.04, 0.08))) +
    gcv_panel_theme() +
    theme(axis.text.x = element_text(size = 5.5, margin = margin(t = 1.5, unit = "pt")),
          axis.ticks.x = element_line(linewidth = 0.3))
  save_panel(plot, filename, width = 2.01, height = 1.12, y_axis_width = 7.5)
}

write_fit_time_panel <- function(loaded, filename) {
  data <- prepare_tuning_data(loaded$fit_seconds, log_values = TRUE)
  plot <- ggplot(data, aes(x = tuning, y = value, fill = tuning)) +
    geom_boxplot(width = 0.62, outlier.size = 0.65, linewidth = 0.28,
                 colour = "#333333") +
    scale_fill_manual(values = tuning_colors, guide = "none") +
    scale_x_discrete(labels = tuning_axis_labels) +
    scale_y_continuous(labels = fixed_y_labels(1), expand = expansion(mult = c(0.04, 0.08))) +
    gcv_panel_theme()
  save_panel(plot, filename, width = 6.27, height = 1.18, y_axis_width = 7.5)
}

write_tuning_legend <- function(filename) {
  labels <- c("R1-fPLS (GCV)", "MV-PLS", "R1-fPLS (fixed λ)")
  colors <- unname(tuning_colors[c("GCV", "MV-PLS", "-9")])
  grDevices::cairo_pdf(filename, width = 3.8, height = 0.28, family = "Arial", bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid.newpage()
  # Keep a constant visual gap between the complete key-label pairs, then
  # centre the resulting group on the page.
  page_width <- 3.8 * 25.4
  text_widths <- vapply(
    labels,
    function(label) {
      convertWidth(
        grobWidth(textGrob(label, gp = gpar(fontfamily = "Arial", fontsize = 9))),
        "mm", valueOnly = TRUE
      )
    },
    numeric(1)
  )
  item_widths <- 7 + text_widths
  item_gap <- 3.5
  x <- cumsum(c((page_width - sum(item_widths) - item_gap * (length(labels) - 1)) / 2,
                head(item_widths + item_gap, -1)))
  for (i in seq_along(labels)) {
    grid.rect(
      x = unit(x[i], "mm"), y = unit(3.6, "mm"), width = unit(5, "mm"), height = unit(3.4, "mm"),
      just = c("left", "centre"), gp = gpar(col = NA, fill = colors[i])
    )
    grid.rect(
      x = unit(x[i] + 0.7, "mm"), y = unit(3.6, "mm"), width = unit(3.6, "mm"), height = unit(1.2, "mm"),
      just = c("left", "centre"), gp = gpar(col = NA, fill = "black")
    )
    grid.text(
      labels[i], x = unit(x[i] + 7, "mm"), y = unit(3.6, "mm"), just = c("left", "centre"),
      gp = gpar(fontfamily = "Arial", fontsize = 9)
    )
  }
}

gcv_raw_directories <- function(family, n_reps) {
  option <- paste0(family, "_lambda_gcv")
  dirs <- file.path(results_root, "GCV", family, option, paste0("batch_", seq_len(n_reps)), "raw", "R1_fPLS")
  if (!all(file.exists(dirs))) return(character())
  dirs
}

load_gcv_raw_curves <- function(family, n_reps, n_components) {
  dirs <- gcv_raw_directories(family, n_reps)
  if (!length(dirs)) return(NULL)
  expected <- unlist(lapply(c("direction", "loading"), function(update) {
    unlist(lapply(dirs, function(dir) {
      file.path(dir, paste0(update, "_gcv_h", seq_len(n_components), ".csv"))
    }))
  }))
  if (!all(file.exists(expected))) return(NULL)

  curve_rows <- list()
  index <- 1L
  for (update in c("direction", "loading")) {
    for (batch in seq_along(dirs)) {
      for (component in seq_len(n_components)) {
        curve <- read.csv(file.path(dirs[batch], paste0(update, "_gcv_h", component, ".csv")))
        if (!identical(names(curve), c("lambda", "gcv"))) stop("Invalid GCV curve schema")
        curve_rows[[index]] <- transform(curve, update = update, batch = batch, component = component)
        index <- index + 1L
      }
    }
  }
  dplyr::bind_rows(curve_rows)
}

horizontal_selection_plot <- function(loaded, curves, update, component) {
  update_name <- update
  component_id <- component
  selected <- loaded[[paste0(update, "_lambda")]] |>
    dplyr::filter(lambda == -1, Group == as.character(component)) |>
    dplyr::transmute(batch = dplyr::row_number(), selected_log_lambda = log10(R1_fPLS))
  curve_data <- dplyr::filter(
    curves, .data$update == update_name, .data$component == component_id
  ) |>
    dplyr::mutate(
      log_lambda = log10(lambda)
    )
  summary <- curve_data |>
    dplyr::group_by(log_lambda) |>
    dplyr::summarise(
      median = median(gcv), lower = quantile(gcv, 0.25), upper = quantile(gcv, 0.75),
      .groups = "drop"
    )
  mode_counts <- table(selected$selected_log_lambda)
  mode_lambda <- as.numeric(names(mode_counts)[which.max(mode_counts)])
  mode_index <- which.min(abs(summary$log_lambda - mode_lambda))
  mode_point <- data.frame(
    log_lambda = summary$log_lambda[mode_index],
    gcv = summary$median[mode_index]
  )
  replication_points <- curve_data |>
    dplyr::left_join(selected, by = "batch") |>
    dplyr::filter(!is.na(selected_log_lambda)) |>
    dplyr::group_by(batch) |>
    dplyr::slice_min(abs(log_lambda - selected_log_lambda), n = 1L, with_ties = FALSE) |>
  dplyr::ungroup()
  curve_range <- range(curve_data$gcv, na.rm = TRUE)
  log_range <- log10(curve_range)
  log_ticks <- seq(
    floor(log_range[1] * 10) / 10,
    ceiling(log_range[2] * 10) / 10,
    length.out = 5L
  )
  curve_breaks <- 10^log_ticks
  lower_limit <- 10^(log_ticks[1] - 0.04)
  upper_limit <- 10^(log_ticks[length(log_ticks)] + 0.04)
  plot <- ggplot(curve_data, aes(x = log_lambda, y = gcv, group = batch)) +
    geom_line(colour = "grey55", alpha = 0.28, linewidth = 0.22) +
    geom_ribbon(
      data = summary, aes(x = log_lambda, ymin = lower, ymax = upper),
      inherit.aes = FALSE, fill = "#377EB8", alpha = 0.22
    ) +
    geom_line(data = summary, aes(x = log_lambda, y = median), inherit.aes = FALSE,
              colour = "#377EB8", linewidth = 0.55) +
    geom_point(data = summary, aes(x = log_lambda, y = median), inherit.aes = FALSE,
               colour = "#377EB8", size = 0.8) +
    geom_text(data = replication_points,
              aes(x = log_lambda, y = gcv), inherit.aes = FALSE,
              label = "✦", family = "Arial", size = 1.45,
              colour = "grey55", vjust = 0.52) +
    geom_text(data = mode_point,
              aes(x = log_lambda, y = gcv), inherit.aes = FALSE,
              label = "✦", family = "Arial", size = 4.2,
              colour = selection_color, vjust = 0.52) +
    scale_x_continuous(limits = c(-9.35, -1.65), breaks = -9:-2) +
    scale_y_log10(
      limits = c(lower_limit, upper_limit), breaks = curve_breaks,
      labels = function(values) formatC(log10(values), format = "f", digits = 1)
    ) +
    gcv_panel_theme() +
    theme(
      panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3),
      plot.margin = margin(4, 1, 4, 1, "pt")
    )
  fixed_axis_grob(plot)
}

write_horizontal_selection_preview <- function(family, loaded, curves) {
  final_output <- identical(Sys.getenv("FPLS_GCV_HORIZONTAL_FINAL"), "true")
  figure_id <- paste0(
    "S_1D_gcv_selection", family_suffix(family),
    if (final_output) "" else "_horizontal_preview"
  )
  panel_plots <- list()
  for (update in c("direction", "loading")) {
    panel_plots[[update]] <- lapply(seq_len(4L), function(component) {
      plot <- horizontal_selection_plot(loaded, curves, update, component)
      filename <- panel_path(figure_id, sprintf("%s_h%02d.pdf", update, component))
      grDevices::cairo_pdf(filename, width = 2.83, height = 1.34, family = "Arial", bg = "white")
      grid.newpage()
      grid.draw(plot)
      grDevices::dev.off()
      plot
    })
  }
  if (!final_output) {
    direction_grid <- cowplot::plot_grid(plotlist = panel_plots$direction, ncol = 1)
    loading_grid <- cowplot::plot_grid(plotlist = panel_plots$loading, ncol = 1)
    preview <- cowplot::plot_grid(direction_grid, loading_grid, ncol = 2,
                                  labels = c("Directions", "Loadings"), label_x = 0.5,
                                  label_y = 1, hjust = 0.5, vjust = 1,
                                  label_fontface = "italic", label_size = 9)
    filename <- panel_path(figure_id, "preview.pdf")
    grDevices::cairo_pdf(filename, width = 6.85, height = 6.25, family = "Arial", bg = "white")
    print(preview)
    grDevices::dev.off()
  }
  write_curve_legend(panel_path(figure_id, "curve_legend.pdf"))
}

write_curve_legend <- function(filename) {
  grDevices::cairo_pdf(filename, width = 6.85, height = 0.55, family = "Arial", bg = "white")
  on.exit(grDevices::dev.off(), add = TRUE)
  grid.newpage()
  text_size <- 9
  label_gap <- 3
  row_gap <- 10
  page_width <- 6.85 * 25.4

  centered_items <- function(labels, sample_widths) {
    text_widths <- vapply(labels, function(label) {
      convertWidth(
        grobWidth(textGrob(label, gp = gpar(fontfamily = "Arial", fontsize = text_size))),
        "mm", valueOnly = TRUE
      )
    }, numeric(1))
    item_widths <- sample_widths + label_gap + text_widths
    x <- cumsum(c((page_width - sum(item_widths) - row_gap * (length(labels) - 1)) / 2,
                  head(item_widths + row_gap, -1)))
    list(x = x, widths = item_widths)
  }

  draw_label <- function(label, x, y) {
    grid.text(
      label, x = unit(x, "mm"), y = unit(y, "mm"), just = c("left", "centre"),
      gp = gpar(fontfamily = "Arial", fontsize = text_size)
    )
  }

  ## First row: the two curve styles.
  curve_labels <- c("GCV curves (repetitions)", "GCV curves (median/IQR)")
  curve_items <- centered_items(curve_labels, c(10, 10))
  curve_y <- 10.5
  grid.segments(
    x0 = unit(curve_items$x[1], "mm"), x1 = unit(curve_items$x[1] + 10, "mm"),
    y0 = unit(curve_y, "mm"), y1 = unit(curve_y, "mm"),
    gp = gpar(col = "grey55", alpha = 0.5, lwd = 0.7)
  )
  draw_label(curve_labels[1], curve_items$x[1] + 10 + label_gap, curve_y)
  grid.rect(
    x = unit(curve_items$x[2], "mm"), y = unit(curve_y, "mm"),
    width = unit(10, "mm"), height = unit(2.8, "mm"), just = c("left", "centre"),
    gp = gpar(col = NA, fill = grDevices::adjustcolor("#377EB8", alpha.f = 0.22))
  )
  grid.segments(
    x0 = unit(curve_items$x[2], "mm"), x1 = unit(curve_items$x[2] + 10, "mm"),
    y0 = unit(curve_y, "mm"), y1 = unit(curve_y, "mm"),
    gp = gpar(col = "#377EB8", lwd = 1.2)
  )
  draw_label(curve_labels[2], curve_items$x[2] + 10 + label_gap, curve_y)

  ## Second row: the per-replication and modal selected lambdas.
  selection_labels <- c("Selected λ (repetitions)", "Most selected λ")
  selection_items <- centered_items(selection_labels, c(7, 7))
  selection_y <- 3.8
  grid.text(
    "✦", x = unit(selection_items$x[1] + 3.5, "mm"), y = unit(selection_y, "mm"),
    just = c("centre", "centre"), gp = gpar(col = "grey55", fontfamily = "Arial", fontsize = 7)
  )
  draw_label(selection_labels[1], selection_items$x[1] + 7 + label_gap, selection_y)
  grid.text(
    "✦", x = unit(selection_items$x[2] + 3.5, "mm"), y = unit(selection_y, "mm"),
    just = c("centre", "centre"), gp = gpar(col = selection_color, fontfamily = "Arial", fontsize = 8)
  )
  draw_label(selection_labels[2], selection_items$x[2] + 7 + label_gap, selection_y)
}

write_performance_panels <- function(family, loaded) {
  figure_id <- paste0("S_1D_gcv_performance", family_suffix(family))
  metrics <- c(
    X_reconstruction_locations = "rmse_x",
    Y_reconstruction = "rmse_y",
    Beta1_locations = "rmse_beta"
  )
  for (component in seq_len(4L)) {
    for (metric in names(metrics)) {
      write_performance_panel(
        loaded, metric, component,
        panel_path(figure_id, sprintf("h%02d_%s.pdf", component, metrics[[metric]]))
      )
    }
  }
  write_fit_time_panel(loaded, panel_path(figure_id, "fit_time.pdf"))
  write_tuning_legend(panel_path(figure_id, "tuning_legend.pdf"))
}

for (family in families) {
  loaded <- read_gcv_family(family)
  if (identical(Sys.getenv("FPLS_GCV_LEGENDS_ONLY"), "true")) {
    figure_id <- paste0("S_1D_gcv_performance", family_suffix(family))
    write_tuning_legend(panel_path(figure_id, "tuning_legend.pdf"))
    next
  }
  preview_only <- identical(Sys.getenv("FPLS_GCV_HORIZONTAL_PREVIEW_ONLY"), "true")
  performance_only <- identical(Sys.getenv("FPLS_GCV_PERFORMANCE_ONLY"), "true")
  if (!preview_only || performance_only) {
    write_performance_panels(family, loaded)
  }
  if (performance_only) next
  n_reps <- sum(
    loaded$direction_lambda$lambda == -1 & loaded$direction_lambda$Group == "1"
  )
  curves <- load_gcv_raw_curves(family, n_reps = n_reps, n_components = 4L)
  if (is.null(curves)) {
    message(
      "GCV curve panels for ", family,
      " are waiting for the new raw *_gcv_h*.csv files from Kami."
    )
  } else {
    if (preview_only || identical(Sys.getenv("FPLS_GCV_HORIZONTAL_PREVIEW"), "true") ||
        identical(Sys.getenv("FPLS_GCV_HORIZONTAL_FINAL"), "true")) {
      write_horizontal_selection_preview(family, loaded, curves)
    }
  }
}
