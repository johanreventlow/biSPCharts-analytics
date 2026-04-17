# Tests for R/data_load.R
# Koer: testthat::test_file("tests/testthat/test-data_load.R")
# (forudsaetter at R/data_load.R og R/github_sync.R er source'et)

test_that("default_analytics_data() returnerer tomme data.frames", {
  result <- default_analytics_data()
  expect_true(is.list(result))
  expect_equal(sort(names(result)), c("errors", "inputs", "outputs", "sessions"))
  for (cat in c("sessions", "inputs", "outputs", "errors")) {
    expect_s3_class(result[[cat]], "data.frame")
    expect_equal(nrow(result[[cat]]), 0)
  }
})

test_that("load_analytics_data() returnerer default naar env vars mangler", {
  withr::with_envvar(
    c(GITHUB_PAT = "", PIN_REPO_URL = "", CONNECT_SERVER = ""),
    {
      result <- load_analytics_data()
      expect_equal(result, default_analytics_data())
    }
  )
})

test_that("bind_session_rds_files() bind'er flere rds-filer korrekt", {
  tmp_dir <- withr::local_tempdir()

  f1 <- list(
    sessions = data.frame(session = "a", duration = 10),
    inputs = data.frame(name = "x", value = "1"),
    outputs = data.frame(),
    errors = data.frame()
  )
  f2 <- list(
    sessions = data.frame(session = "b", duration = 20),
    inputs = data.frame(name = "y", value = "2"),
    outputs = data.frame(),
    errors = data.frame()
  )
  saveRDS(f1, file.path(tmp_dir, "20260417T100000Z_abc.rds"))
  saveRDS(f2, file.path(tmp_dir, "20260417T110000Z_def.rds"))

  result <- bind_session_rds_files(tmp_dir)

  expect_equal(nrow(result$sessions), 2)
  expect_equal(sort(result$sessions$session), c("a", "b"))
  expect_equal(nrow(result$inputs), 2)
  expect_equal(nrow(result$outputs), 0)
  expect_equal(nrow(result$errors), 0)
})

test_that("bind_session_rds_files() haandterer tom mappe", {
  tmp_dir <- withr::local_tempdir()
  result <- bind_session_rds_files(tmp_dir)
  expect_equal(result, default_analytics_data())
})

test_that("bind_session_rds_files() springer ugyldige filer over", {
  tmp_dir <- withr::local_tempdir()
  valid_data <- list(
    sessions = data.frame(session = "a"),
    inputs = data.frame(),
    outputs = data.frame(),
    errors = data.frame()
  )
  saveRDS(valid_data, file.path(tmp_dir, "20260417T100000Z_ok.rds"))
  # Ugyldig .rds-fil
  writeLines("not an rds file", file.path(tmp_dir, "20260417T110000Z_bad.rds"))

  result <- bind_session_rds_files(tmp_dir)
  # Kun den gyldige fil
  expect_equal(nrow(result$sessions), 1)
})

test_that("load_analytics_data() laeser fra aegte GitHub repo (integration)", {
  skip_if(
    nchar(Sys.getenv("GITHUB_PAT")) == 0 ||
      nchar(Sys.getenv("PIN_REPO_URL")) == 0,
    "GITHUB_PAT / PIN_REPO_URL ikke sat — springer integration over"
  )

  result <- load_analytics_data()
  expect_true(is.list(result))
  expect_equal(sort(names(result)), c("errors", "inputs", "outputs", "sessions"))
  # Smoke-test data fra write-side skal vaere til stede (mindst 1 session)
  expect_true(nrow(result$sessions) >= 1)
})
