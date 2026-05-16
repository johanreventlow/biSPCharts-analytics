# R/transform_indicators.R
# Normalisering + fuzzy-clustering af indicator_title-fritekst.

#' Normaliser + filtrer indicator titles
#'
#' Drop tomme, < min-length, NA, stop-ord. Returnerer tibble med
#' raa + normaliseret kolonne for sporbarhed.
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
#' Greedy single-linkage clustering: hver ny streng tilknyttes naermeste
#' eksisterende cluster hvis distance < threshold; ellers ny cluster.
#' Cluster-label = mest hyppige variant (efter normalisering).
#'
#' @param titles character-vektor af raa titler
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
