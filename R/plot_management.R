# R/plot_management.R
# View L (Ledelse) plot-funktioner.

#' L2: Eksport-format breakdown
#'
#' @param export_data tibble (format, n_sessions)
#' @return ggplot
#' @export
plot_export_breakdown <- function(export_data) {
  if (nrow(export_data) == 0L) return(.empty_ggplot("Ingen eksporter"))
  export_data$format <- stats::reorder(export_data$format,
                                         export_data$n_sessions)
  ggplot2::ggplot(export_data,
                   ggplot2::aes(x = .data$n_sessions, y = .data$format)) +
    ggplot2::geom_col(fill = "#e67e22") +
    ggplot2::labs(x = "Sessions", y = NULL, title = "Eksport-format") +
    ggplot2::theme_minimal()
}

#' L4: Weekly trend med partial-uge-markering
#'
#' @param trend_data tibble (iso_week, week_start, n_sessions, is_partial)
#' @return ggplot
#' @export
plot_weekly_trend <- function(trend_data) {
  if (nrow(trend_data) == 0L) return(.empty_ggplot())
  trend_data$bar_fill <- ifelse(trend_data$is_partial, "Igangvaerende uge",
                                  "Afsluttet uge")
  ggplot2::ggplot(trend_data, ggplot2::aes(x = .data$week_start,
                                              y = .data$n_sessions,
                                              fill = .data$bar_fill)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = c("Afsluttet uge" = "#3498db",
                                            "Igangvaerende uge" = "#bdc3c7")) +
    ggplot2::labs(x = NULL, y = "Sessions", fill = NULL,
                   title = "Sessions per uge") +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "bottom")
}

#' L3: Top indicator clusters
#'
#' @param indicator_data tibble (cluster, n_sessions, n_variants)
#' @return ggplot
#' @export
plot_top_indicators <- function(indicator_data) {
  if (nrow(indicator_data) == 0L) return(.empty_ggplot())
  indicator_data$cluster <- stats::reorder(indicator_data$cluster,
                                              indicator_data$n_sessions)
  ggplot2::ggplot(indicator_data,
                   ggplot2::aes(x = .data$n_sessions, y = .data$cluster)) +
    ggplot2::geom_col(fill = "#27ae60") +
    ggplot2::geom_text(ggplot2::aes(label = paste0(.data$n_variants, " varianter")),
                        hjust = -0.2, size = 3) +
    ggplot2::labs(x = "Unikke sessions", y = NULL,
                   title = "Top indikator-clusters") +
    ggplot2::theme_minimal()
}

#' L5: Cohort retention heatmap
#'
#' @param cohort_data tibble (cohort_week, weeks_since, retention_pct)
#' @return ggplot
#' @export
plot_cohort_retention <- function(cohort_data) {
  if (nrow(cohort_data) == 0L) return(.empty_ggplot())
  ggplot2::ggplot(cohort_data, ggplot2::aes(x = .data$weeks_since,
                                               y = .data$cohort_week,
                                               fill = .data$retention_pct)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = paste0(.data$retention_pct, "%")),
                        size = 3) +
    ggplot2::scale_fill_gradient(low = "#ecf0f1", high = "#2c3e50",
                                   na.value = "white") +
    ggplot2::labs(x = "Uger siden foerste besoeg", y = "Kohorte",
                   fill = "Retention %", title = "Cohort retention") +
    ggplot2::theme_minimal()
}

#' L6: Use case heatmap (chart_type x cluster)
#'
#' @param heatmap_data tibble (chart_type, cluster, n_sessions)
#' @return ggplot
#' @export
plot_use_case_heatmap <- function(heatmap_data) {
  if (nrow(heatmap_data) == 0L) return(.empty_ggplot())
  ggplot2::ggplot(heatmap_data, ggplot2::aes(x = .data$chart_type,
                                                y = .data$cluster,
                                                fill = .data$n_sessions)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = .data$n_sessions), size = 3) +
    ggplot2::scale_fill_gradient(low = "#eef6ff", high = "#2c3e50") +
    ggplot2::labs(x = "Chart-type", y = "Indikator-cluster",
                   fill = "Sessions", title = "Use case-fordeling") +
    ggplot2::theme_minimal()
}
