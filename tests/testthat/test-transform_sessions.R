# Tests for R/transform_sessions.R
# Koer: testthat::test_file("tests/testthat/test-transform_sessions.R")
# (forudsaetter at R/-filer er source'et via helper-setup.R)

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
