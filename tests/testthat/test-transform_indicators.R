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
