# Generate the CSV rows used by review_simulation_results.tex.
# Run from the repository root with:
#   Rscript reports/generate_gcv_review_tables.R

families <- c("sensitivity", "sensitivity_high_NSRX")
output_dir <- file.path("reports", "gcv_tables")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

format_lambda <- function(value) {
  if (is.na(value)) return("")
  if (value == 0) return("0")
  exponent <- round(log10(value))
  if (isTRUE(all.equal(value, 10^exponent))) {
    return(sprintf("10^{%d}", exponent))
  }
  format(value, scientific = TRUE, digits = 3, trim = TRUE)
}

median_by_component <- function(data, lambda_value) {
  selected <- data[data$lambda == lambda_value, , drop = FALSE]
  selected <- selected[is.finite(selected$R1_fPLS), , drop = FALSE]
  aggregate(
    selected[["R1_fPLS"]],
    list(h = as.integer(selected$Group)),
    median
  )
}

selection_distribution <- function(data) {
  selected <- data[data$lambda == -1, , drop = FALSE]
  selected <- selected[is.finite(selected$R1_fPLS), , drop = FALSE]
  distributions <- lapply(split(selected, selected$Group), function(rows) {
    counts <- table(rows$R1_fPLS)
    counts <- counts[order(-as.numeric(counts), as.numeric(names(counts)))]
    percentages <- 100 * as.numeric(counts) / sum(counts)
    formatted_percentages <- vapply(percentages, function(value) {
      if (abs(value - round(value)) < 1e-8) {
        sprintf("%d", round(value))
      } else {
        sprintf("%.1f", value)
      }
    }, character(1))
    paste(
      paste0(
        vapply(as.numeric(names(counts)), format_lambda, character(1)),
        "\\,(", formatted_percentages, "\\%)"
      ),
      collapse = "\\;;\\;"
    )
  })
  data.frame(
    h = as.integer(names(distributions)),
    distribution = unname(unlist(distributions)),
    stringsAsFactors = FALSE
  )
}

best_fixed <- function(data, higher_is_better) {
  fixed <- data[is.finite(data$lambda) & data$lambda > 0, , drop = FALSE]
  summaries <- aggregate(
    fixed[["R1_fPLS"]],
    list(h = as.integer(fixed$Group), lambda = fixed$lambda),
    median
  )
  names(summaries)[3] <- "value"
  chosen <- do.call(rbind, lapply(split(summaries, summaries$h), function(rows) {
    rows <- rows[order(rows$lambda), , drop = FALSE]
    index <- if (higher_is_better) which.max(rows$value) else which.min(rows$value)
    rows[index, , drop = FALSE]
  }))
  chosen[order(chosen$h), , drop = FALSE]
}

make_table <- function(loaded, family, metric_name, data, higher_is_better) {
  fixed <- best_fixed(data, higher_is_better)
  gcv_metric <- median_by_component(data, -1)
  mv_metric <- median_by_component(data, 0)
  gcv_direction <- selection_distribution(loaded$direction_lambda)
  gcv_loading <- selection_distribution(loaded$loading_lambda)

  rows <- data.frame(
    h = fixed$h,
    lambda_fixed = vapply(fixed$lambda, format_lambda, character(1)),
    lambda_gcv_dir = gcv_direction$distribution[match(fixed$h, gcv_direction$h)],
    lambda_gcv_load = gcv_loading$distribution[match(fixed$h, gcv_loading$h)],
    metric_fixed = sprintf("%.4f", fixed$value),
    metric_gcv = sprintf("%.4f", gcv_metric$x[match(fixed$h, gcv_metric$h)]),
    metric_mv = sprintf("%.4f", mv_metric$x[match(fixed$h, mv_metric$h)]),
    stringsAsFactors = FALSE
  )
  write.csv(
    rows,
    file.path(output_dir, sprintf("%s_%s.csv", family, metric_name)),
    row.names = FALSE,
    quote = FALSE
  )
}

for (family in families) {
  loaded <- readRDS(file.path(
    "results", "GCV", "aggregate", family, sprintf("loaded_%s.rds", family)
  ))
  metrics <- list(
    Y_reconstruction = list(data = loaded$rmse$Y_reconstruction, higher = FALSE),
    X_reconstruction = list(data = loaded$rmse$X_reconstruction_locations, higher = FALSE),
    Beta = list(data = loaded$cosine$Beta_locations, higher = TRUE),
    X_direction = list(data = loaded$cosine$X_direction_locations, higher = TRUE),
    X_loading = list(data = loaded$cosine$X_loading_locations, higher = TRUE),
    X_scores = list(data = loaded$cosine$X_latent_scores, higher = TRUE)
  )
  for (metric_name in names(metrics)) {
    make_table(
      loaded,
      family,
      metric_name,
      metrics[[metric_name]]$data,
      metrics[[metric_name]]$higher
    )
  }
}
