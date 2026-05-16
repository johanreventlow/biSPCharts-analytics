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

#' L3: Top-N normaliserede indikator-clusters
#'
#' @param facts session_facts
#' @param top_n antal clusters at vise
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med data, decision_job
#' @export
kpi_top_indicators <- function(facts, top_n = 20L, days = 28L,
                                 reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$connected_at >= cutoff,
                   !is.na(.data$indicator_title_raw))

  if (nrow(filtered) == 0L) {
    return(list(
      data = tibble::tibble(cluster = character(), n_sessions = integer(),
                             n_variants = integer()),
      decision_job = "Hvilke kvalitetstemaer dominerer?",
      caveat = "Ingen titler i vinduet."
    ))
  }

  clustered <- cluster_indicator_titles(filtered$indicator_title_raw)
  filtered$cluster <- clustered$cluster[match(
    normalize_text(filtered$indicator_title_raw),
    clustered$normalized
  )]

  data <- filtered |>
    dplyr::filter(!is.na(.data$cluster)) |>
    dplyr::group_by(.data$cluster) |>
    dplyr::summarise(
      n_sessions = dplyr::n_distinct(.data$sessionid),
      n_variants = dplyr::n_distinct(.data$indicator_title_raw),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(.data$n_sessions)) |>
    dplyr::slice_head(n = top_n)

  list(
    data = data,
    decision_job = "Hvilke kvalitetstemaer dominerer?",
    caveat = paste0("Fuzzy-cluster (Jaro-Winkler threshold = ",
                     ANALYTICS_CONSTANTS$indicator_cluster_threshold,
                     "). n_variants viser klyngens stoerrelse.")
  )
}

#' L5: Cohort retention (uge-baseret)
#'
#' visitor_id grupperet efter foerste-besoegs-uge; for hver kohorte
#' beregnes % aktive i uge N+0, N+1, ...
#'
#' @param facts session_facts (kraever visitor_id != NA)
#' @param n_weeks antal uger at spore
#' @param reference_time POSIXct
#' @return list med data, decision_job
#' @export
kpi_cohort_retention <- function(facts, n_weeks = 6L, reference_time = Sys.time()) {
  cleaned <- facts |>
    dplyr::filter(!.data$is_test_session, !is.na(.data$visitor_id))

  if (nrow(cleaned) == 0L) {
    return(list(
      data = tibble::tibble(cohort_week = character(), weeks_since = integer(),
                             retention_pct = numeric(), cohort_size = integer()),
      decision_job = "Vender brugere tilbage?",
      caveat = "Ingen visitor_id i data."
    ))
  }

  cleaned$week_start <- lubridate::floor_date(cleaned$connected_at,
                                                unit = "week", week_start = 1L)

  first_seen <- cleaned |>
    dplyr::group_by(.data$visitor_id) |>
    dplyr::summarise(cohort_week_start = min(.data$week_start), .groups = "drop")
  cleaned <- dplyr::left_join(cleaned, first_seen, by = "visitor_id")
  cleaned$weeks_since <- as.integer(
    difftime(cleaned$week_start, cleaned$cohort_week_start, units = "weeks")
  )

  cohort_sizes <- first_seen |>
    dplyr::count(.data$cohort_week_start, name = "cohort_size")

  active <- cleaned |>
    dplyr::filter(.data$weeks_since >= 0L, .data$weeks_since < n_weeks) |>
    dplyr::distinct(.data$cohort_week_start, .data$weeks_since, .data$visitor_id) |>
    dplyr::count(.data$cohort_week_start, .data$weeks_since, name = "n_active")

  data <- dplyr::left_join(active, cohort_sizes, by = "cohort_week_start") |>
    dplyr::mutate(
      retention_pct = round(.data$n_active / .data$cohort_size * 100, 1),
      cohort_week = format(.data$cohort_week_start, "%Y-W%V")
    ) |>
    dplyr::select("cohort_week", "weeks_since", "retention_pct", "cohort_size") |>
    dplyr::arrange(.data$cohort_week, .data$weeks_since)

  list(
    data = data,
    decision_job = "Vender brugere tilbage?",
    caveat = "Lower bound — visitor_id mistes ved cleared localStorage."
  )
}

#' L6: Use case heatmap (chart_type x indicator-cluster)
#'
#' @param facts session_facts
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med data, decision_job
#' @export
kpi_use_case_heatmap <- function(facts, days = 28L, reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$connected_at >= cutoff,
                   !is.na(.data$chart_type),
                   !is.na(.data$indicator_title_raw))

  if (nrow(filtered) == 0L) {
    return(list(
      data = tibble::tibble(chart_type = character(), cluster = character(),
                             n_sessions = integer()),
      decision_job = "Hvilke chart-typer driver hvilke use cases?",
      caveat = "Ingen data."
    ))
  }

  clustered <- cluster_indicator_titles(filtered$indicator_title_raw)
  filtered$cluster <- clustered$cluster[match(
    normalize_text(filtered$indicator_title_raw),
    clustered$normalized
  )]

  data <- filtered |>
    dplyr::filter(!is.na(.data$cluster)) |>
    dplyr::group_by(.data$chart_type, .data$cluster) |>
    dplyr::summarise(n_sessions = dplyr::n_distinct(.data$sessionid),
                      .groups = "drop") |>
    dplyr::filter(.data$n_sessions >= ANALYTICS_CONSTANTS$heatmap_min_cell) |>
    dplyr::arrange(dplyr::desc(.data$n_sessions))

  list(
    data = data,
    decision_job = "Hvilke chart-typer driver hvilke use cases?",
    caveat = paste0("Min ", ANALYTICS_CONSTANTS$heatmap_min_cell,
                     " sessions per celle.")
  )
}
