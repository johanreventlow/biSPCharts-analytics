# R/transform_funnel.R
# 5-trins wizard funnel via Lag 1 proxy.

#' Build wizard funnel fra session_facts
#'
#' Returnerer en tibble med antal sessions per trin + frafalds-procent
#' relativt til foregaaende trin.
#'
#' @param facts tibble fra build_session_facts()
#' @param exclude_test_sessions logical: filtrer is_test_session == TRUE
#' @return tibble (step, step_order, n_sessions, frafald_pct)
#' @export
build_wizard_funnel <- function(facts, exclude_test_sessions = TRUE) {
  steps <- c("Data tilgaengelig", "Kolonner valgt",
             "Diagramtype valgt", "Output genereret", "Eksport")
  step_cols <- c("step_data_proxy", "step_columns",
                 "step_chart_type", "step_output_generated", "step_exported")

  if (!is.data.frame(facts) || nrow(facts) == 0L) {
    return(tibble::tibble(
      step = steps, step_order = seq_along(steps),
      n_sessions = rep(0L, 5L), frafald_pct = rep(NA_real_, 5L)
    ))
  }

  if (isTRUE(exclude_test_sessions) && "is_test_session" %in% names(facts)) {
    facts <- facts[!facts$is_test_session, ]
  }

  counts <- vapply(step_cols, function(col) sum(facts[[col]], na.rm = TRUE),
                   integer(1))
  frafald <- c(NA_real_, vapply(seq_along(counts)[-1L], function(i) {
    if (counts[i - 1L] == 0L) return(NA_real_)
    round((1 - counts[i] / counts[i - 1L]) * 100, 1)
  }, numeric(1)))

  tibble::tibble(
    step = steps,
    step_order = seq_along(steps),
    n_sessions = as.integer(counts),
    frafald_pct = frafald
  )
}
