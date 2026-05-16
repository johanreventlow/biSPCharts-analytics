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
