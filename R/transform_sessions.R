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

  # Indicator title per session (foerste forekomst)
  indicator_per_session <- if (nrow(inputs) > 0L) {
    inputs |>
      dplyr::filter(.data$name == "indicator_title", nchar(.data$value) > 0L) |>
      dplyr::group_by(.data$sessionid) |>
      dplyr::summarise(indicator_title_raw = dplyr::first(.data$value),
                       .groups = "drop")
  } else {
    tibble::tibble(sessionid = character(), indicator_title_raw = character())
  }
  base <- dplyr::left_join(base, indicator_per_session, by = "sessionid")

  # Chart type per session
  chart_per_session <- if (nrow(inputs) > 0L) {
    inputs |>
      dplyr::filter(.data$name == "chart_type", nchar(.data$value) > 0L) |>
      dplyr::group_by(.data$sessionid) |>
      dplyr::summarise(chart_type = dplyr::first(.data$value),
                       .groups = "drop")
  } else {
    tibble::tibble(sessionid = character(), chart_type = character())
  }
  base <- dplyr::left_join(base, chart_per_session, by = "sessionid")

  # Wizard steps
  base$step_columns <- base$sessionid %in% .sessions_matching(
    inputs, ANALYTICS_CONSTANTS$column_input_regex
  )
  base$step_chart_type <- !is.na(base$chart_type)
  base$step_output_generated <- base$sessionid %in% outputs$sessionid
  base$step_exported <- base$sessionid %in% .sessions_matching(
    inputs, ANALYTICS_CONSTANTS$export_regex
  )
  base$step_data_proxy <- base$step_columns | base$step_chart_type |
    base$step_output_generated

  # Export formats per session (list-col)
  base$export_formats <- .export_formats_per_session(inputs, base$sessionid)

  # Errors
  base$n_errors <- 0L
  base$error_signatures <- vector("list", nrow(base))
  if (nrow(errors) > 0L) {
    err_summary <- errors |>
      dplyr::group_by(.data$sessionid) |>
      dplyr::summarise(
        n_errors_new = dplyr::n(),
        error_signatures_new = list(normalize_error_message(.data$error)),
        .groups = "drop"
      )
    base <- dplyr::left_join(base, err_summary, by = "sessionid")
    base$n_errors <- dplyr::coalesce(base$n_errors_new, 0L)
    base$error_signatures <- ifelse(
      lengths(base$error_signatures_new) > 0L,
      base$error_signatures_new, base$error_signatures
    )
    base$n_errors_new <- NULL
    base$error_signatures_new <- NULL
  }

  # Client metadata: visitor_id, browser, os — parsed fra inputs per session
  base$visitor_id <- NA_character_
  base$browser <- NA_character_
  base$os <- NA_character_
  if (nrow(inputs) > 0L) {
    meta_inputs <- inputs |>
      dplyr::filter(grepl("analytics_client_metadata", .data$name, fixed = TRUE))
    meta_parsed <- lapply(seq_len(nrow(meta_inputs)), function(i) {
      v <- tryCatch(jsonlite::fromJSON(meta_inputs$value[i]),
                    error = function(e) NULL)
      if (is.null(v)) return(NULL)
      tibble::tibble(
        sessionid = meta_inputs$sessionid[i],
        visitor_id = v$visitor_id %||% NA_character_,
        user_agent = v$user_agent %||% NA_character_
      )
    })
    meta_parsed <- Filter(Negate(is.null), meta_parsed)
    if (length(meta_parsed) > 0L) {
      visitor_per_session <- dplyr::bind_rows(meta_parsed) |>
        dplyr::group_by(.data$sessionid) |>
        dplyr::summarise(visitor_id = dplyr::first(.data$visitor_id),
                         user_agent = dplyr::first(.data$user_agent),
                         .groups = "drop")
      base <- dplyr::left_join(base, visitor_per_session, by = "sessionid",
                                suffix = c(".old", ""))
      base$visitor_id.old <- NULL
      ua_parsed <- parse_user_agent(base$user_agent)
      base$browser <- ua_parsed$browser
      base$os <- ua_parsed$os
      base$user_agent <- NULL
    }
  }

  # Performance metrics per session via inputs-join
  base$load_complete_ms <- NA_real_
  base$ttfb_ms <- NA_real_
  base$dom_ready_ms <- NA_real_
  if (nrow(inputs) > 0L) {
    perf_inputs <- inputs |>
      dplyr::filter(grepl("analytics_performance", .data$name, fixed = TRUE))
    perf_parsed <- lapply(seq_len(nrow(perf_inputs)), function(i) {
      v <- tryCatch(jsonlite::fromJSON(perf_inputs$value[i]),
                    error = function(e) NULL)
      if (is.null(v)) return(NULL)
      tibble::tibble(
        sessionid = perf_inputs$sessionid[i],
        load_complete_ms = v$load_complete_ms %||% NA_real_,
        ttfb_ms = v$ttfb_ms %||% NA_real_,
        dom_ready_ms = v$dom_ready_ms %||% NA_real_
      )
    })
    perf_parsed <- Filter(Negate(is.null), perf_parsed)
    if (length(perf_parsed) > 0L) {
      perf_df <- dplyr::bind_rows(perf_parsed) |>
        dplyr::group_by(.data$sessionid) |>
        dplyr::summarise(dplyr::across(dplyr::everything(), ~ dplyr::first(.x)),
                          .groups = "drop")
      base <- dplyr::left_join(base, perf_df, by = "sessionid",
                                suffix = c(".old", ""))
      base$load_complete_ms.old <- NULL
      base$ttfb_ms.old <- NULL
      base$dom_ready_ms.old <- NULL
    }
  }

  # Test-session-flag
  base$is_test_session <- is_test_session(base)

  dplyr::select(base, "sessionid", "connected_at", "disconnected_at",
                "duration_sec", "engaged", dplyr::everything(),
                -dplyr::any_of(c("server_connected", "server_disconnected",
                                  "app", "user")))
}

# Internt: sessionids hvis name matcher regex
.sessions_matching <- function(inputs, regex) {
  if (!is.data.frame(inputs) || nrow(inputs) == 0L) return(character())
  matches <- inputs[grepl(regex, inputs$name), ]
  unique(matches$sessionid)
}

# Internt: export_formats per session som list-col
.export_formats_per_session <- function(inputs, sessionids) {
  result <- vector("list", length(sessionids))
  names(result) <- sessionids
  if (!is.data.frame(inputs) || nrow(inputs) == 0L) return(unname(result))
  matches <- inputs[grepl(ANALYTICS_CONSTANTS$export_regex, inputs$name), ]
  if (nrow(matches) == 0L) return(unname(result))
  matches$format <- sub(ANALYTICS_CONSTANTS$export_regex, "\\1", matches$name)
  by_session <- split(matches$format, matches$sessionid)
  for (sid in names(by_session)) {
    if (sid %in% sessionids) result[[sid]] <- unique(by_session[[sid]])
  }
  unname(result)
}
