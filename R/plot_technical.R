# R/plot_technical.R
# ggplot2 grafer til Teknisk-fane

#' Feature-brug (horisontal barchart)
#'
#' @param inputs data.frame med inputs
#' @return ggplot objekt
plot_feature_usage <- function(inputs) {
  if (nrow(inputs) == 0) return(.empty_plot("Ingen data"))

  # Taael brug af noegle-features
  features <- inputs |>
    dplyr::filter(.data$name %in% c("chart_type", "skift_column", "frys_column")) |>
    dplyr::count(.data$name, .data$value, sort = TRUE, name = "antal") |>
    dplyr::slice_head(n = 15) |>
    dplyr::mutate(label = paste0(.data$name, ": ", .data$value)) |>
    dplyr::mutate(label = stats::reorder(.data$label, .data$antal))

  if (nrow(features) == 0) return(.empty_plot("Ingen feature-data"))

  ggplot2::ggplot(features, ggplot2::aes(x = .data$antal, y = .data$label)) +
    ggplot2::geom_col(fill = "#8e44ad") +
    ggplot2::labs(x = "Antal", y = NULL, title = "Feature-brug") +
    ggplot2::theme_minimal()
}

#' Wizard-flow funnel med frafald (stacked barchart)
#'
#' @param sessions data.frame med sessions
#' @param inputs data.frame med inputs
#' @return ggplot objekt
plot_wizard_funnel_detailed <- function(sessions, inputs) {
  total <- nrow(sessions)
  if (total == 0) return(.empty_plot("Ingen data"))

  upload_count <- total
  analyser_count <- if (nrow(inputs) > 0) {
    inputs |> dplyr::filter(.data$name == "chart_type") |>
      dplyr::pull(.data$session) |> dplyr::n_distinct()
  } else 0L
  eksport_count <- if (nrow(inputs) > 0) {
    inputs |> dplyr::filter(grepl("export", .data$name, fixed = TRUE)) |>
      dplyr::pull(.data$session) |> dplyr::n_distinct()
  } else 0L

  funnel <- data.frame(
    trin = factor(c("Upload", "Analyser", "Eksport"), levels = c("Upload", "Analyser", "Eksport")),
    antal = c(upload_count, analyser_count, eksport_count),
    frafald_pct = c(NA, round((1 - analyser_count / max(upload_count, 1)) * 100, 1),
                    round((1 - eksport_count / max(analyser_count, 1)) * 100, 1))
  )

  ggplot2::ggplot(funnel, ggplot2::aes(x = .data$trin, y = .data$antal)) +
    ggplot2::geom_col(fill = c("#3498db", "#2ecc71", "#e67e22")) +
    ggplot2::geom_text(ggplot2::aes(label = paste0(.data$antal, "\n(",
      ifelse(is.na(.data$frafald_pct), "", paste0("-", .data$frafald_pct, "%")), ")")),
      vjust = -0.3, size = 3.5) +
    ggplot2::labs(x = NULL, y = "Sessions", title = "Wizard-flow med frafald") +
    ggplot2::theme_minimal()
}

#' Fejl-oversigt (top fejltyper)
#'
#' @param errors data.frame med errors
#' @return ggplot objekt
plot_error_overview <- function(errors) {
  if (nrow(errors) == 0) return(.empty_plot("Ingen fejl registreret"))

  top_errors <- errors |>
    dplyr::count(.data$error, sort = TRUE, name = "antal") |>
    dplyr::slice_head(n = 10) |>
    dplyr::mutate(error = stringr::str_trunc(.data$error, 50)) |>
    dplyr::mutate(error = stats::reorder(.data$error, .data$antal))

  ggplot2::ggplot(top_errors, ggplot2::aes(x = .data$antal, y = .data$error)) +
    ggplot2::geom_col(fill = "#e74c3c") +
    ggplot2::labs(x = "Antal", y = NULL, title = "Top 10 fejltyper") +
    ggplot2::theme_minimal()
}

#' Performance boxplot
#'
#' @param perf_metrics data.frame med performance metrics
#' @return ggplot objekt
plot_performance <- function(perf_metrics) {
  if (nrow(perf_metrics) == 0) return(.empty_plot("Ingen performance-data"))

  # Filtrér relevante metrikker
  perf_long <- perf_metrics |>
    dplyr::select(dplyr::any_of(c("type", "load_complete_ms", "dom_ready_ms",
                                   "ttfb_ms", "duration_ms"))) |>
    tidyr::pivot_longer(
      cols = dplyr::any_of(c("load_complete_ms", "dom_ready_ms", "ttfb_ms", "duration_ms")),
      names_to = "metric",
      values_to = "ms"
    ) |>
    dplyr::filter(!is.na(.data$ms))

  if (nrow(perf_long) == 0) return(.empty_plot("Ingen performance-data"))

  ggplot2::ggplot(perf_long, ggplot2::aes(x = .data$metric, y = .data$ms)) +
    ggplot2::geom_boxplot(fill = "#f39c12", alpha = 0.6) +
    ggplot2::labs(x = NULL, y = "Millisekunder", title = "Performance-fordeling") +
    ggplot2::coord_flip() +
    ggplot2::theme_minimal()
}

#' Browser/OS donut chart
#'
#' @param client_meta data.frame med client metadata
#' @return ggplot objekt
plot_browser_os <- function(client_meta) {
  if (nrow(client_meta) == 0) return(.empty_plot("Ingen browser-data"))

  # Enkel browser-parsing fra user_agent
  browser_data <- client_meta |>
    dplyr::mutate(browser = dplyr::case_when(
      grepl("Chrome", .data$user_agent) & !grepl("Edg", .data$user_agent) ~ "Chrome",
      grepl("Firefox", .data$user_agent) ~ "Firefox",
      grepl("Safari", .data$user_agent) & !grepl("Chrome", .data$user_agent) ~ "Safari",
      grepl("Edg", .data$user_agent) ~ "Edge",
      TRUE ~ "Anden"
    )) |>
    dplyr::count(.data$browser, sort = TRUE, name = "antal")

  ggplot2::ggplot(browser_data, ggplot2::aes(x = "", y = .data$antal, fill = .data$browser)) +
    ggplot2::geom_col(width = 1) +
    ggplot2::coord_polar("y") +
    ggplot2::labs(fill = "Browser", title = "Browser-fordeling") +
    ggplot2::theme_void() +
    ggplot2::theme(legend.position = "bottom")
}

#' Returning visitors (stacked area chart)
#'
#' @param sessions data.frame med sessions
#' @param client_meta data.frame med client metadata
#' @return ggplot objekt
plot_returning_visitors <- function(sessions, client_meta) {
  if (nrow(sessions) == 0 || nrow(client_meta) == 0) return(.empty_plot("Ingen data"))

  # Foerste besog per visitor_id
  if (!"visitor_id" %in% names(client_meta)) return(.empty_plot("Ingen visitor-ID data"))

  first_seen <- client_meta |>
    dplyr::group_by(.data$visitor_id) |>
    dplyr::summarise(first_visit = min(.data$timestamp, na.rm = TRUE), .groups = "drop")

  visitor_sessions <- client_meta |>
    dplyr::mutate(dato = as.Date(.data$timestamp)) |>
    dplyr::left_join(first_seen, by = "visitor_id") |>
    dplyr::mutate(type = ifelse(as.Date(.data$first_visit) == .data$dato, "Ny", "Tilbagevendende")) |>
    dplyr::count(.data$dato, .data$type, name = "antal")

  ggplot2::ggplot(visitor_sessions, ggplot2::aes(x = .data$dato, y = .data$antal, fill = .data$type)) +
    ggplot2::geom_area(alpha = 0.7) +
    ggplot2::scale_fill_manual(values = c("Ny" = "#3498db", "Tilbagevendende" = "#2ecc71")) +
    ggplot2::labs(x = NULL, y = "Antal", fill = NULL, title = "Nye vs. tilbagevendende besogende") +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "bottom")
}

#' Tidsmoenstre heatmap (ugedag x time)
#'
#' @param sessions data.frame med sessions
#' @return ggplot objekt
plot_time_patterns <- function(sessions) {
  if (nrow(sessions) == 0) return(.empty_plot("Ingen data"))

  time_data <- sessions |>
    dplyr::mutate(
      connected = lubridate::ymd_hms(.data$server_connected, quiet = TRUE),
      ugedag = factor(
        lubridate::wday(.data$connected, label = TRUE, abbr = TRUE, locale = "da_DK.UTF-8"),
        levels = c("man", "tir", "ons", "tor", "fre", "lor", "son")
      ),
      time = lubridate::hour(.data$connected)
    ) |>
    dplyr::count(.data$ugedag, .data$time, name = "antal")

  ggplot2::ggplot(time_data, ggplot2::aes(x = .data$time, y = .data$ugedag, fill = .data$antal)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::scale_fill_gradient(low = "#eef6ff", high = "#2c3e50") +
    ggplot2::scale_x_continuous(breaks = seq(0, 23, 3)) +
    ggplot2::labs(x = "Time", y = NULL, fill = "Sessions", title = "Tidsmoenstre (ugedag x time)") +
    ggplot2::theme_minimal()
}

# Intern helper til tom graf
.empty_plot <- function(label = "Ingen data") {
  ggplot2::ggplot() +
    ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = label, size = 6, color = "grey60")
}
