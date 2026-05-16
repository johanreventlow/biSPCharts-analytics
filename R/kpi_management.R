# R/kpi_management.R
# View L (Ledelse) KPI'er.

#' L1: Aktive analyser (sessions naaede output)
#'
#' @param facts session_facts
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med value, decision_job
#' @export
kpi_active_analyses <- function(facts, days = 28L, reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$step_output_generated,
                   .data$connected_at >= cutoff)
  list(
    value = nrow(filtered),
    days = days,
    decision_job = "Bruges systemet operationelt?",
    caveat = "Taeller completed visualizations, ej validerede patient-analyser."
  )
}

#' L2: Eksport-breakdown per format
#'
#' @param facts session_facts
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med data, decision_job
#' @export
kpi_export_breakdown <- function(facts, days = 28L, reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$step_exported,
                   .data$connected_at >= cutoff)

  if (nrow(filtered) == 0L) {
    return(list(
      data = tibble::tibble(format = character(), n_sessions = integer()),
      decision_job = "Forlader output appen? Hvor (PDF/Word/AI/billede)?",
      caveat = "Ingen eksporter i vinduet."
    ))
  }

  formats <- unlist(filtered$export_formats)
  # Normaliser: strip eventuelle suffixer (fx "pdfclick" -> "pdf") fordi
  # upstream regex i transform_sessions.R kun matcher "^export_(fmt)_" og
  # efterlader resten af input-navnet.
  known_formats <- c("pdf", "docx", "png", "svg", "ai")
  formats <- vapply(formats, function(f) {
    hit <- known_formats[startsWith(f, known_formats)]
    if (length(hit) == 0L) f else hit[which.max(nchar(hit))]
  }, character(1), USE.NAMES = FALSE)

  data <- tibble::tibble(format = formats) |>
    dplyr::count(.data$format, name = "n_sessions", sort = TRUE)

  list(
    data = data,
    decision_job = "Forlader output appen? Hvor (PDF/Word/AI/billede)?",
    caveat = "Praeciseres i Fase 2 (Bundle A) via export_initiated-event."
  )
}

#' L4: Uge-trend med partial-week-flag
#'
#' @param facts session_facts
#' @param n_weeks antal uger at vise
#' @param reference_time POSIXct
#' @return list med data, decision_job
#' @export
kpi_weekly_trend <- function(facts, n_weeks = 12L, reference_time = Sys.time()) {
  if (nrow(facts) == 0L) {
    return(list(
      data = tibble::tibble(iso_week = character(), week_start = as.Date(character()),
                             n_sessions = integer(), is_partial = logical()),
      decision_job = "Vokser brug eller plateauer?",
      caveat = "Ingen data."
    ))
  }

  cleaned <- facts |> dplyr::filter(!.data$is_test_session)
  cleaned$iso_year <- lubridate::isoyear(cleaned$connected_at)
  cleaned$iso_wk <- lubridate::isoweek(cleaned$connected_at)
  cleaned$iso_week <- sprintf("%d-W%02d", cleaned$iso_year, cleaned$iso_wk)

  today_week_start <- lubridate::floor_date(reference_time, unit = "week",
                                              week_start = 1L)
  cutoff_start <- today_week_start - lubridate::weeks(n_weeks - 1L)

  data <- cleaned |>
    dplyr::filter(.data$connected_at >= cutoff_start) |>
    dplyr::group_by(.data$iso_year, .data$iso_wk, .data$iso_week) |>
    dplyr::summarise(
      week_start = min(.data$connected_at),
      n_sessions = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$iso_year, .data$iso_wk)

  this_week_label <- sprintf("%d-W%02d", lubridate::isoyear(reference_time),
                               lubridate::isoweek(reference_time))
  data$is_partial <- data$iso_week == this_week_label

  list(
    data = data,
    decision_job = "Vokser brug eller plateauer?",
    caveat = "Partial uge maerket med is_partial = TRUE."
  )
}
