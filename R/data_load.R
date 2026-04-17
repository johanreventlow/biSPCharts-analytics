# R/data_load.R
# Indlaes analytics-data fra privat GitHub repo (append-model).

#' Tom default-struktur for analytics-data
#'
#' @return Navngivet liste med 4 tomme data.frames
default_analytics_data <- function() {
  list(
    sessions = data.frame(),
    inputs = data.frame(),
    outputs = data.frame(),
    errors = data.frame()
  )
}

#' Bind alle per-session .rds-filer til aggregeret liste
#'
#' Laeser hver .rds-fil i mappen, sammensaetter per kategori via
#' dplyr::bind_rows(). Ugyldige filer springes over med warning.
#'
#' @param sessions_dir Sti til sessions-mappe
#' @return Navngivet liste med 4 data.frames (sessions, inputs, outputs, errors)
bind_session_rds_files <- function(sessions_dir) {
  if (!dir.exists(sessions_dir)) return(default_analytics_data())

  rds_files <- list.files(sessions_dir, pattern = "\\.rds$", full.names = TRUE)
  if (length(rds_files) == 0) return(default_analytics_data())

  parsed <- lapply(rds_files, function(f) {
    tryCatch(readRDS(f), error = function(e) {
      message(paste("Kunne ikke laese", basename(f), "-", e$message))
      NULL
    })
  })
  parsed <- Filter(Negate(is.null), parsed)
  if (length(parsed) == 0) return(default_analytics_data())

  categories <- c("sessions", "inputs", "outputs", "errors")
  result <- lapply(stats::setNames(categories, categories), function(cat) {
    dfs <- lapply(parsed, function(d) d[[cat]] %||% data.frame())
    dfs <- Filter(function(d) is.data.frame(d) && nrow(d) > 0, dfs)
    if (length(dfs) == 0) return(data.frame())
    tryCatch(
      dplyr::bind_rows(dfs),
      error = function(e) {
        message(paste("bind_rows fejlede for", cat, ":", e$message))
        data.frame()
      }
    )
  })

  result
}

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Indlaes analytics-data fra privat GitHub repo
#'
#' Kloner PIN_REPO_URL til midlertidig mappe, laeser alle .rds-filer
#' i sessions/ og bind'er dem sammen. Returnerer tom default-struktur
#' hvis env vars mangler eller clone fejler.
#'
#' Kraever env vars (per-content i Connect Cloud):
#' - GITHUB_PAT: Fine-grained PAT med contents:read paa data-repo
#' - PIN_REPO_URL: HTTPS URL til data-repo
#' - PIN_REPO_BRANCH: Valgfri (default: "main")
#'
#' @return Navngivet liste med sessions, inputs, outputs, errors data.frames
load_analytics_data <- function() {
  pat <- Sys.getenv("GITHUB_PAT")
  repo_url <- Sys.getenv("PIN_REPO_URL")
  branch <- Sys.getenv("PIN_REPO_BRANCH")
  if (nchar(branch) == 0) branch <- "main"

  if (nchar(pat) == 0 || nchar(repo_url) == 0) {
    message("GITHUB_PAT eller PIN_REPO_URL ikke sat — bruger tom data")
    return(default_analytics_data())
  }

  tmp_dir <- tempfile("bispcharts-read-")
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  sessions_dir <- clone_data_repo(repo_url, pat, branch, dest = tmp_dir)
  if (is.null(sessions_dir)) return(default_analytics_data())

  bind_session_rds_files(sessions_dir)
}

#' Udtrak client metadata fra inputs
#'
#' @param inputs data.frame med alle inputs fra shinylogs
#' @return data.frame med client metadata
extract_client_metadata <- function(inputs) {
  if (nrow(inputs) == 0) return(data.frame())

  meta_inputs <- inputs[grepl("analytics_client_metadata", inputs$name, fixed = TRUE), ]
  if (nrow(meta_inputs) == 0) return(data.frame())

  parsed <- lapply(meta_inputs$value, function(v) {
    tryCatch(jsonlite::fromJSON(v), error = function(e) NULL)
  })
  parsed <- Filter(Negate(is.null), parsed)
  if (length(parsed) == 0) return(data.frame())

  dplyr::bind_rows(parsed)
}

#' Udtrak performance metrics fra inputs
#'
#' @param inputs data.frame med alle inputs fra shinylogs
#' @return data.frame med performance metrics
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
