# R/kpi_product.R
# View P (Produkt) KPI'er. Hver KPI returnerer named list:
#   list(value/data = ..., decision_job = "...", caveat = "...")

#' P1: Aktive sessions (engaged + tidsvindue)
#'
#' Taeller sessions der er engaged (>= engaged_duration_sec), ikke er
#' test-sessions, og som er connected indenfor tidsvinduet.
#'
#' @param facts session_facts tibble fra build_session_facts()
#' @param days antal dage tilbage at kigge (default 28)
#' @param reference_time POSIXct, default Sys.time()
#' @return list med value, days, decision_job, caveat
#' @export
kpi_active_sessions <- function(facts, days = 28L, reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$engaged,
                   !is.na(.data$connected_at),
                   .data$connected_at >= cutoff)
  list(
    value = nrow(filtered),
    days = days,
    decision_job = "Er trafikken stabil? Pludselig drop = produktionsproblem.",
    caveat = paste0("Inkluderer kun sessions >= ",
                     ANALYTICS_CONSTANTS$engaged_duration_sec,
                     "s + ekskluderer test-sessions.")
  )
}

#' P3: Fejl-clusters top-N (normaliseret)
#'
#' Tagger top-N error-signatures rangeret efter antal unikke sessions
#' der ramte signaturen. Ekskluderer test-sessions.
#'
#' @param facts session_facts tibble
#' @param top_n antal cluster-rows at vise (default 10)
#' @param days tidsvindue (default 28)
#' @param reference_time POSIXct, default Sys.time()
#' @return list med data (tibble), decision_job, caveat
#' @export
kpi_error_clusters <- function(facts, top_n = 10L, days = 28L,
                                 reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$n_errors > 0L,
                   !is.na(.data$connected_at),
                   .data$connected_at >= cutoff)

  if (nrow(filtered) == 0L) {
    return(list(
      data = tibble::tibble(error_signature = character(),
                              n_sessions = integer()),
      decision_job = "Hvilke fejl rammer flest unikke sessions?",
      caveat = "Ingen fejl i tidsvinduet."
    ))
  }

  exploded <- tibble::tibble(
    sessionid = rep(filtered$sessionid, lengths(filtered$error_signatures)),
    error_signature = unlist(filtered$error_signatures)
  )

  data <- exploded |>
    dplyr::distinct(.data$sessionid, .data$error_signature) |>
    dplyr::count(.data$error_signature, name = "n_sessions", sort = TRUE) |>
    dplyr::slice_head(n = top_n)

  list(
    data = data,
    decision_job = "Hvilke fejl rammer flest unikke sessions?",
    caveat = "Normaliseret: linjenumre + ID'er erstattet med 'N'."
  )
}

#' P4: Performance percentiler (p50/p95) per metric
#'
#' Beregner p50 og p95 for load_complete_ms, ttfb_ms og dom_ready_ms.
#' Returnerer NA hvis n < perf_min_n.
#'
#' @param facts session_facts tibble
#' @param days tidsvindue (default 28)
#' @param reference_time POSIXct, default Sys.time()
#' @return list med data (tibble), decision_job, caveat
#' @export
kpi_performance_percentiles <- function(facts, days = 28L,
                                          reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   !is.na(.data$connected_at),
                   .data$connected_at >= cutoff)

  metrics <- c("load_complete_ms", "ttfb_ms", "dom_ready_ms")
  rows <- lapply(metrics, function(m) {
    vals <- filtered[[m]]
    vals <- vals[!is.na(vals)]
    if (length(vals) < ANALYTICS_CONSTANTS$perf_min_n) {
      return(tibble::tibble(metric = m, p50 = NA_real_, p95 = NA_real_,
                              n = length(vals)))
    }
    tibble::tibble(metric = m,
                    p50 = stats::quantile(vals, 0.5, names = FALSE),
                    p95 = stats::quantile(vals, 0.95, names = FALSE),
                    n = length(vals))
  })

  list(
    data = dplyr::bind_rows(rows),
    decision_job = "Er load-tid acceptabel? P95 > 5s = undersoeg.",
    caveat = paste0("Vises kun naar n >= ",
                     ANALYTICS_CONSTANTS$perf_min_n, ".")
  )
}
