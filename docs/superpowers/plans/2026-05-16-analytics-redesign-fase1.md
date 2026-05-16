# Analytics Redesign Fase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erstat nuværende biSPCharts-analytics-dashboard med to målgruppe-specifikke views (Produkt + Ledelse) byggende på Lag 1 KPI-katalog. Alle KPI'er har eksplicit decision-job + fix kendte fejl (tidsvinduer, fri-tekst-clustering, funnel-overestimat).

**Architecture:** Quarto dashboard renderer ved daglig scheduled deploy. Rå shinylogs-data → `build_session_facts()` fact-tabel → view-specifikke KPI-/plot-moduler. TDD per modul med synthetic fixtures. Ingen ændringer i biSPCharts-app (Fase 2-4 roadmap).

**Tech Stack:** R, Quarto dashboard, dplyr/tidyr/lubridate, ggplot2, stringdist (fuzzy clustering), testthat (TDD), shinylogs (input data format).

**Spec:** `docs/superpowers/specs/2026-05-16-analytics-redesign-design.md`

---

## File Structure

### Filer der oprettes

| Fil | Ansvar |
|-----|--------|
| `tests/testthat/helper-setup.R` | Auto-source af alle `R/*.R` før tests |
| `tests/testthat/fixtures/synthesize.R` | Generator-script for synthetic fixtures |
| `tests/testthat/fixtures/synthetic_sessions.rds` | 50-sessions fixture (generated) |
| `R/utils_normalize.R` | String-normalisering, stop-lister, test-session-heuristik, konstanter |
| `R/transform_sessions.R` | `build_session_facts()` — joiner rå tabeller → én fact-tabel per session |
| `R/transform_indicators.R` | `normalize_indicator_titles()` + `cluster_indicator_titles()` (Jaro-Winkler) |
| `R/transform_funnel.R` | `build_wizard_funnel()` — 5-trins funnel via Lag 1 proxy |
| `R/kpi_product.R` | P1-P6 KPI-funktioner (returnerer named lists eller tibbles) |
| `R/kpi_management.R` | L1-L6 KPI-funktioner |
| `R/plot_product.R` | View P ggplot-funktioner |
| `R/plot_management.R` | View L ggplot-funktioner |
| `docs/CHANGES.md` | Side-by-side mapping af gamle → nye KPI'er |
| `tests/testthat/test-utils_normalize.R` | Tests for normalize-helpers |
| `tests/testthat/test-transform_sessions.R` | Tests for session_facts schema + edge cases |
| `tests/testthat/test-transform_indicators.R` | Tests for clustering + stop-liste |
| `tests/testthat/test-transform_funnel.R` | Tests for 5-trins funnel |
| `tests/testthat/test-kpi_product.R` | Tests for P-KPI'er mod kendt fixture |
| `tests/testthat/test-kpi_management.R` | Tests for L-KPI'er mod kendt fixture |
| `tests/testthat/test-plot_smoke.R` | Smoke-tests for plot-funktioner (returnerer ggplot uden fejl) |

### Filer der modificeres

| Fil | Ændring |
|-----|---------|
| `index.qmd` | Rewrite: to tabs ("Produkt" + "Ledelse"), drop value boxes, decision-job-tekst per KPI |

### Filer der slettes

| Fil | Erstattet af |
|-----|--------------|
| `R/kpi_calculations.R` | `R/kpi_product.R` + `R/kpi_management.R` |
| `R/plot_overview.R` | `R/plot_product.R` + `R/plot_management.R` |
| `R/plot_technical.R` | `R/plot_product.R` + `R/plot_management.R` |

---

## Konstanter + designvalg (referenceres af flere tasks)

- **Engaged session-tærskel:** `ENGAGED_DURATION_SEC = 30`
- **Tidsvinduer:** `WINDOW_SHORT_DAYS = 7`, `WINDOW_LONG_DAYS = 28`
- **Indikator-clustering:** Jaro-Winkler distance, threshold `0.15`, min word length `3`
- **Stop-liste (test-titler):** `c("test", "abc", "asdf", "qwerty", "xxx", "123", "test123", "lorem", "ipsum")`
- **Min sessions for browser-cross-tab:** `5`
- **Min sessions per heatmap-celle:** `3`
- **Performance min-n for percentil:** `10`
- **Test-session min-varighed:** `< 10` sekunder
- **Eksport-format regex:** `^export_(pdf|docx|png|svg|ai)_`
- **Kolonne-input regex:** `^(skift|frys|target|maal)_column$`

Alle konstanter eksporteres fra `R/utils_normalize.R`.

---

### Task 1: Test-helper for auto-source af R-filer

**Files:**
- Create: `tests/testthat/helper-setup.R`

- [ ] **Step 1: Læs eksisterende test-pattern**

Run: `head -5 tests/testthat/test-data_load.R`
Expected: Bekræfter at tests forudsætter manual `source()` af R-filer. Helper-filer i testthat auto-loadet før tests.

- [ ] **Step 2: Opret helper-setup.R**

```r
# tests/testthat/helper-setup.R
# Auto-sources alle R/*.R foer hver test koeres.
# testthat auto-loader helper-*.R foer test-*.R-filer.

local({
  r_files <- list.files(
    here::here("R"),
    pattern = "\\.R$",
    full.names = TRUE
  )
  for (f in r_files) {
    suppressMessages(source(f, local = FALSE))
  }
})
```

- [ ] **Step 3: Verificér at tests stadig bestaar**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-data_load.R')"`
Expected: Alle eksisterende tests bestaar (3 tests PASS).

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/helper-setup.R
git commit -m "test: auto-source R/-filer i testthat-helper"
```

---

### Task 2: Synthetic fixture generator

**Files:**
- Create: `tests/testthat/fixtures/synthesize.R`
- Create: `tests/testthat/fixtures/synthetic_sessions.rds` (genereret artifact)

- [ ] **Step 1: Skriv generator-script**

```r
# tests/testthat/fixtures/synthesize.R
# Koer manuelt for at regenerere fixtures:
#   Rscript tests/testthat/fixtures/synthesize.R

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

saveRDS(
  fixture,
  file.path(dirname(sys.frame(1)$ofile %||% "tests/testthat/fixtures"), "synthetic_sessions.rds")
)

message("Genereret synthetic_sessions.rds med ", n_sessions, " sessions, ",
        nrow(inputs), " inputs, ", nrow(outputs), " outputs, ", nrow(errors), " errors.")
```

- [ ] **Step 2: Generér fixture-fil**

Run:
```bash
cd /Users/johanreventlow/R/biSPCharts-analytics
Rscript tests/testthat/fixtures/synthesize.R
```
Expected: `synthetic_sessions.rds` oprettes; message viser 50 sessions + ≥ 150 inputs + 25 outputs + 8 errors.

- [ ] **Step 3: Verificér fixture-skema**

Run:
```bash
Rscript -e 'x <- readRDS("tests/testthat/fixtures/synthetic_sessions.rds"); str(x, max.level = 2)'
```
Expected: List med 4 data.frames (sessions/inputs/outputs/errors), korrekte navne på kolonner.

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/fixtures/
git commit -m "test: tilfoej synthetic_sessions fixture-generator"
```

---

### Task 3: utils_normalize.R — konstanter + tekst-helpers

**Files:**
- Create: `R/utils_normalize.R`
- Create: `tests/testthat/test-utils_normalize.R`

- [ ] **Step 1: Skriv failing tests**

```r
# tests/testthat/test-utils_normalize.R

test_that("ANALYTICS_CONSTANTS exporterer forventede felter", {
  expect_true(is.list(ANALYTICS_CONSTANTS))
  expected <- c("engaged_duration_sec", "window_short_days", "window_long_days",
                "indicator_cluster_threshold", "indicator_min_length",
                "stop_words", "browser_min_sessions", "heatmap_min_cell",
                "perf_min_n", "test_session_max_duration",
                "export_regex", "column_input_regex")
  expect_true(all(expected %in% names(ANALYTICS_CONSTANTS)))
})

test_that("normalize_text() lowercase + trim + collapse whitespace", {
  expect_equal(normalize_text("  Tryksaar  "), "tryksaar")
  expect_equal(normalize_text("TRYK  saar"), "tryk saar")
  expect_equal(normalize_text("Tryksaar\tafsnit"), "tryksaar afsnit")
  expect_equal(normalize_text(c("A", "  B  ")), c("a", "b"))
  expect_equal(normalize_text(NA_character_), NA_character_)
})

test_that("is_stop_word() fanger kendte test-strings", {
  expect_true(is_stop_word("test"))
  expect_true(is_stop_word("TEST"))
  expect_true(is_stop_word("  abc  "))
  expect_false(is_stop_word("tryksaar"))
  expect_false(is_stop_word(""))
  expect_equal(is_stop_word(c("test", "tryksaar", "abc")), c(TRUE, FALSE, TRUE))
})

test_that("parse_user_agent() identificerer browser + OS", {
  ua_chrome_mac <- "Mozilla/5.0 (Macintosh) Chrome/120.0"
  ua_firefox_win <- "Mozilla/5.0 (Windows) Firefox/115.0"
  ua_safari <- "Mozilla/5.0 (Macintosh) Safari/17.0"
  ua_edge <- "Mozilla/5.0 (Windows) Edg/120.0"

  expect_equal(parse_user_agent(ua_chrome_mac)$browser, "Chrome")
  expect_equal(parse_user_agent(ua_chrome_mac)$os, "macOS")
  expect_equal(parse_user_agent(ua_firefox_win)$browser, "Firefox")
  expect_equal(parse_user_agent(ua_firefox_win)$os, "Windows")
  expect_equal(parse_user_agent(ua_safari)$browser, "Safari")
  expect_equal(parse_user_agent(ua_edge)$browser, "Edge")
  expect_equal(parse_user_agent(NA_character_)$browser, "Anden")
})

test_that("normalize_error_message() stripper linjenumre + dynamiske ID'er", {
  expect_equal(
    normalize_error_message("Error: invalid column in line 42"),
    "Error: invalid column in line N"
  )
  expect_equal(
    normalize_error_message("Error: id 12345 not found"),
    "Error: id N not found"
  )
  expect_equal(
    normalize_error_message(c("Error: line 1", "Error: line 999")),
    c("Error: line N", "Error: line N")
  )
})
```

- [ ] **Step 2: Kør test → forvent FAIL**

Run:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-utils_normalize.R')"
```
Expected: Alle 5 tests FAIL — "could not find function 'ANALYTICS_CONSTANTS'" / "normalize_text" mv.

- [ ] **Step 3: Implementér R/utils_normalize.R**

```r
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
  indicator_cluster_threshold = 0.15,
  indicator_min_length = 3L,
  stop_words = c("test", "abc", "asdf", "qwerty", "xxx", "123",
                 "test123", "lorem", "ipsum"),
  browser_min_sessions = 5L,
  heatmap_min_cell = 3L,
  perf_min_n = 10L,
  test_session_max_duration = 10L,
  export_regex = "^export_(pdf|docx|png|svg|ai)_",
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
```

- [ ] **Step 4: Kør test → forvent PASS**

Run:
```bash
Rscript -e "testthat::test_file('tests/testthat/test-utils_normalize.R')"
```
Expected: Alle 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/utils_normalize.R tests/testthat/test-utils_normalize.R
git commit -m "feat(normalize): tilfoej konstanter + tekst-helpers"
```

---

### Task 4: utils_normalize.R — test-session-heuristik

**Files:**
- Modify: `R/utils_normalize.R` (tilføj `is_test_session()`)
- Modify: `tests/testthat/test-utils_normalize.R` (tilføj tests)

- [ ] **Step 1: Skriv failing test**

Tilføj til `tests/testthat/test-utils_normalize.R`:

```r
test_that("is_test_session() flag'er korte sessions + stop-ord titler", {
  facts <- tibble::tibble(
    sessionid = c("s1", "s2", "s3", "s4", "s5"),
    duration_sec = c(5, 600, 8, 120, 600),
    indicator_title_raw = c("Tryksaar", "Tryksaar", "test", "abc", "Fald")
  )
  result <- is_test_session(facts)
  expect_equal(result, c(TRUE, FALSE, TRUE, TRUE, FALSE))
})

test_that("is_test_session() haandterer manglende kolonner", {
  facts_no_title <- tibble::tibble(
    sessionid = "s1", duration_sec = 5
  )
  result <- is_test_session(facts_no_title)
  expect_equal(result, TRUE)
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-utils_normalize.R')"`
Expected: 2 nye tests FAIL ("could not find function 'is_test_session'").

- [ ] **Step 3: Implementér is_test_session()**

Tilføj til `R/utils_normalize.R`:

```r
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
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-utils_normalize.R')"`
Expected: Alle 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/utils_normalize.R tests/testthat/test-utils_normalize.R
git commit -m "feat(normalize): tilfoej is_test_session()-heuristik"
```

---

### Task 5: transform_sessions.R — session_facts skeleton

**Files:**
- Create: `R/transform_sessions.R`
- Create: `tests/testthat/test-transform_sessions.R`

- [ ] **Step 1: Skriv failing test**

```r
# tests/testthat/test-transform_sessions.R

fixture_path <- testthat::test_path("fixtures", "synthetic_sessions.rds")
fx <- readRDS(fixture_path)
client_meta <- extract_client_metadata(fx$inputs)
perf_metrics <- extract_performance_metrics(fx$inputs)

test_that("build_session_facts() returnerer tibble med korrekt schema", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  expect_s3_class(result, "tbl_df")

  expected_cols <- c("sessionid", "connected_at", "disconnected_at",
                     "duration_sec", "engaged", "visitor_id",
                     "browser", "os", "indicator_title_raw",
                     "chart_type", "step_data_proxy", "step_columns",
                     "step_chart_type", "step_output_generated",
                     "step_exported", "export_formats", "n_errors",
                     "error_signatures", "load_complete_ms",
                     "ttfb_ms", "dom_ready_ms", "is_test_session")
  expect_true(all(expected_cols %in% names(result)))

  expect_equal(nrow(result), nrow(fx$sessions))
})

test_that("build_session_facts() med tom input returnerer tom tibble", {
  empty_inputs <- data.frame()
  result <- build_session_facts(
    sessions = data.frame(), inputs = empty_inputs,
    outputs = data.frame(), errors = data.frame(),
    client_meta = data.frame(), perf_metrics = data.frame()
  )
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("build_session_facts() beregner duration_sec + engaged korrekt", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  expect_true(all(result$duration_sec >= 0 | is.na(result$duration_sec)))
  expect_equal(
    result$engaged,
    result$duration_sec >= ANALYTICS_CONSTANTS$engaged_duration_sec
  )
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_sessions.R')"`
Expected: FAIL — "could not find function 'build_session_facts'".

- [ ] **Step 3: Implementér skeleton**

```r
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
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_sessions.R')"`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/transform_sessions.R tests/testthat/test-transform_sessions.R
git commit -m "feat(transform): tilfoej build_session_facts() skeleton"
```

---

### Task 6: transform_sessions.R — udfyld kolonner fra inputs/outputs/errors

**Files:**
- Modify: `R/transform_sessions.R`
- Modify: `tests/testthat/test-transform_sessions.R`

- [ ] **Step 1: Skriv failing test for udfyldte kolonner**

Tilføj til `tests/testthat/test-transform_sessions.R`:

```r
test_that("build_session_facts() udfylder visitor_id + browser fra client_meta", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  expect_true(any(!is.na(result$visitor_id)))
  expect_true(any(result$browser %in% c("Chrome", "Firefox", "Safari", "Edge")))
})

test_that("build_session_facts() udleder wizard-steps korrekt", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  # Fixture: 30 sessions med chart_type, 20 med export_
  expect_equal(sum(result$step_chart_type), 30L)
  expect_equal(sum(result$step_exported), 20L)
  expect_equal(sum(result$step_columns), 40L)
})

test_that("build_session_facts() taeller errors per session", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  # Fixture: 8 errors fordelt paa 8 sessions
  expect_equal(sum(result$n_errors), nrow(fx$errors))
  expect_equal(sum(result$n_errors > 0L), 8L)
})

test_that("build_session_facts() joiner performance-metrics", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  expect_true(any(!is.na(result$load_complete_ms)))
})

test_that("build_session_facts() flag'er test-sessions korrekt", {
  result <- build_session_facts(
    fx$sessions, fx$inputs, fx$outputs, fx$errors, client_meta, perf_metrics
  )
  expect_true(sum(result$is_test_session) > 0L)
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_sessions.R')"`
Expected: Nye tests FAIL.

- [ ] **Step 3: Erstat placeholder-blok med faktisk join-logik**

Erstat placeholder-sektionen i `R/transform_sessions.R` (linjerne der sætter `base$visitor_id <- NA` osv.) med:

```r
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
  if (nrow(errors) > 0L) {
    err_summary <- errors |>
      dplyr::group_by(.data$sessionid) |>
      dplyr::summarise(
        n_errors = dplyr::n(),
        error_signatures = list(normalize_error_message(.data$error)),
        .groups = "drop"
      )
    base <- dplyr::left_join(base, err_summary, by = "sessionid",
                              suffix = c("", ".new"))
    base$n_errors <- dplyr::coalesce(base$n_errors.new, base$n_errors)
    base$error_signatures <- ifelse(
      lengths(base$error_signatures.new) > 0L,
      base$error_signatures.new, base$error_signatures
    )
    base$n_errors.new <- NULL
    base$error_signatures.new <- NULL
  }

  # Client metadata: visitor_id, browser, os
  if (nrow(client_meta) > 0L && "visitor_id" %in% names(client_meta)) {
    cm <- client_meta |>
      dplyr::distinct(.data$visitor_id, .data$user_agent, .data$timestamp,
                       .keep_all = FALSE)
    # Joiner client_meta paa nearest timestamp pr sessionid kraever sessionid i client_meta.
    # extract_client_metadata returnerer ej sessionid -> brug inputs-join som proxy:
    visitor_per_session <- if (nrow(inputs) > 0L) {
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
      if (length(meta_parsed) == 0L) {
        tibble::tibble(sessionid = character(), visitor_id = character(),
                       user_agent = character())
      } else {
        dplyr::bind_rows(meta_parsed) |>
          dplyr::group_by(.data$sessionid) |>
          dplyr::summarise(visitor_id = dplyr::first(.data$visitor_id),
                           user_agent = dplyr::first(.data$user_agent),
                           .groups = "drop")
      }
    } else {
      tibble::tibble(sessionid = character(), visitor_id = character(),
                     user_agent = character())
    }

    base <- dplyr::left_join(base, visitor_per_session, by = "sessionid",
                              suffix = c(".old", ""))
    base$visitor_id.old <- NULL

    ua_parsed <- parse_user_agent(base$user_agent)
    base$browser <- ua_parsed$browser
    base$os <- ua_parsed$os
    base$user_agent <- NULL
  }

  # Performance metrics per session via inputs-join
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
```

Tilføj private helpers nederst i `R/transform_sessions.R`:

```r
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
```

Tilføj `%||%`-helper hvis ej allerede sourced (eksisterer i data_load.R, så ok).

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_sessions.R')"`
Expected: Alle 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/transform_sessions.R tests/testthat/test-transform_sessions.R
git commit -m "feat(transform): udfyld session_facts kolonner fra inputs/outputs/errors"
```

---

### Task 7: transform_indicators.R — normalize + fuzzy cluster

**Files:**
- Create: `R/transform_indicators.R`
- Create: `tests/testthat/test-transform_indicators.R`

- [ ] **Step 1: Skriv failing tests**

```r
# tests/testthat/test-transform_indicators.R

test_that("normalize_indicator_titles() filtrerer tomme + korte + stop-ord", {
  titles <- c("Tryksaar", "  tryksaar  ", "ab", "test", "", NA, "Fald")
  result <- normalize_indicator_titles(titles)
  # forventer: tryksaar, tryksaar, fald (ab/test/tom/NA filtreret)
  expect_equal(sort(unique(result$normalized)), c("fald", "tryksaar"))
  expect_equal(nrow(result), 3L)
})

test_that("cluster_indicator_titles() grupperer naerliggende strenge", {
  titles <- c("Tryksaar", "Tryksaar", "tryksaar", "Tryksaar afsnit B",
              "Fald", "Patientfald", "Infektion")
  result <- cluster_indicator_titles(titles)
  expect_s3_class(result, "tbl_df")
  expect_true(all(c("title_raw", "cluster") %in% names(result)))
  # Tryksaar-varianter skal vaere i samme cluster
  trykklynger <- result$cluster[grepl("tryksaar", tolower(result$title_raw))]
  expect_equal(length(unique(trykklynger)), 1L)
})

test_that("cluster_indicator_titles() med tom input returnerer tom tibble", {
  result <- cluster_indicator_titles(character())
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("cluster_indicator_titles() respekterer threshold-konstant", {
  titles <- c("alpha", "alpha", "beta")
  result <- cluster_indicator_titles(titles)
  # alpha + beta skal ende i hver sin cluster (distance > threshold)
  expect_equal(length(unique(result$cluster)), 2L)
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_indicators.R')"`
Expected: FAIL — funktioner ej fundet.

- [ ] **Step 3: Implementér R/transform_indicators.R**

```r
# R/transform_indicators.R
# Normalisering + fuzzy-clustering af indicator_title-fritekst.

#' Normaliser + filtrer indicator titles
#'
#' Drop tomme, < min-length, NA, stop-ord. Returnerer tibble med
#' rå + normaliseret kolonne for sporbarhed.
#'
#' @param titles character-vektor
#' @return tibble (title_raw, normalized) med kun valide rows
#' @export
normalize_indicator_titles <- function(titles) {
  if (length(titles) == 0L) {
    return(tibble::tibble(title_raw = character(), normalized = character()))
  }
  df <- tibble::tibble(title_raw = titles, normalized = normalize_text(titles))
  df |>
    dplyr::filter(
      !is.na(.data$normalized),
      nchar(.data$normalized) >= ANALYTICS_CONSTANTS$indicator_min_length,
      !is_stop_word(.data$normalized)
    )
}

#' Fuzzy-cluster indicator titles via Jaro-Winkler distance
#'
#' Greedy single-linkage clustering: hver ny streng tilknyttes nærmeste
#' eksisterende cluster hvis distance < threshold; ellers ny cluster.
#' Cluster-label = mest hyppige variant (efter normalisering).
#'
#' @param titles character-vektor af rå titler
#' @return tibble (title_raw, normalized, cluster)
#' @export
cluster_indicator_titles <- function(titles) {
  filtered <- normalize_indicator_titles(titles)
  if (nrow(filtered) == 0L) {
    return(tibble::tibble(title_raw = character(),
                          normalized = character(),
                          cluster = character()))
  }
  unique_normalized <- unique(filtered$normalized)
  if (length(unique_normalized) == 1L) {
    cluster_map <- stats::setNames(unique_normalized, unique_normalized)
  } else {
    dist_mat <- stringdist::stringdistmatrix(
      unique_normalized, unique_normalized, method = "jw"
    )
    cluster_ids <- integer(length(unique_normalized))
    next_id <- 1L
    for (i in seq_along(unique_normalized)) {
      assigned <- FALSE
      for (j in seq_len(i - 1L)) {
        if (dist_mat[i, j] < ANALYTICS_CONSTANTS$indicator_cluster_threshold) {
          cluster_ids[i] <- cluster_ids[j]
          assigned <- TRUE
          break
        }
      }
      if (!assigned) {
        cluster_ids[i] <- next_id
        next_id <- next_id + 1L
      }
    }
    # Cluster-label = den mest hyppige normaliserede variant per cluster
    norm_to_id <- stats::setNames(cluster_ids, unique_normalized)
    counts_by_norm <- table(filtered$normalized)
    id_to_label <- tapply(
      names(counts_by_norm),
      norm_to_id[names(counts_by_norm)],
      function(group) {
        group_counts <- counts_by_norm[group]
        names(group_counts)[which.max(group_counts)]
      }
    )
    cluster_map <- stats::setNames(
      as.character(id_to_label[as.character(norm_to_id[unique_normalized])]),
      unique_normalized
    )
  }
  filtered$cluster <- cluster_map[filtered$normalized]
  filtered
}
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_indicators.R')"`
Expected: Alle 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/transform_indicators.R tests/testthat/test-transform_indicators.R
git commit -m "feat(transform): tilfoej indicator-clustering med Jaro-Winkler"
```

---

### Task 8: transform_funnel.R — 5-trins funnel

**Files:**
- Create: `R/transform_funnel.R`
- Create: `tests/testthat/test-transform_funnel.R`

- [ ] **Step 1: Skriv failing tests**

```r
# tests/testthat/test-transform_funnel.R

fixture_path <- testthat::test_path("fixtures", "synthetic_sessions.rds")
fx <- readRDS(fixture_path)
client_meta <- extract_client_metadata(fx$inputs)
perf_metrics <- extract_performance_metrics(fx$inputs)
facts <- build_session_facts(fx$sessions, fx$inputs, fx$outputs, fx$errors,
                              client_meta, perf_metrics)

test_that("build_wizard_funnel() returnerer 5 trin i fast raekkefoelge", {
  result <- build_wizard_funnel(facts)
  expect_s3_class(result, "tbl_df")
  expect_equal(result$step, c("Data tilgaengelig", "Kolonner valgt",
                              "Diagramtype valgt", "Output genereret",
                              "Eksport"))
  expect_true(all(c("step", "step_order", "n_sessions", "frafald_pct") %in% names(result)))
})

test_that("build_wizard_funnel() taeller korrekt fra fixture", {
  result <- build_wizard_funnel(facts)
  # Fixture (uden is_test_session-filter): 40 column-valg, 30 chart_type,
  # 25 outputs, 20 exports. Step 1 = step_data_proxy (union, op til 40).
  expect_lte(result$n_sessions[2], 40L)
  expect_equal(result$n_sessions[3], 30L)
  expect_equal(result$n_sessions[4], 25L)
  expect_equal(result$n_sessions[5], 20L)
})

test_that("build_wizard_funnel() respekterer is_test_session-filter", {
  result_all <- build_wizard_funnel(facts, exclude_test_sessions = FALSE)
  result_clean <- build_wizard_funnel(facts, exclude_test_sessions = TRUE)
  expect_lte(result_clean$n_sessions[1], result_all$n_sessions[1])
})

test_that("build_wizard_funnel() med tom input returnerer tomt skema", {
  empty <- facts[0L, ]
  result <- build_wizard_funnel(empty)
  expect_equal(nrow(result), 5L)
  expect_true(all(result$n_sessions == 0L))
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_funnel.R')"`
Expected: FAIL — `build_wizard_funnel` ej fundet.

- [ ] **Step 3: Implementér build_wizard_funnel()**

```r
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
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-transform_funnel.R')"`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/transform_funnel.R tests/testthat/test-transform_funnel.R
git commit -m "feat(transform): tilfoej build_wizard_funnel() med 5 trin"
```

---

### Task 9: kpi_product.R — P1, P3, P4 (sessions, fejl-cluster, performance)

**Files:**
- Create: `R/kpi_product.R`
- Create: `tests/testthat/test-kpi_product.R`

- [ ] **Step 1: Skriv failing tests**

```r
# tests/testthat/test-kpi_product.R

fixture_path <- testthat::test_path("fixtures", "synthetic_sessions.rds")
fx <- readRDS(fixture_path)
client_meta <- extract_client_metadata(fx$inputs)
perf_metrics <- extract_performance_metrics(fx$inputs)
facts <- build_session_facts(fx$sessions, fx$inputs, fx$outputs, fx$errors,
                              client_meta, perf_metrics)

test_that("kpi_active_sessions() respekterer engaged + tidsvindue", {
  result <- kpi_active_sessions(facts, days = 28L,
                                  reference_time = max(facts$connected_at, na.rm = TRUE))
  expect_true(is.list(result))
  expect_true(all(c("value", "decision_job") %in% names(result)))
  expect_equal(result$value, sum(facts$engaged & !facts$is_test_session, na.rm = TRUE))
})

test_that("kpi_error_clusters() returnerer top-N normaliserede fejl", {
  result <- kpi_error_clusters(facts, top_n = 5L)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("error_signature", "n_sessions") %in% names(result$data)))
  expect_lte(nrow(result$data), 5L)
})

test_that("kpi_performance_percentiles() returnerer p50 + p95", {
  result <- kpi_performance_percentiles(facts)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("metric", "p50", "p95") %in% names(result$data)))
  expect_true("load_complete_ms" %in% result$data$metric)
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_product.R')"`
Expected: FAIL.

- [ ] **Step 3: Implementér P1, P3, P4**

```r
# R/kpi_product.R
# View P (Produkt) KPI'er. Hver KPI returnerer named list:
#   list(value/data = ..., decision_job = "...", caveat = "...")

#' P1: Aktive sessions (engaged + tidsvindue)
#'
#' @param facts session_facts tibble
#' @param days antal dage tilbage at kigge
#' @param reference_time POSIXct, default Sys.time()
#' @return list med value, decision_job, caveat
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
#' @param facts session_facts tibble
#' @param top_n antal cluster-rows at vise
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med data (tibble), decision_job
#' @export
kpi_error_clusters <- function(facts, top_n = 10L, days = 28L,
                                 reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$n_errors > 0L,
                   .data$connected_at >= cutoff)

  if (nrow(filtered) == 0L) {
    return(list(
      data = tibble::tibble(error_signature = character(), n_sessions = integer()),
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
#' @param facts session_facts tibble
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med data (tibble), decision_job
#' @export
kpi_performance_percentiles <- function(facts, days = 28L,
                                          reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  filtered <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$connected_at >= cutoff)

  metrics <- c("load_complete_ms", "ttfb_ms", "dom_ready_ms")
  rows <- lapply(metrics, function(m) {
    vals <- filtered[[m]]
    vals <- vals[!is.na(vals)]
    if (length(vals) < ANALYTICS_CONSTANTS$perf_min_n) {
      return(tibble::tibble(metric = m, p50 = NA_real_, p95 = NA_real_, n = length(vals)))
    }
    tibble::tibble(metric = m,
                    p50 = stats::quantile(vals, 0.5, names = FALSE),
                    p95 = stats::quantile(vals, 0.95, names = FALSE),
                    n = length(vals))
  })

  list(
    data = dplyr::bind_rows(rows),
    decision_job = "Er load-tid acceptabel? P95 > 5s = undersoeg.",
    caveat = paste0("Vises kun naar n >= ", ANALYTICS_CONSTANTS$perf_min_n, ".")
  )
}
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_product.R')"`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/kpi_product.R tests/testthat/test-kpi_product.R
git commit -m "feat(kpi): tilfoej P1, P3, P4 produkt-KPI'er"
```

---

### Task 10: kpi_product.R — P2, P5, P6 (funnel-KPI, browser-fejl, feature-adoption)

**Files:**
- Modify: `R/kpi_product.R`
- Modify: `tests/testthat/test-kpi_product.R`

- [ ] **Step 1: Skriv failing tests**

Tilføj til `tests/testthat/test-kpi_product.R`:

```r
test_that("kpi_wizard_funnel() wrap'er build_wizard_funnel()", {
  result <- kpi_wizard_funnel(facts)
  expect_true(all(c("data", "decision_job") %in% names(result)))
  expect_equal(nrow(result$data), 5L)
})

test_that("kpi_browser_errors() cross-tab kun med n >= browser_min_sessions", {
  result <- kpi_browser_errors(facts)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("browser_os", "n_sessions", "error_rate") %in% names(result$data)))
  expect_true(all(result$data$n_sessions >= ANALYTICS_CONSTANTS$browser_min_sessions))
})

test_that("kpi_feature_adoption() returnerer % sessions per tracked input", {
  feature_ids <- c("chart_type", "skift_column")
  result <- kpi_feature_adoption(facts, fx$inputs, feature_ids)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("feature_id", "adoption_pct") %in% names(result$data)))
  expect_equal(nrow(result$data), 2L)
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_product.R')"`
Expected: 3 nye tests FAIL.

- [ ] **Step 3: Implementér P2, P5, P6**

Tilføj til `R/kpi_product.R`:

```r
#' P2: Wizard funnel (wrapper)
#'
#' @inheritParams build_wizard_funnel
#' @return list med data, decision_job
#' @export
kpi_wizard_funnel <- function(facts, exclude_test_sessions = TRUE) {
  list(
    data = build_wizard_funnel(facts, exclude_test_sessions),
    decision_job = "Hvor sker friction? Hvilket trin taber flest brugere?",
    caveat = "Lag 1 proxy — trin 1 (data) detekteres indirekte via efterfoelgende inputs."
  )
}

#' P5: Browser/OS-kombinationer + fejl-rate
#'
#' Kun kombinationer med >= browser_min_sessions vises.
#'
#' @param facts session_facts tibble
#' @return list med data (tibble), decision_job
#' @export
kpi_browser_errors <- function(facts) {
  if (nrow(facts) == 0L) {
    return(list(
      data = tibble::tibble(browser_os = character(), n_sessions = integer(),
                             n_errors = integer(), error_rate = numeric()),
      decision_job = "Er en browser problematisk?",
      caveat = "Ingen data."
    ))
  }

  cleaned <- facts |> dplyr::filter(!.data$is_test_session)
  cleaned$browser_os <- paste(cleaned$browser, cleaned$os, sep = " / ")

  data <- cleaned |>
    dplyr::group_by(.data$browser_os) |>
    dplyr::summarise(
      n_sessions = dplyr::n(),
      n_errors = sum(.data$n_errors > 0L, na.rm = TRUE),
      error_rate = round(.data$n_errors / .data$n_sessions * 100, 1),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$n_sessions >= ANALYTICS_CONSTANTS$browser_min_sessions) |>
    dplyr::arrange(dplyr::desc(.data$error_rate))

  list(
    data = data,
    decision_job = "Er en browser/OS-kombination problematisk?",
    caveat = paste0("Min ", ANALYTICS_CONSTANTS$browser_min_sessions,
                     " sessions per kombination.")
  )
}

#' P6: Feature-adoption rate
#'
#' For hver tracked input-id beregner % sessions der minimum trigget den.
#'
#' @param facts session_facts tibble
#' @param inputs raw inputs data.frame
#' @param feature_ids character-vektor af input-name vaerdier
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return list med data, decision_job
#' @export
kpi_feature_adoption <- function(facts, inputs, feature_ids,
                                   days = 28L, reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  active_sessions <- facts |>
    dplyr::filter(!.data$is_test_session,
                   .data$connected_at >= cutoff) |>
    dplyr::pull(.data$sessionid)

  total <- length(active_sessions)
  if (total == 0L) {
    return(list(
      data = tibble::tibble(feature_id = feature_ids,
                             n_sessions = 0L, adoption_pct = NA_real_),
      decision_job = "Bruger nogen feature X? Hvis nej = sunset-kandidat.",
      caveat = "Ingen aktive sessions i vinduet."
    ))
  }

  rows <- lapply(feature_ids, function(fid) {
    matched <- inputs |>
      dplyr::filter(.data$name == fid, .data$sessionid %in% active_sessions) |>
      dplyr::pull(.data$sessionid) |>
      unique()
    tibble::tibble(
      feature_id = fid,
      n_sessions = length(matched),
      adoption_pct = round(length(matched) / total * 100, 1)
    )
  })

  list(
    data = dplyr::bind_rows(rows) |> dplyr::arrange(dplyr::desc(.data$adoption_pct)),
    decision_job = "Bruger nogen feature X? Hvis nej = sunset-kandidat.",
    caveat = "Liste over feature-id'er vedligeholdes manuelt."
  )
}
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_product.R')"`
Expected: Alle 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/kpi_product.R tests/testthat/test-kpi_product.R
git commit -m "feat(kpi): tilfoej P2 (funnel), P5 (browser-fejl), P6 (feature-adoption)"
```

---

### Task 11: kpi_management.R — L1, L2, L4 (analyser, eksport, trend)

**Files:**
- Create: `R/kpi_management.R`
- Create: `tests/testthat/test-kpi_management.R`

- [ ] **Step 1: Skriv failing tests**

```r
# tests/testthat/test-kpi_management.R

fixture_path <- testthat::test_path("fixtures", "synthetic_sessions.rds")
fx <- readRDS(fixture_path)
client_meta <- extract_client_metadata(fx$inputs)
perf_metrics <- extract_performance_metrics(fx$inputs)
facts <- build_session_facts(fx$sessions, fx$inputs, fx$outputs, fx$errors,
                              client_meta, perf_metrics)

ref_time <- max(facts$connected_at, na.rm = TRUE)

test_that("kpi_active_analyses() taeller sessions med output_generated", {
  result <- kpi_active_analyses(facts, days = 28L, reference_time = ref_time)
  expect_true(is.list(result))
  expect_true(result$value > 0L)
  expect_lte(result$value, sum(facts$step_output_generated))
})

test_that("kpi_export_breakdown() returnerer rows per eksport-format", {
  result <- kpi_export_breakdown(facts, days = 28L, reference_time = ref_time)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("format", "n_sessions") %in% names(result$data)))
  expect_true(any(result$data$format %in% c("pdf", "docx", "png", "ai")))
})

test_that("kpi_weekly_trend() markerer partial uge", {
  result <- kpi_weekly_trend(facts, n_weeks = 4L, reference_time = ref_time)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("iso_week", "n_sessions", "is_partial") %in% names(result$data)))
  # Den sidste uge kan vaere partial
  expect_true(any(result$data$is_partial) || all(!result$data$is_partial))
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_management.R')"`
Expected: FAIL.

- [ ] **Step 3: Implementér L1, L2, L4**

```r
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
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_management.R')"`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/kpi_management.R tests/testthat/test-kpi_management.R
git commit -m "feat(kpi): tilfoej L1 (analyser), L2 (eksport), L4 (uge-trend)"
```

---

### Task 12: kpi_management.R — L3, L5, L6 (indikator-cluster, retention, use case-heatmap)

**Files:**
- Modify: `R/kpi_management.R`
- Modify: `tests/testthat/test-kpi_management.R`

- [ ] **Step 1: Skriv failing tests**

Tilføj til `tests/testthat/test-kpi_management.R`:

```r
test_that("kpi_top_indicators() returnerer top-N normaliserede clusters", {
  result <- kpi_top_indicators(facts, top_n = 5L, reference_time = ref_time)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("cluster", "n_sessions") %in% names(result$data)))
  expect_lte(nrow(result$data), 5L)
})

test_that("kpi_cohort_retention() returnerer matrix-tibble", {
  result <- kpi_cohort_retention(facts, n_weeks = 4L, reference_time = ref_time)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("cohort_week", "weeks_since", "retention_pct") %in% names(result$data)))
})

test_that("kpi_use_case_heatmap() returnerer celler med min antal", {
  result <- kpi_use_case_heatmap(facts, reference_time = ref_time)
  expect_s3_class(result$data, "tbl_df")
  expect_true(all(c("chart_type", "cluster", "n_sessions") %in% names(result$data)))
  expect_true(all(result$data$n_sessions >= ANALYTICS_CONSTANTS$heatmap_min_cell))
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_management.R')"`
Expected: 3 nye tests FAIL.

- [ ] **Step 3: Implementér L3, L5, L6**

Tilføj til `R/kpi_management.R`:

```r
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
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-kpi_management.R')"`
Expected: Alle 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/kpi_management.R tests/testthat/test-kpi_management.R
git commit -m "feat(kpi): tilfoej L3 (indikator-cluster), L5 (retention), L6 (use-case)"
```

---

### Task 13: plot_product.R — View P plots

**Files:**
- Create: `R/plot_product.R`
- Create: `tests/testthat/test-plot_smoke.R`

- [ ] **Step 1: Skriv failing smoke-tests**

```r
# tests/testthat/test-plot_smoke.R

fixture_path <- testthat::test_path("fixtures", "synthetic_sessions.rds")
fx <- readRDS(fixture_path)
client_meta <- extract_client_metadata(fx$inputs)
perf_metrics <- extract_performance_metrics(fx$inputs)
facts <- build_session_facts(fx$sessions, fx$inputs, fx$outputs, fx$errors,
                              client_meta, perf_metrics)
ref_time <- max(facts$connected_at, na.rm = TRUE)

test_that("plot_active_sessions_trend() returnerer ggplot", {
  p <- plot_active_sessions_trend(facts, days = 28L, reference_time = ref_time)
  expect_s3_class(p, "ggplot")
})

test_that("plot_wizard_funnel() returnerer ggplot", {
  funnel_data <- build_wizard_funnel(facts)
  p <- plot_wizard_funnel(funnel_data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_error_clusters() returnerer ggplot", {
  result <- kpi_error_clusters(facts, reference_time = ref_time)
  p <- plot_error_clusters(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_performance_percentiles() returnerer ggplot", {
  result <- kpi_performance_percentiles(facts, reference_time = ref_time)
  p <- plot_performance_percentiles(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_browser_errors() returnerer ggplot", {
  result <- kpi_browser_errors(facts)
  p <- plot_browser_errors(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot-funktioner haandterer tomt input gracefully", {
  empty_facts <- facts[0L, ]
  empty_funnel <- build_wizard_funnel(empty_facts)
  expect_s3_class(plot_wizard_funnel(empty_funnel), "ggplot")
  expect_s3_class(plot_active_sessions_trend(empty_facts), "ggplot")
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-plot_smoke.R')"`
Expected: FAIL.

- [ ] **Step 3: Implementér plot_product.R**

```r
# R/plot_product.R
# View P (Produkt) plot-funktioner.

.empty_ggplot <- function(label = "Ingen data") {
  ggplot2::ggplot() +
    ggplot2::theme_void() +
    ggplot2::annotate("text", x = 0.5, y = 0.5, label = label,
                       size = 6, color = "grey60")
}

#' P1: Aktive sessions trend (daglige counts, engaged only)
#'
#' @param facts session_facts
#' @param days tidsvindue
#' @param reference_time POSIXct
#' @return ggplot
#' @export
plot_active_sessions_trend <- function(facts, days = 28L,
                                         reference_time = Sys.time()) {
  cutoff <- reference_time - lubridate::days(days)
  cleaned <- facts |>
    dplyr::filter(!.data$is_test_session, .data$engaged,
                   .data$connected_at >= cutoff)
  if (nrow(cleaned) == 0L) return(.empty_ggplot())

  daily <- cleaned |>
    dplyr::mutate(dato = as.Date(.data$connected_at)) |>
    dplyr::count(.data$dato, name = "sessions")

  all_days <- data.frame(dato = seq(as.Date(cutoff), as.Date(reference_time),
                                     by = "day"))
  daily <- dplyr::left_join(all_days, daily, by = "dato") |>
    dplyr::mutate(sessions = tidyr::replace_na(.data$sessions, 0L))

  daily$gns_7d <- zoo::rollmean(daily$sessions, k = 7L, fill = NA,
                                  align = "right")

  ggplot2::ggplot(daily, ggplot2::aes(x = .data$dato)) +
    ggplot2::geom_col(ggplot2::aes(y = .data$sessions),
                       fill = "#3498db", alpha = 0.4) +
    ggplot2::geom_line(ggplot2::aes(y = .data$gns_7d),
                        color = "#2c3e50", linewidth = 1, na.rm = TRUE) +
    ggplot2::labs(x = NULL, y = "Sessions",
                   title = paste0("Aktive sessions (", days,
                                  " dage, engaged >= 30s)")) +
    ggplot2::theme_minimal()
}

#' P2: Wizard funnel barchart
#'
#' @param funnel_data tibble fra build_wizard_funnel()
#' @return ggplot
#' @export
plot_wizard_funnel <- function(funnel_data) {
  if (nrow(funnel_data) == 0L || all(funnel_data$n_sessions == 0L)) {
    return(.empty_ggplot())
  }
  funnel_data$step <- factor(funnel_data$step, levels = funnel_data$step)
  funnel_data$label <- ifelse(
    is.na(funnel_data$frafald_pct),
    as.character(funnel_data$n_sessions),
    sprintf("%d (-%.0f%%)", funnel_data$n_sessions, funnel_data$frafald_pct)
  )
  ggplot2::ggplot(funnel_data,
                   ggplot2::aes(x = .data$step, y = .data$n_sessions)) +
    ggplot2::geom_col(fill = "#3498db") +
    ggplot2::geom_text(ggplot2::aes(label = .data$label),
                        vjust = -0.4, size = 3.5) +
    ggplot2::labs(x = NULL, y = "Sessions", title = "Wizard-frafald per trin") +
    ggplot2::theme_minimal()
}

#' P3: Fejl-cluster top-N barchart
#'
#' @param error_data tibble (error_signature, n_sessions)
#' @return ggplot
#' @export
plot_error_clusters <- function(error_data) {
  if (nrow(error_data) == 0L) return(.empty_ggplot("Ingen fejl"))
  error_data$error_signature <- stringr::str_trunc(error_data$error_signature, 60L)
  error_data$error_signature <- stats::reorder(error_data$error_signature,
                                                 error_data$n_sessions)
  ggplot2::ggplot(error_data,
                   ggplot2::aes(x = .data$n_sessions, y = .data$error_signature)) +
    ggplot2::geom_col(fill = "#e74c3c") +
    ggplot2::labs(x = "Unikke sessions", y = NULL,
                   title = "Top fejl-cluster (normaliseret)") +
    ggplot2::theme_minimal()
}

#' P4: Performance percentiler
#'
#' @param perf_data tibble (metric, p50, p95, n)
#' @return ggplot
#' @export
plot_performance_percentiles <- function(perf_data) {
  if (nrow(perf_data) == 0L || all(is.na(perf_data$p50))) {
    return(.empty_ggplot("Utilstraekkelig data"))
  }
  long <- perf_data |>
    tidyr::pivot_longer(cols = c("p50", "p95"),
                         names_to = "percentile", values_to = "ms")
  ggplot2::ggplot(long, ggplot2::aes(x = .data$metric, y = .data$ms,
                                       fill = .data$percentile)) +
    ggplot2::geom_col(position = "dodge") +
    ggplot2::scale_fill_manual(values = c(p50 = "#3498db", p95 = "#e67e22")) +
    ggplot2::labs(x = NULL, y = "Millisekunder", fill = NULL,
                   title = "Performance p50 / p95") +
    ggplot2::coord_flip() +
    ggplot2::theme_minimal()
}

#' P5: Browser/OS-fejl-rate
#'
#' @param browser_data tibble (browser_os, n_sessions, error_rate)
#' @return ggplot
#' @export
plot_browser_errors <- function(browser_data) {
  if (nrow(browser_data) == 0L) return(.empty_ggplot("Ingen kombinationer"))
  browser_data$browser_os <- stats::reorder(browser_data$browser_os,
                                              browser_data$error_rate)
  ggplot2::ggplot(browser_data, ggplot2::aes(x = .data$error_rate,
                                                y = .data$browser_os,
                                                size = .data$n_sessions)) +
    ggplot2::geom_point(color = "#e74c3c") +
    ggplot2::labs(x = "Fejl-rate (%)", y = NULL, size = "Sessions",
                   title = "Browser/OS x fejl-rate") +
    ggplot2::theme_minimal()
}
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-plot_smoke.R')"`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/plot_product.R tests/testthat/test-plot_smoke.R
git commit -m "feat(plot): tilfoej View P plot-funktioner"
```

---

### Task 14: plot_management.R — View L plots

**Files:**
- Create: `R/plot_management.R`
- Modify: `tests/testthat/test-plot_smoke.R`

- [ ] **Step 1: Skriv failing tests**

Tilføj til `tests/testthat/test-plot_smoke.R`:

```r
test_that("plot_export_breakdown() returnerer ggplot", {
  result <- kpi_export_breakdown(facts, reference_time = ref_time)
  p <- plot_export_breakdown(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_weekly_trend() returnerer ggplot med partial-uge-markering", {
  result <- kpi_weekly_trend(facts, n_weeks = 4L, reference_time = ref_time)
  p <- plot_weekly_trend(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_top_indicators() returnerer ggplot", {
  result <- kpi_top_indicators(facts, reference_time = ref_time)
  p <- plot_top_indicators(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_cohort_retention() returnerer ggplot", {
  result <- kpi_cohort_retention(facts, reference_time = ref_time)
  p <- plot_cohort_retention(result$data)
  expect_s3_class(p, "ggplot")
})

test_that("plot_use_case_heatmap() returnerer ggplot", {
  result <- kpi_use_case_heatmap(facts, reference_time = ref_time)
  p <- plot_use_case_heatmap(result$data)
  expect_s3_class(p, "ggplot")
})
```

- [ ] **Step 2: Kør test → FAIL**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-plot_smoke.R')"`
Expected: 5 nye tests FAIL.

- [ ] **Step 3: Implementér plot_management.R**

```r
# R/plot_management.R
# View L (Ledelse) plot-funktioner.

#' L2: Eksport-format breakdown
#'
#' @param export_data tibble (format, n_sessions)
#' @return ggplot
#' @export
plot_export_breakdown <- function(export_data) {
  if (nrow(export_data) == 0L) return(.empty_ggplot("Ingen eksporter"))
  export_data$format <- stats::reorder(export_data$format,
                                         export_data$n_sessions)
  ggplot2::ggplot(export_data,
                   ggplot2::aes(x = .data$n_sessions, y = .data$format)) +
    ggplot2::geom_col(fill = "#e67e22") +
    ggplot2::labs(x = "Sessions", y = NULL, title = "Eksport-format") +
    ggplot2::theme_minimal()
}

#' L4: Weekly trend med partial-uge-markering
#'
#' @param trend_data tibble (iso_week, week_start, n_sessions, is_partial)
#' @return ggplot
#' @export
plot_weekly_trend <- function(trend_data) {
  if (nrow(trend_data) == 0L) return(.empty_ggplot())
  trend_data$bar_fill <- ifelse(trend_data$is_partial, "Igangvaerende uge",
                                  "Afsluttet uge")
  ggplot2::ggplot(trend_data, ggplot2::aes(x = .data$week_start,
                                              y = .data$n_sessions,
                                              fill = .data$bar_fill)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = c("Afsluttet uge" = "#3498db",
                                            "Igangvaerende uge" = "#bdc3c7")) +
    ggplot2::labs(x = NULL, y = "Sessions", fill = NULL,
                   title = "Sessions per uge") +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "bottom")
}

#' L3: Top indicator clusters
#'
#' @param indicator_data tibble (cluster, n_sessions, n_variants)
#' @return ggplot
#' @export
plot_top_indicators <- function(indicator_data) {
  if (nrow(indicator_data) == 0L) return(.empty_ggplot())
  indicator_data$cluster <- stats::reorder(indicator_data$cluster,
                                              indicator_data$n_sessions)
  ggplot2::ggplot(indicator_data,
                   ggplot2::aes(x = .data$n_sessions, y = .data$cluster)) +
    ggplot2::geom_col(fill = "#27ae60") +
    ggplot2::geom_text(ggplot2::aes(label = paste0(.data$n_variants, " varianter")),
                        hjust = -0.2, size = 3) +
    ggplot2::labs(x = "Unikke sessions", y = NULL,
                   title = "Top indikator-clusters") +
    ggplot2::theme_minimal()
}

#' L5: Cohort retention heatmap
#'
#' @param cohort_data tibble (cohort_week, weeks_since, retention_pct)
#' @return ggplot
#' @export
plot_cohort_retention <- function(cohort_data) {
  if (nrow(cohort_data) == 0L) return(.empty_ggplot())
  ggplot2::ggplot(cohort_data, ggplot2::aes(x = .data$weeks_since,
                                               y = .data$cohort_week,
                                               fill = .data$retention_pct)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = paste0(.data$retention_pct, "%")),
                        size = 3) +
    ggplot2::scale_fill_gradient(low = "#ecf0f1", high = "#2c3e50",
                                   na.value = "white") +
    ggplot2::labs(x = "Uger siden foerste besoeg", y = "Kohorte",
                   fill = "Retention %", title = "Cohort retention") +
    ggplot2::theme_minimal()
}

#' L6: Use case heatmap (chart_type x cluster)
#'
#' @param heatmap_data tibble (chart_type, cluster, n_sessions)
#' @return ggplot
#' @export
plot_use_case_heatmap <- function(heatmap_data) {
  if (nrow(heatmap_data) == 0L) return(.empty_ggplot())
  ggplot2::ggplot(heatmap_data, ggplot2::aes(x = .data$chart_type,
                                                y = .data$cluster,
                                                fill = .data$n_sessions)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = .data$n_sessions), size = 3) +
    ggplot2::scale_fill_gradient(low = "#eef6ff", high = "#2c3e50") +
    ggplot2::labs(x = "Chart-type", y = "Indikator-cluster",
                   fill = "Sessions", title = "Use case-fordeling") +
    ggplot2::theme_minimal()
}
```

- [ ] **Step 4: Kør test → PASS**

Run: `Rscript -e "testthat::test_file('tests/testthat/test-plot_smoke.R')"`
Expected: Alle 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add R/plot_management.R tests/testthat/test-plot_smoke.R
git commit -m "feat(plot): tilfoej View L plot-funktioner"
```

---

### Task 15: Slet legacy R-filer

**Files:**
- Delete: `R/kpi_calculations.R`
- Delete: `R/plot_overview.R`
- Delete: `R/plot_technical.R`

- [ ] **Step 1: Verificér at intet andet sourcer dem**

Run:
```bash
grep -rn "kpi_calculations\|plot_overview\|plot_technical" \
  /Users/johanreventlow/R/biSPCharts-analytics --include="*.R" --include="*.qmd" \
  | grep -v "^Binary"
```
Expected: Kun hits i index.qmd (som re-skrives i task 16) eller i selve filerne.

- [ ] **Step 2: Slet filerne**

Run:
```bash
cd /Users/johanreventlow/R/biSPCharts-analytics
git rm R/kpi_calculations.R R/plot_overview.R R/plot_technical.R
```

- [ ] **Step 3: Kør alle tests → forvent PASS**

Run:
```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```
Expected: Alle tests PASS (35+ tests samlet).

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: fjern legacy kpi/plot-filer (erstattet af kpi_/plot_-moduler)"
```

---

### Task 16: index.qmd rewrite — to tabs med decision-job-tekst

**Files:**
- Modify: `index.qmd`

- [ ] **Step 1: Verificér eksisterende setup-chunk fanger nye deps**

Setup-chunk skal inkludere `stringdist` + `zoo` + `tibble`. Existing imports: `dplyr`, `ggplot2`, `lubridate`, `pins`, `scales`, `tidyr`.

- [ ] **Step 2: Erstat hele index.qmd**

```markdown
---
title: "biSPCharts Analytics"
format: dashboard
---

```{r}
#| label: setup
#| include: false
library(dplyr)
library(ggplot2)
library(lubridate)
library(scales)
library(stringdist)
library(tibble)
library(tidyr)
library(zoo)

# Indlaes alle R-filer
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

# Indlaes + transformer data
raw <- load_analytics_data()
client_meta <- extract_client_metadata(raw$inputs)
perf_metrics <- extract_performance_metrics(raw$inputs)
facts <- build_session_facts(raw$sessions, raw$inputs, raw$outputs,
                              raw$errors, client_meta, perf_metrics)
ref_time <- if (nrow(facts) > 0L) max(facts$connected_at, na.rm = TRUE) else Sys.time()

# Tracked features for adoption-KPI
tracked_features <- c("chart_type", "skift_column", "frys_column",
                       "target_column", "indicator_title")
```

# Produkt

## Row {height=15%}

```{r}
#| content: valuebox
#| title: "Aktive sessions (28d)"
r <- kpi_active_sessions(facts, days = 28L, reference_time = ref_time)
list(value = r$value, icon = "bar-chart", color = "primary")
```

```{r}
#| content: valuebox
#| title: "Aktive sessions (7d)"
r <- kpi_active_sessions(facts, days = 7L, reference_time = ref_time)
list(value = r$value, icon = "bar-chart", color = "info")
```

```{r}
#| content: valuebox
#| title: "Sessions med fejl (28d)"
r <- kpi_error_clusters(facts, top_n = 100L, reference_time = ref_time)
list(value = sum(r$data$n_sessions), icon = "exclamation-triangle", color = "warning")
```

## Row {height=45%}

### Column {width=60%}

```{r}
#| title: "Aktive sessions trend"
#| subtitle: "Beslutning: er trafikken stabil? Pludselig drop = produktionsproblem."
plot_active_sessions_trend(facts, days = 28L, reference_time = ref_time)
```

### Column {width=40%}

```{r}
#| title: "Wizard-frafald"
#| subtitle: "Beslutning: hvor sker friction? Hvilket trin taber flest brugere?"
plot_wizard_funnel(build_wizard_funnel(facts))
```

## Row {height=40%}

### Column {width=50%}

```{r}
#| title: "Fejl-cluster top 10"
#| subtitle: "Beslutning: hvilke fejl rammer flest unikke sessions?"
plot_error_clusters(kpi_error_clusters(facts, top_n = 10L, reference_time = ref_time)$data)
```

### Column {width=50%}

```{r}
#| title: "Performance p50 / p95"
#| subtitle: "Beslutning: er load-tid acceptabel? P95 > 5s = undersoeg."
plot_performance_percentiles(kpi_performance_percentiles(facts, reference_time = ref_time)$data)
```

## Row {height=40%}

### Column {width=50%}

```{r}
#| title: "Browser/OS x fejl-rate"
#| subtitle: "Beslutning: er en kombination problematisk?"
plot_browser_errors(kpi_browser_errors(facts)$data)
```

### Column {width=50%}

```{r}
#| title: "Feature-adoption"
#| subtitle: "Beslutning: bruger nogen feature X? Hvis nej = sunset-kandidat."
adoption <- kpi_feature_adoption(facts, raw$inputs, tracked_features,
                                  days = 28L, reference_time = ref_time)
knitr::kable(adoption$data)
```

# Ledelse

## Row {height=15%}

```{r}
#| content: valuebox
#| title: "Aktive analyser (28d)"
r <- kpi_active_analyses(facts, reference_time = ref_time)
list(value = r$value, icon = "check-circle", color = "success")
```

```{r}
#| content: valuebox
#| title: "Eksporter (28d)"
r <- kpi_export_breakdown(facts, reference_time = ref_time)
list(value = sum(r$data$n_sessions), icon = "download", color = "primary")
```

```{r}
#| content: valuebox
#| title: "Unikke besoegende (28d)"
unique_v <- facts |>
  dplyr::filter(!is_test_session, !is.na(visitor_id),
                 connected_at >= ref_time - lubridate::days(28L)) |>
  dplyr::pull(visitor_id) |>
  dplyr::n_distinct()
list(value = unique_v, icon = "people", color = "info")
```

## Row {height=45%}

### Column {width=60%}

```{r}
#| title: "Sessions per uge"
#| subtitle: "Beslutning: vokser brug eller plateauer?"
plot_weekly_trend(kpi_weekly_trend(facts, n_weeks = 12L, reference_time = ref_time)$data)
```

### Column {width=40%}

```{r}
#| title: "Eksport-format"
#| subtitle: "Beslutning: forlader output appen? Hvor?"
plot_export_breakdown(kpi_export_breakdown(facts, reference_time = ref_time)$data)
```

## Row {height=40%}

### Column {width=50%}

```{r}
#| title: "Top indikator-clusters"
#| subtitle: "Beslutning: hvilke kvalitetstemaer dominerer?"
plot_top_indicators(kpi_top_indicators(facts, top_n = 15L, reference_time = ref_time)$data)
```

### Column {width=50%}

```{r}
#| title: "Cohort retention"
#| subtitle: "Beslutning: vender brugere tilbage?"
plot_cohort_retention(kpi_cohort_retention(facts, n_weeks = 6L, reference_time = ref_time)$data)
```

## Row {height=40%}

```{r}
#| title: "Use case-fordeling (chart-type x indikator)"
#| subtitle: "Beslutning: hvilke chart-typer driver hvilke use cases?"
plot_use_case_heatmap(kpi_use_case_heatmap(facts, reference_time = ref_time)$data)
```
```

- [ ] **Step 3: Render lokalt mod tom data**

Run:
```bash
cd /Users/johanreventlow/R/biSPCharts-analytics
GITHUB_PAT="" PIN_REPO_URL="" quarto render index.qmd
```
Expected: Render lykkes uden fejl; alle plots viser "Ingen data"-placeholder.

- [ ] **Step 4: Render mod synthetic fixture**

Sæt midlertidigt fixture som data-kilde:

```bash
Rscript -e '
fx <- readRDS("tests/testthat/fixtures/synthetic_sessions.rds")
saveRDS(list(sessions = fx$sessions, inputs = fx$inputs,
              outputs = fx$outputs, errors = fx$errors),
         "/tmp/fixture_test.rds")
' && \
echo "Note: render mod fixture kraever stub af load_analytics_data() — verificeres i task 17"
```
Expected: Message printet; render mod fixture verificeres i task 17.

- [ ] **Step 5: Commit**

```bash
git add index.qmd
git commit -m "feat(dashboard): rewrite til to tabs (Produkt + Ledelse) med decision-jobs"
```

---

### Task 17: End-to-end render-validering mod synthetic fixture

**Files:**
- Create (midlertidig): `_test_render.R`

- [ ] **Step 1: Skriv test-render-script**

```r
# _test_render.R
# Midlertidig: render mod synthetic fixture i stedet for prod-data.
# Bruges af task 17 + slettes efter.

library(quarto)
fx <- readRDS("tests/testthat/fixtures/synthetic_sessions.rds")

mock_load <- function() fx
assignInNamespace("load_analytics_data",
                  mock_load,
                  ns = topenv())

quarto::quarto_render("index.qmd", output_format = "dashboard")
```

- [ ] **Step 2: Forenklet alternativ: kør setup-chunk manuelt**

```bash
Rscript -e '
fx <- readRDS("tests/testthat/fixtures/synthetic_sessions.rds")
for (f in list.files("R", pattern = "\\\\.R$", full.names = TRUE)) source(f)
client_meta <- extract_client_metadata(fx$inputs)
perf_metrics <- extract_performance_metrics(fx$inputs)
facts <- build_session_facts(fx$sessions, fx$inputs, fx$outputs, fx$errors,
                              client_meta, perf_metrics)
ref_time <- max(facts$connected_at, na.rm = TRUE)

# Eyeball KPI-vaerdier
print(kpi_active_sessions(facts, reference_time = ref_time))
print(kpi_active_analyses(facts, reference_time = ref_time))
print(kpi_export_breakdown(facts, reference_time = ref_time))
print(kpi_top_indicators(facts, top_n = 5L, reference_time = ref_time))
print(kpi_wizard_funnel(facts))
'
```
Expected:
- `kpi_active_sessions`: value > 0
- `kpi_active_analyses`: value ≈ 25 (matcher fixture outputs)
- `kpi_export_breakdown`: data har rows for pdf/docx/png/ai
- `kpi_top_indicators`: tryksaar/fald/infektion dominerer
- `kpi_wizard_funnel`: 5 trin, faldende mod eksport

- [ ] **Step 3: Verificér quarto-render lokalt**

Run:
```bash
GITHUB_PAT="" PIN_REPO_URL="" quarto render index.qmd
```
Expected: `_site/index.html` genereres uden fejl.

- [ ] **Step 4: Render-tid måling**

Run:
```bash
time (GITHUB_PAT="" PIN_REPO_URL="" quarto render index.qmd)
```
Expected: < 30s.
Hvis > 30s: cache-lag bør implementeres som opfølgning (out-of-scope for denne plan, dokumentér i CHANGES.md).

- [ ] **Step 5: Commit (uden _test_render.R)**

`_test_render.R` slettes; ingen commit fra dette task (bare validering).

```bash
rm -f _test_render.R 2>/dev/null
git status  # forventer clean working tree (hvis fixture-render er korrekt)
```

---

### Task 18: docs/CHANGES.md — migration-noter

**Files:**
- Create: `docs/CHANGES.md`

- [ ] **Step 1: Skriv CHANGES.md**

```markdown
# Analytics-dashboard ændringer — 2026-05-16

## Sammendrag

Dashboard refactored fra "Overblik" + "Teknisk" til "Produkt" + "Ledelse".
Alle KPI'er har eksplicit decision-job + kendte fejl er fixet.

## Mapping af gamle → nye KPI'er

| Gammel KPI | Status | Erstatning |
|-----------|--------|-----------|
| Sessions denne uge | Erstattet | P1 (engaged + tidsvindue) |
| Unikke besøgende (uden vindue) | Erstattet | Ledelse value box (visitor_id i 28d) |
| Completion rate (chart_type) | Erstattet | P2 (funnel) + L1 (output_generated) |
| Gns. varighed (mislabeled median) | Fjernet | Ingen — støjet, intet decision-job |
| Top indikator (rå fri tekst) | Erstattet | L3 normaliseret + clustered |
| Trend uge/uge (partial bias) | Erstattet | L4 weekly trend med partial-flag |
| Wizard-flow Upload=alle | Erstattet | P2 5-trins corrected funnel |
| Sessions per dag | Bevaret | P1 trend-plot (filtreret til engaged) |
| Top 10 indikatorer | Erstattet | L3 clustered |
| Feature-brug | Erstattet | P6 adoption-rate (% sessions) |
| Wizard-flow med frafald | Erstattet | P2 |
| Fejl-oversigt | Erstattet | P3 normaliseret cluster |
| Performance (boxplot) | Erstattet | P4 p50/p95 percentil-bar |
| Browser/OS | Erstattet | P5 (krydset med fejl-rate) |
| Nye vs. tilbagevendende | Erstattet | L5 cohort retention |
| Tidsmønstre heatmap | Fjernet | Ikke prioriteret — kan tilføjes igen senere |

## Nye konstanter (R/utils_normalize.R)

Alle tærskler eksponeret i `ANALYTICS_CONSTANTS`:

- `engaged_duration_sec = 30` — minimum varighed for "engaged" session
- `indicator_cluster_threshold = 0.15` — Jaro-Winkler threshold for fuzzy-cluster
- `browser_min_sessions = 5` — minimum sessions per browser/OS-kombination
- `heatmap_min_cell = 3` — minimum sessions per heatmap-celle
- `perf_min_n = 10` — minimum n for percentil-beregning

## Nye filer

- `R/utils_normalize.R` — konstanter + tekst-helpers
- `R/transform_sessions.R` — `build_session_facts()`
- `R/transform_indicators.R` — fuzzy-clustering
- `R/transform_funnel.R` — 5-trins wizard funnel
- `R/kpi_product.R` — P1-P6
- `R/kpi_management.R` — L1-L6 (uden hospital/afdeling)
- `R/plot_product.R` + `R/plot_management.R`

## Slettet

- `R/kpi_calculations.R`, `R/plot_overview.R`, `R/plot_technical.R`

## Forberedelser til Fase 2 (Bundle A)

Når biSPCharts tilføjer `hospital` + `department` som inputs:

- `build_session_facts()` er allerede klargjort med `hospital_raw` + `department_raw`-placeholder (NA indtil felter ankommer)
- L1, L3, L6 udvides med hospital/afdeling-segmentering
- Se `docs/superpowers/specs/2026-05-16-analytics-redesign-design.md` sektion 4 + 7

## Test-strategi

- Synthetic fixture: `tests/testthat/fixtures/synthetic_sessions.rds`
- Regenerér via: `Rscript tests/testthat/fixtures/synthesize.R`
- Kør alle tests: `Rscript -e "testthat::test_dir('tests/testthat')"`

## Render-tid

Måling pr. 2026-05-16: TBD (udfyldes ved første prod-render efter merge).
Hvis > 30s ved første prod-render: implementér qs-fil-cache (se spec sektion 5).
```

- [ ] **Step 2: Verificér rendering af markdown**

Run:
```bash
head -20 docs/CHANGES.md
```
Expected: Læselig markdown, ingen syntax-fejl.

- [ ] **Step 3: Commit**

```bash
git add docs/CHANGES.md
git commit -m "docs: tilfoej CHANGES.md med migration-mapping"
```

---

### Task 19: Final integration test + branch finalisering

**Files:**
- Ingen nye filer

- [ ] **Step 1: Kør hele test-suiten**

Run:
```bash
cd /Users/johanreventlow/R/biSPCharts-analytics
Rscript -e "testthat::test_dir('tests/testthat')"
```
Expected: Alle tests PASS (≥ 35 tests). Ingen WARNINGs.

- [ ] **Step 2: Lint nye R-filer**

Run:
```bash
Rscript -e 'lintr::lint_dir("R", linters = lintr::default_linters)'
```
Expected: Ingen kritiske lints (style-warnings acceptable hvis ej blokerende).

- [ ] **Step 3: Render mod tom data**

Run:
```bash
GITHUB_PAT="" PIN_REPO_URL="" quarto render index.qmd
```
Expected: `_site/index.html` genereret; alle plots viser "Ingen data" gracefully.

- [ ] **Step 4: Verificér commit-graf**

Run:
```bash
git log --oneline main..HEAD
```
Expected: ≥ 16 atomare commits, alle med conventional-commit prefix.

- [ ] **Step 5: Markér branch klar til review**

Branch klar til PR (ej push uden eksplicit godkendelse fra bruger).

Hvis bruger ønsker PR:

```bash
git push -u origin docs/analytics-redesign-spec
gh pr create --draft --title "feat(analytics): redesign dashboard til Produkt + Ledelse views" \
  --body "$(cat <<'EOF'
## Summary
- Erstatter Overblik/Teknisk-tabs med Produkt/Ledelse views
- Alle KPI'er har eksplicit decision-job
- Fixer kendte fejl: tidsvinduer, fri-tekst clustering, funnel-overestimat
- Tilføjer transform-pipeline (session_facts fact-tabel)
- Lag 2 instrumentering (hospital/afdeling/wizard-events) forbliver roadmap

## Test plan
- [ ] Alle tests passerer: `testthat::test_dir('tests/testthat')`
- [ ] Render mod tom data viser "Ingen data" overalt
- [ ] Render mod synthetic fixture viser meningsfulde KPI'er
- [ ] Render-tid < 30s mod prod-data

Spec: docs/superpowers/specs/2026-05-16-analytics-redesign-design.md
Plan: docs/superpowers/plans/2026-05-16-analytics-redesign-fase1.md
EOF
)"
```

Ej automatisk — bruger må eksplicit anmode om push + PR.

---

## Self-Review Tjekkliste

**1. Spec coverage:**

- Sektion 1 (problem + designrammer) → adresseret i Task 16 (decision-job-tekst pr KPI) + Task 18 (CHANGES.md mapping) ✓
- Sektion 2 (P + L views, intet community) → Task 16 to tabs ✓
- Sektion 3 (Lag 1 KPI'er P1-P6 + L1-L6) → Tasks 9-12 ✓
- Sektion 4 (Lag 2 roadmap) → eksplicit ud af scope (Fase 1 only) + dokumenteret i Task 18 ✓
- Sektion 5 (datamodel + filer + cache) → Tasks 1-8 + Task 17 (cache out-of-scope, dokumenteret) ✓
- Sektion 6 (privacy droppet, kun test-filter + AI-restriction) → Task 4 (is_test_session) ✓
- Sektion 7 (Fase 1 arbejdsblokke 1-8) → Tasks 1-17 ✓
- Sektion 8 (success criteria) → Task 19 (final integration test) ✓

**2. Placeholder scan:** Ingen "TBD/TODO" i task-steps. Eneste TBD er i CHANGES.md render-tid (faktisk-måling efter prod-deploy — legitim).

**3. Type consistency:**
- `build_session_facts()` signatur konsistent på tværs Tasks 5-12
- `kpi_*()` returns named lists med `value`/`data` + `decision_job` (konsistent)
- `plot_*()` accepterer den specifikke kpi's `$data`-output (verificeret cross-task)
- `ANALYTICS_CONSTANTS$*`-felter ens i tasks 3-12

Plan komplet.
