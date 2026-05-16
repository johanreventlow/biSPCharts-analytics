# tests/testthat/fixtures/synthesize.R
# Koer manuelt for at regenerere fixtures:
#   Rscript tests/testthat/fixtures/synthesize.R

# Lokal `%||%`-fallback saa scriptet kan koeres standalone (uden at
# source R/data_load.R). `R/data_load.R` definerer det samme operator,
# men det er ikke garanteret tilgaengeligt under Rscript.
`%||%` <- function(x, y) if (is.null(x)) y else x

# Robust resolution af scriptets egen mappe — virker baade i interaktiv
# session (`sys.frame(1)$ofile`) og under Rscript (`--file=`-argument).
resolve_script_dir <- function() {
  # 1) Interactive `source()` saetter sys.frame(1)$ofile.
  ofile <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(ofile)) {
    return(dirname(normalizePath(ofile)))
  }
  # 2) Rscript saetter --file=<path> i commandArgs(trailingOnly = FALSE).
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
  if (length(file_arg) > 0L && nzchar(file_arg[[1L]])) {
    return(dirname(normalizePath(file_arg[[1L]])))
  }
  # 3) Fallback: forventet sti relativ til projekt-rod.
  normalizePath("tests/testthat/fixtures", mustWork = FALSE)
}

script_dir <- resolve_script_dir()

set.seed(42L)

n_sessions <- 50L
sessionids <- paste0("sess_", sprintf("%04d", seq_len(n_sessions)))
start_time <- as.POSIXct("2026-04-01 08:00:00", tz = "UTC")

# Sessions: blandet engaged (>30s) + drive-by (<30s) + test (<10s)
durations_sec <- c(
  runif(20, 45, 600),     # engaged real
  runif(15, 5, 25),       # drive-by
  runif(10, 2, 8),        # test
  runif(5, 1800, 7200)    # lang-tab (outliers)
)

connected <- start_time + sort(sample(0:(28L * 86400L), n_sessions))
disconnected <- connected + durations_sec

sessions <- data.frame(
  sessionid = sessionids,
  app = "biSPCharts",
  user = NA_character_,
  server_connected = format(connected, "%Y-%m-%dT%H:%M:%SZ"),
  server_disconnected = format(disconnected, "%Y-%m-%dT%H:%M:%SZ"),
  stringsAsFactors = FALSE
)

# Inputs: forskellige niveauer af wizard-progress
# - 40 sessions har kolonne-valg
# - 30 sessions har chart_type
# - 20 sessions har export_*

mk_input <- function(sid, ts, name, value, type = "character") {
  data.frame(sessionid = sid, timestamp = ts, name = name,
             value = value, type = type, binding = "shiny", stringsAsFactors = FALSE)
}

inputs_list <- list()

# Indicator titles med kendte clusters
title_pool <- c(
  rep("Tryksaar", 8), rep("tryksaar", 4), "Tryksaar afsnit B",
  rep("Fald", 6), rep("Patientfald", 3),
  rep("Infektion", 5), "Sygehusinfektion",
  rep("Medicineringsfejl", 4),
  "test", "abc", "qwerty",
  rep("VAP", 3),
  "Liggetid"
)

for (i in seq_len(40L)) {
  sid <- sessionids[i]
  ts <- format(connected[i] + runif(1, 5, 30), "%Y-%m-%dT%H:%M:%SZ")
  inputs_list[[length(inputs_list) + 1L]] <- mk_input(
    sid, ts, "indicator_title", title_pool[(i %% length(title_pool)) + 1L]
  )
  inputs_list[[length(inputs_list) + 1L]] <- mk_input(
    sid, ts, "skift_column", "Tid"
  )
}

chart_types <- c("run", "i", "p", "u", "g")
for (i in seq_len(30L)) {
  sid <- sessionids[i]
  ts <- format(connected[i] + runif(1, 30, 60), "%Y-%m-%dT%H:%M:%SZ")
  inputs_list[[length(inputs_list) + 1L]] <- mk_input(
    sid, ts, "chart_type", chart_types[(i %% length(chart_types)) + 1L]
  )
}

export_formats <- c("pdf", "docx", "png", "ai")
for (i in seq_len(20L)) {
  sid <- sessionids[i]
  ts <- format(connected[i] + runif(1, 60, 120), "%Y-%m-%dT%H:%M:%SZ")
  fmt <- export_formats[(i %% length(export_formats)) + 1L]
  inputs_list[[length(inputs_list) + 1L]] <- mk_input(
    sid, ts, paste0("export_", fmt, "_click"), "TRUE", "logical"
  )
}

# Client metadata (visitor_id, user_agent) som JSON-string
visitor_pool <- c(rep("v_001", 12), rep("v_002", 8), rep("v_003", 5),
                  paste0("v_", sprintf("%03d", 4:30)))
ua_pool <- c(
  "Mozilla/5.0 (Macintosh) Chrome/120.0",
  "Mozilla/5.0 (Windows) Firefox/115.0",
  "Mozilla/5.0 (Macintosh) Safari/17.0",
  "Mozilla/5.0 (Windows) Edg/120.0"
)
for (i in seq_len(n_sessions)) {
  meta <- list(
    visitor_id = visitor_pool[(i %% length(visitor_pool)) + 1L],
    user_agent = ua_pool[(i %% length(ua_pool)) + 1L],
    timestamp = format(connected[i], "%Y-%m-%dT%H:%M:%SZ")
  )
  inputs_list[[length(inputs_list) + 1L]] <- mk_input(
    sessionids[i],
    format(connected[i], "%Y-%m-%dT%H:%M:%SZ"),
    "analytics_client_metadata",
    jsonlite::toJSON(meta, auto_unbox = TRUE)
  )
}

# Performance metrics
for (i in seq_len(n_sessions)) {
  perf <- list(
    type = "page_load",
    load_complete_ms = round(runif(1, 200, 4000)),
    dom_ready_ms = round(runif(1, 100, 2000)),
    ttfb_ms = round(runif(1, 50, 800))
  )
  inputs_list[[length(inputs_list) + 1L]] <- mk_input(
    sessionids[i],
    format(connected[i], "%Y-%m-%dT%H:%M:%SZ"),
    "analytics_performance",
    jsonlite::toJSON(perf, auto_unbox = TRUE)
  )
}

inputs <- do.call(rbind, inputs_list)

# Outputs: SPC-plots for 25 sessions
output_sessions <- sessionids[seq_len(25L)]
outputs <- data.frame(
  sessionid = output_sessions,
  timestamp = format(connected[seq_len(25L)] + 90, "%Y-%m-%dT%H:%M:%SZ"),
  name = "spc_plot",
  binding = "plotOutput",
  type = "plot",
  stringsAsFactors = FALSE
)

# Errors: 8 sessions
error_sessions <- sessionids[c(3, 7, 12, 18, 22, 31, 37, 44)]
error_msgs <- c(
  "Error: invalid column in line 42",
  "Error: invalid column in line 87",
  "Error: connection timeout",
  "Error: invalid column in line 15",
  "Error: division by zero",
  "Error: connection timeout",
  "Error: division by zero",
  "Error: NA values in target column"
)
errors <- data.frame(
  sessionid = error_sessions,
  timestamp = format(connected[c(3, 7, 12, 18, 22, 31, 37, 44)] + 60, "%Y-%m-%dT%H:%M:%SZ"),
  error = error_msgs,
  binding = "renderPlot",
  type = "error",
  stringsAsFactors = FALSE
)

fixture <- list(sessions = sessions, inputs = inputs, outputs = outputs, errors = errors)

out_path <- file.path(script_dir, "synthetic_sessions.rds")
saveRDS(fixture, out_path)

message("Genereret ", out_path, " med ", n_sessions, " sessions, ",
        nrow(inputs), " inputs, ", nrow(outputs), " outputs, ", nrow(errors), " errors.")
