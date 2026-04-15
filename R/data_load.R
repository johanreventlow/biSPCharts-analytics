# R/data_load.R
# Indlaes analytics-data fra Connect Cloud pin

#' Indlaes analytics-data fra pin
#'
#' Laeser "spc-analytics-logs" pin fra Connect Cloud.
#' Returnerer tom default-struktur hvis pin ikke er tilgaengelig.
#'
#' @return Navngivet liste med sessions, inputs, outputs, errors data.frames
load_analytics_data <- function() {
  default_data <- list(
    sessions = data.frame(),
    inputs = data.frame(),
    outputs = data.frame(),
    errors = data.frame()
  )

  tryCatch({
    if (nchar(Sys.getenv("CONNECT_SERVER")) == 0) {
      message("CONNECT_SERVER ikke sat — bruger tom data")
      return(default_data)
    }

    board <- pins::board_connect()
    pin_data <- pins::pin_read(board, "spc-analytics-logs")

    # Valider struktur
    if (!is.list(pin_data)) return(default_data)

    # Sikr at alle 4 kategorier er til stede
    for (cat in c("sessions", "inputs", "outputs", "errors")) {
      if (is.null(pin_data[[cat]])) {
        pin_data[[cat]] <- data.frame()
      }
    }

    pin_data
  }, error = function(e) {
    message(paste("Kunne ikke laese analytics pin:", e$message))
    default_data
  })
}

#' Udtrak client metadata fra inputs
#'
#' Filtrerer analytics_client_metadata inputs og parser til data.frame.
#'
#' @param inputs data.frame med alle inputs fra shinylogs
#' @return data.frame med client metadata (visitor_id, browser, os, screen, etc.)
extract_client_metadata <- function(inputs) {
  if (nrow(inputs) == 0) return(data.frame())

  meta_inputs <- inputs[grepl("analytics_client_metadata", inputs$name, fixed = TRUE), ]
  if (nrow(meta_inputs) == 0) return(data.frame())

  # Parse value-kolonne (JSON-string fra shinylogs)
  parsed <- lapply(meta_inputs$value, function(v) {
    tryCatch(jsonlite::fromJSON(v), error = function(e) NULL)
  })
  parsed <- Filter(Negate(is.null), parsed)
  if (length(parsed) == 0) return(data.frame())

  dplyr::bind_rows(parsed)
}

#' Udtrak performance metrics fra inputs
#'
#' Filtrerer analytics_performance inputs og parser til data.frame.
#'
#' @param inputs data.frame med alle inputs fra shinylogs
#' @return data.frame med performance metrics (type, duration_ms, etc.)
extract_performance_metrics <- function(inputs) {
  if (nrow(inputs) == 0) return(data.frame())

  perf_inputs <- inputs[grepl("analytics_performance", inputs$name, fixed = TRUE), ]
  if (nrow(perf_inputs) == 0) return(data.frame())

  parsed <- lapply(perf_inputs$value, function(v) {
    tryCatch(jsonlite::fromJSON(v), error = function(e) NULL)
  })
  parsed <- Filter(Negate(is.null), parsed)
  if (length(parsed) == 0) return(data.frame())

  dplyr::bind_rows(parsed)
}
