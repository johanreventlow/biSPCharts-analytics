# R/kpi_calculations.R
# KPI-beregninger for analytics dashboard

#' Beregn alle KPI'er for Overblik-fane
#'
#' @param sessions data.frame med sessions
#' @param inputs data.frame med inputs
#' @param client_meta data.frame med client metadata
#' @param days Antal dage at kigge tilbage (default 7)
#' @return Navngivet liste med KPI-vaerdier
calculate_overview_kpis <- function(sessions, inputs, client_meta, days = 7) {
  if (nrow(sessions) == 0) {
    return(list(
      sessions_count = 0L,
      unique_visitors = 0L,
      completion_rate = NA_real_,
      median_duration_min = NA_real_,
      top_indicator = "Ingen data",
      trend_pct = NA_real_
    ))
  }

  # Parse tidsstempler
  sessions <- sessions |>
    dplyr::mutate(
      connected = lubridate::ymd_hms(.data$server_connected, quiet = TRUE),
      disconnected = lubridate::ymd_hms(.data$server_disconnected, quiet = TRUE)
    )

  cutoff <- lubridate::now() - lubridate::days(days)
  recent <- sessions |> dplyr::filter(.data$connected >= cutoff)

  # Sessions denne uge
  sessions_count <- nrow(recent)

  # Unikke besogende (fra client metadata)
  unique_visitors <- if (nrow(client_meta) > 0 && "visitor_id" %in% names(client_meta)) {
    dplyr::n_distinct(client_meta$visitor_id)
  } else {
    NA_integer_
  }

  # Completion rate: sessions der har et spc_plot output
  sessions_with_plot <- if (nrow(inputs) > 0) {
    chart_sessions <- inputs |>
      dplyr::filter(.data$name == "chart_type") |>
      dplyr::pull(.data$session) |>
      unique()
    length(chart_sessions)
  } else {
    0L
  }
  completion_rate <- if (sessions_count > 0) {
    round(sessions_with_plot / sessions_count * 100, 1)
  } else {
    NA_real_
  }

  # Median session-varighed
  median_duration_min <- if ("session_duration" %in% names(recent) && nrow(recent) > 0) {
    round(stats::median(recent$session_duration, na.rm = TRUE) / 60, 1)
  } else {
    NA_real_
  }

  # Populaereste indikator
  top_indicator <- if (nrow(inputs) > 0 && "name" %in% names(inputs)) {
    indicator_inputs <- inputs |>
      dplyr::filter(.data$name == "indicator_title", nchar(.data$value) > 0)
    if (nrow(indicator_inputs) > 0) {
      indicator_inputs |>
        dplyr::count(.data$value, sort = TRUE) |>
        dplyr::slice(1) |>
        dplyr::pull(.data$value)
    } else {
      "Ingen data"
    }
  } else {
    "Ingen data"
  }

  # Trend: uge-over-uge aendring
  prev_cutoff <- cutoff - lubridate::days(days)
  prev_week <- sessions |>
    dplyr::filter(.data$connected >= prev_cutoff, .data$connected < cutoff)
  trend_pct <- if (nrow(prev_week) > 0) {
    round((sessions_count - nrow(prev_week)) / nrow(prev_week) * 100, 1)
  } else {
    NA_real_
  }

  list(
    sessions_count = sessions_count,
    unique_visitors = unique_visitors,
    completion_rate = completion_rate,
    median_duration_min = median_duration_min,
    top_indicator = top_indicator,
    trend_pct = trend_pct
  )
}
