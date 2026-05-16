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
