# R/plot_product.R
# View P (Produkt) plot-funktioner.

.empty_ggplot <- function(label = "Ingen data") {
  ggplot2::ggplot() +
    ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = label,
                       size = 6, color = "grey60")
}

#' P1: Aktive sessions trend (daglige counts, engaged only)
#'
#' @param facts session_facts
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return ggplot
#' @export
plot_active_sessions_trend <- function(facts, days = 28L,
                                         reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  cleaned <- facts |>
    dplyr::filter(!.data$is_test_session, .data$engaged,
                   .data$connected_at >= cutoff)
  if (nrow(cleaned) == 0L) return(.empty_ggplot())

  daily <- cleaned |>
    dplyr::mutate(dato = as.Date(.data$connected_at)) |>
    dplyr::count(.data$dato, name = "sessions")

  all_days <- data.frame(dato = seq(as.Date(cutoff), as.Date(reference_time),
                                     by = "day"))
  daily <- dplyr::left_join(all_days, daily, by = "dato") |>
    dplyr::mutate(sessions = tidyr::replace_na(.data$sessions, 0L))

  daily$gns_7d <- zoo::rollmean(daily$sessions, k = 7L, fill = NA,
                                  align = "right")

  ggplot2::ggplot(daily, ggplot2::aes(x = .data$dato)) +
    ggplot2::geom_col(ggplot2::aes(y = .data$sessions),
                       fill = "#3498db", alpha = 0.4) +
    ggplot2::geom_line(ggplot2::aes(y = .data$gns_7d),
                        color = "#2c3e50", linewidth = 1, na.rm = TRUE) +
    ggplot2::labs(x = NULL, y = "Sessions",
                   title = paste0("Aktive sessions (", days,
                                  " dage, engaged >= 30s)")) +
    ggplot2::theme_minimal()
}

#' P2: Wizard funnel barchart
#'
#' @param funnel_data tibble fra build_wizard_funnel()
#' @return ggplot
#' @export
plot_wizard_funnel <- function(funnel_data) {
  if (nrow(funnel_data) == 0L || all(funnel_data$n_sessions == 0L)) {
    return(.empty_ggplot())
  }
  funnel_data$step <- factor(funnel_data$step, levels = funnel_data$step)
  funnel_data$label <- ifelse(
    is.na(funnel_data$frafald_pct),
    as.character(funnel_data$n_sessions),
    sprintf("%d (-%.0f%%)", funnel_data$n_sessions, funnel_data$frafald_pct)
  )
  ggplot2::ggplot(funnel_data,
                   ggplot2::aes(x = .data$step, y = .data$n_sessions)) +
    ggplot2::geom_col(fill = "#3498db") +
    ggplot2::geom_text(ggplot2::aes(label = .data$label),
                        vjust = -0.4, size = 3.5) +
    ggplot2::labs(x = NULL, y = "Sessions", title = "Wizard-frafald per trin") +
    ggplot2::theme_minimal()
}

#' P3: Fejl-cluster top-N barchart
#'
#' @param error_data tibble (error_signature, n_sessions)
#' @return ggplot
#' @export
plot_error_clusters <- function(error_data) {
  if (nrow(error_data) == 0L) return(.empty_ggplot("Ingen fejl"))
  error_data$error_signature <- stringr::str_trunc(error_data$error_signature, 60L)
  error_data$error_signature <- stats::reorder(error_data$error_signature,
                                                 error_data$n_sessions)
  ggplot2::ggplot(error_data,
                   ggplot2::aes(x = .data$n_sessions, y = .data$error_signature)) +
    ggplot2::geom_col(fill = "#e74c3c") +
    ggplot2::labs(x = "Unikke sessions", y = NULL,
                   title = "Top fejl-cluster (normaliseret)") +
    ggplot2::theme_minimal()
}

#' P4: Performance percentiler
#'
#' @param perf_data tibble (metric, p50, p95, n)
#' @return ggplot
#' @export
plot_performance_percentiles <- function(perf_data) {
  if (nrow(perf_data) == 0L || all(is.na(perf_data$p50))) {
    return(.empty_ggplot("Utilstraekkelig data"))
  }
  long <- perf_data |>
    tidyr::pivot_longer(cols = c("p50", "p95"),
                         names_to = "percentile", values_to = "ms")
  ggplot2::ggplot(long, ggplot2::aes(x = .data$metric, y = .data$ms,
                                       fill = .data$percentile)) +
    ggplot2::geom_col(position = "dodge") +
    ggplot2::scale_fill_manual(values = c(p50 = "#3498db", p95 = "#e67e22")) +
    ggplot2::labs(x = NULL, y = "Millisekunder", fill = NULL,
                   title = "Performance p50 / p95") +
    ggplot2::coord_flip() +
    ggplot2::theme_minimal()
}

#' P5: Browser/OS-fejl-rate
#'
#' @param browser_data tibble (browser_os, n_sessions, error_rate)
#' @return ggplot
#' @export
plot_browser_errors <- function(browser_data) {
  if (nrow(browser_data) == 0L) return(.empty_ggplot("Ingen kombinationer"))
  browser_data$browser_os <- stats::reorder(browser_data$browser_os,
                                              browser_data$error_rate)
  ggplot2::ggplot(browser_data, ggplot2::aes(x = .data$error_rate,
                                                y = .data$browser_os,
                                                size = .data$n_sessions)) +
    ggplot2::geom_point(color = "#e74c3c") +
    ggplot2::labs(x = "Fejl-rate (%)", y = NULL, size = "Sessions",
                   title = "Browser/OS x fejl-rate") +
    ggplot2::theme_minimal()
}
