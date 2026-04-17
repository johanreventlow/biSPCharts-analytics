# R/github_sync.R
# Clone og laes analytics-data fra privat GitHub repo.

#' Indsaet PAT i HTTPS git-URL for autentificering
#'
#' @param url HTTPS git URL
#' @param pat GitHub Personal Access Token
#' @return URL med indlejret PAT
inject_pat_into_url <- function(url, pat) {
  if (!startsWith(url, "https://")) {
    stop("PIN_REPO_URL skal vaere HTTPS (fandt: ", url, ")", call. = FALSE)
  }
  sub("^https://", paste0("https://x-access-token:", pat, "@"), url)
}

#' Clone data-repo til midlertidig mappe
#'
#' Returnerer sti til sessions/ mappen i clonen. Cleanup skal
#' haandteres af kalder (on.exit unlink(parent_dir)).
#'
#' @return Sti til sessions-mappe, eller NULL ved fejl
clone_data_repo <- function(repo_url, pat, branch = "main", dest = NULL) {
  if (is.null(dest)) dest <- tempfile("bispcharts-read-")

  if (!requireNamespace("gert", quietly = TRUE)) {
    message("gert-pakken er ikke installeret — kan ikke clone repo")
    return(NULL)
  }

  auth_url <- inject_pat_into_url(repo_url, pat)
  tryCatch({
    gert::git_clone(
      url = auth_url,
      path = dest,
      branch = branch,
      verbose = FALSE
    )
    file.path(dest, "sessions")
  }, error = function(e) {
    message(paste("Clone fejlede:", conditionMessage(e)))
    NULL
  })
}
