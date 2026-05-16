# Tests for R/transform_funnel.R
# Koer: testthat::test_file("tests/testthat/test-transform_funnel.R")
# (forudsaetter at R/-filer er source'et via helper-setup.R)

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
  result <- build_wizard_funnel(facts, exclude_test_sessions = FALSE)
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
