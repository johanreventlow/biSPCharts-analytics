# R/plot_overview.R
# ggplot2 grafer til Overblik-fane

#' Sessions over tid (30 dage, med glidende gennemsnit)
#'
#' @param sessions data.frame med sessions
#' @return ggplot objekt
plot_sessions_over_time <- function(sessions) {
  if (nrow(sessions) == 0) return(ggplot2::ggplot() + ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Ingen data", size = 6, color = "grey60"))

  daily <- sessions |>
    dplyr::mutate(dato = as.Date(lubridate::ymd_hms(.data$server_connected, quiet = TRUE))) |>
    dplyr::filter(.data$dato >= Sys.Date() - 30) |>
    dplyr::count(.data$dato, name = "sessions")

  # Udfyld manglende dage med 0
  all_days <- data.frame(dato = seq(Sys.Date() - 30, Sys.Date(), by = "day"))
  daily <- dplyr::left_join(all_days, daily, by = "dato") |>
    dplyr::mutate(sessions = tidyr::replace_na(.data$sessions, 0))

  # 7-dages glidende gennemsnit
  daily <- daily |>
    dplyr::mutate(
      gns_7d = zoo::rollmean(.data$sessions, k = 7, fill = NA, align = "right")
    )

  ggplot2::ggplot(daily, ggplot2::aes(x = .data$dato)) +
    ggplot2::geom_col(ggplot2::aes(y = .data$sessions), fill = "#3498db", alpha = 0.4) +
    ggplot2::geom_line(ggplot2::aes(y = .data$gns_7d), color = "#2c3e50", linewidth = 1, na.rm = TRUE) +
    ggplot2::scale_x_date(date_labels = "%d. %b", date_breaks = "1 week") +
    ggplot2::labs(x = NULL, y = "Sessions", title = "Sessions per dag (seneste 30 dage)") +
    ggplot2::theme_minimal()
}

#' Top 10 indikatorer (horisontal barchart)
#'
#' @param inputs data.frame med inputs
#' @return ggplot objekt
plot_top_indicators <- function(inputs) {
  if (nrow(inputs) == 0) return(ggplot2::ggplot() + ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Ingen data", size = 6, color = "grey60"))

  indicators <- inputs |>
    dplyr::filter(.data$name == "indicator_title", nchar(.data$value) > 0) |>
    dplyr::count(.data$value, sort = TRUE, name = "antal") |>
    dplyr::slice_head(n = 10)

  if (nrow(indicators) == 0) return(ggplot2::ggplot() + ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Ingen indikatorer registreret", size = 5, color = "grey60"))

  indicators <- indicators |>
    dplyr::mutate(value = stats::reorder(.data$value, .data$antal))

  ggplot2::ggplot(indicators, ggplot2::aes(x = .data$antal, y = .data$value)) +
    ggplot2::geom_col(fill = "#27ae60") +
    ggplot2::labs(x = "Antal sessions", y = NULL, title = "Top 10 indikatorer") +
    ggplot2::theme_minimal()
}

#' Wizard completion funnel
#'
#' @param sessions data.frame med sessions
#' @param inputs data.frame med inputs
#' @return ggplot objekt
plot_wizard_funnel <- function(sessions, inputs) {
  total <- nrow(sessions)
  if (total == 0) return(ggplot2::ggplot() + ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = "Ingen data", size = 6, color = "grey60"))

  # Upload = alle sessions, Analyser = sessions med chart_type, Eksport = sessions med export format
  upload_count <- total
  analyser_count <- if (nrow(inputs) > 0 && "sessionid" %in% names(inputs)) {
    inputs |> dplyr::filter(.data$name == "chart_type") |>
      dplyr::pull(.data$sessionid) |> dplyr::n_distinct()
  } else 0L
  eksport_count <- if (nrow(inputs) > 0 && "sessionid" %in% names(inputs)) {
    inputs |> dplyr::filter(grepl("export", .data$name, fixed = TRUE)) |>
      dplyr::pull(.data$sessionid) |> dplyr::n_distinct()
  } else 0L

  funnel <- data.frame(
    trin = factor(c("Upload", "Analyser", "Eksport"), levels = c("Upload", "Analyser", "Eksport")),
    antal = c(upload_count, analyser_count, eksport_count)
  )

  ggplot2::ggplot(funnel, ggplot2::aes(x = .data$trin, y = .data$antal)) +
    ggplot2::geom_col(fill = c("#3498db", "#2ecc71", "#e67e22")) +
    ggplot2::geom_text(ggplot2::aes(label = .data$antal), vjust = -0.5, fontface = "bold") +
    ggplot2::labs(x = NULL, y = "Antal sessions", title = "Wizard-flow") +
    ggplot2::theme_minimal()
}
