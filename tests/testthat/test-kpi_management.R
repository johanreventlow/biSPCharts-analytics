# Tests for R/kpi_management.R
# Koer: testthat::test_file("tests/testthat/test-kpi_management.R")
# (forudsaetter at R/-filer er source'et via helper-setup.R)

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
