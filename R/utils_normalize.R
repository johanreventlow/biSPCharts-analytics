# R/utils_normalize.R
# String-normalisering, konstanter, test-session-heuristik.

#' Centrale konstanter for analytics-dashboardet
#'
#' Eksporteres som named list saa de er let testbare + dokumenterede.
#' @export
ANALYTICS_CONSTANTS <- list(
  engaged_duration_sec = 30L,
  window_short_days = 7L,
  window_long_days = 28L,
  indicator_cluster_threshold = 0.2,
  indicator_min_length = 3L,
  stop_words = c("test", "abc", "asdf", "qwerty", "xxx", "123",
                 "test123", "lorem", "ipsum"),
  browser_min_sessions = 5L,
  heatmap_min_cell = 3L,
  perf_min_n = 10L,
  test_session_max_duration = 10L,
  export_regex = "^export_(pdf|docx|png|svg|ai)_.*$",
  column_input_regex = "^(skift|frys|target|maal)_column$"
)

#' Normaliser fri tekst: trim + lowercase + collapse whitespace
#'
#' @param x character-vektor
#' @return normaliseret character-vektor (NA forbliver NA)
#' @export
normalize_text <- function(x) {
  if (length(x) == 0L) return(x)
  result <- tolower(trimws(x))
  result <- gsub("\\s+", " ", result)
  result[is.na(x)] <- NA_character_
  result
}

#' Tjek om streng er kendt test/stop-ord
#'
#' @param x character-vektor
#' @return logical-vektor
#' @export
is_stop_word <- function(x) {
  normalized <- normalize_text(x)
  normalized %in% ANALYTICS_CONSTANTS$stop_words
}

#' Parse user_agent til browser + OS
#'
#' @param ua character-vektor med user-agent strings
#' @return tibble med kolonner browser, os
#' @export
parse_user_agent <- function(ua) {
  if (length(ua) == 0L) {
    return(tibble::tibble(browser = character(), os = character()))
  }
  browser <- dplyr::case_when(
    is.na(ua) ~ "Anden",
    grepl("Edg", ua) ~ "Edge",
    grepl("Chrome", ua) & !grepl("Edg", ua) ~ "Chrome",
    grepl("Firefox", ua) ~ "Firefox",
    grepl("Safari", ua) & !grepl("Chrome", ua) ~ "Safari",
    TRUE ~ "Anden"
  )
  os <- dplyr::case_when(
    is.na(ua) ~ "Anden",
    grepl("Macintosh|Mac OS", ua) ~ "macOS",
    grepl("Windows", ua) ~ "Windows",
    grepl("Linux", ua) ~ "Linux",
    grepl("iPhone|iPad|iOS", ua) ~ "iOS",
    grepl("Android", ua) ~ "Android",
    TRUE ~ "Anden"
  )
  tibble::tibble(browser = browser, os = os)
}

#' Normaliser fejl-besked: strip linjenumre + dynamiske integer-ID'er
#'
#' Erstatter "line 42" -> "line N", "id 12345" -> "id N" osv.
#' @param msg character-vektor
#' @return normaliseret character-vektor
#' @export
normalize_error_message <- function(msg) {
  if (length(msg) == 0L) return(msg)
  result <- gsub("\\bline\\s+\\d+", "line N", msg, ignore.case = TRUE)
  result <- gsub("\\bid\\s+\\d+", "id N", result, ignore.case = TRUE)
  result <- gsub("\\b\\d{4,}\\b", "N", result)
  result
}

#' Flag test-sessions via heuristik
#'
#' Sessions er test hvis:
#' - duration_sec < test_session_max_duration (default 10s), ELLER
#' - indicator_title_raw matcher stop-liste
#'
#' @param facts tibble med kolonner sessionid, duration_sec, (valgfri) indicator_title_raw
#' @return logical-vektor med samme laengde som rows i facts
#' @export
is_test_session <- function(facts) {
  short <- !is.na(facts$duration_sec) &
    facts$duration_sec < ANALYTICS_CONSTANTS$test_session_max_duration

  stop_title <- if ("indicator_title_raw" %in% names(facts)) {
    is_stop_word(facts$indicator_title_raw)
  } else {
    rep(FALSE, nrow(facts))
  }

  short | stop_title
}
