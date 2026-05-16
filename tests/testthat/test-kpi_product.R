# Tests for R/kpi_product.R
# Koer: testthat::test_file("tests/testthat/test-kpi_product.R")
# (forudsaetter at R/-filer er source'et via helper-setup.R)

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
