# tests/testthat/helper-setup.R
# Auto-sources alle R/*.R foer hver test koeres.
# testthat auto-loader helper-*.R foer test-*.R-filer.

local({
  r_files <- list.files(
    here::here("R"),
    pattern = "\\.R$",
    full.names = TRUE
  )
  for (f in r_files) {
    suppressMessages(source(f, local = FALSE))
  }
})
