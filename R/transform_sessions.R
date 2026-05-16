# R/transform_sessions.R
# Bygger session_facts fact-tabel fra raa shinylogs-tabeller.

#' Build session facts table
#'
#' Joiner sessions/inputs/outputs/errors/client_meta/perf_metrics til
#' én tibble med én row per session. Manglende felter giver NA.
#'
#' @param sessions data.frame fra shinylogs
#' @param inputs data.frame fra shinylogs
#' @param outputs data.frame fra shinylogs
#' @param errors data.frame fra shinylogs
#' @param client_meta data.frame fra extract_client_metadata()
#' @param perf_metrics data.frame fra extract_performance_metrics()
#' @return tibble med session_facts schema
#' @export
build_session_facts <- function(sessions, inputs, outputs, errors,
                                client_meta, perf_metrics) {
  if (!is.data.frame(sessions) || nrow(sessions) == 0L) {
    return(tibble::tibble(
      sessionid = character(), connected_at = as.POSIXct(character()),
      disconnected_at = as.POSIXct(character()),
      duration_sec = numeric(), engaged = logical(),
      visitor_id = character(), browser = character(), os = character(),
      indicator_title_raw = character(), chart_type = character(),
      step_data_proxy = logical(), step_columns = logical(),
      step_chart_type = logical(), step_output_generated = logical(),
      step_exported = logical(), export_formats = list(),
      n_errors = integer(), error_signatures = list(),
      load_complete_ms = numeric(), ttfb_ms = numeric(),
      dom_ready_ms = numeric(), is_test_session = logical()
    ))
  }

  base <- tibble::as_tibble(sessions) |>
    dplyr::mutate(
      connected_at = lubridate::ymd_hms(.data$server_connected, quiet = TRUE),
      disconnected_at = lubridate::ymd_hms(.data$server_disconnected, quiet = TRUE),
      duration_sec = as.numeric(
        difftime(.data$disconnected_at, .data$connected_at, units = "secs")
      ),
      engaged = .data$duration_sec >= ANALYTICS_CONSTANTS$engaged_duration_sec
    )

  # Placeholder-kolonner — udfyldes i task 6
  base$visitor_id <- NA_character_
  base$browser <- NA_character_
  base$os <- NA_character_
  base$indicator_title_raw <- NA_character_
  base$chart_type <- NA_character_
  base$step_data_proxy <- FALSE
  base$step_columns <- FALSE
  base$step_chart_type <- FALSE
  base$step_output_generated <- FALSE
  base$step_exported <- FALSE
  base$export_formats <- vector("list", nrow(base))
  base$n_errors <- 0L
  base$error_signatures <- vector("list", nrow(base))
  base$load_complete_ms <- NA_real_
  base$ttfb_ms <- NA_real_
  base$dom_ready_ms <- NA_real_
  base$is_test_session <- FALSE

  dplyr::select(base, "sessionid", "connected_at", "disconnected_at",
                "duration_sec", "engaged", dplyr::everything(),
                -dplyr::any_of(c("server_connected", "server_disconnected",
                                  "app", "user")))
}
