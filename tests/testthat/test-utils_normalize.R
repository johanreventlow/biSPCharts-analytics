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
