# Claude Instructions — biSPCharts Analytics

## Project Overview

- **Project Type:** Quarto Dashboard
- **Purpose:** Visualisering af biSPCharts brugsstatistik fra shinylogs
- **Deploy:** Posit Connect Cloud, daglig scheduled rendering
- **Sprog:** Dansk

## Tech Stack

- Quarto (format: dashboard)
- bslib (layout, value boxes)
- gert (clone privat data-repo fra GitHub)
- ggplot2, dplyr, tidyr, lubridate, scales
- BFHtheme (hospital-branding)

## Data-pipeline

Appen laeser analytics-data fra privat GitHub repo
**`johanreventlow/bispcharts-analytics-data`** (append-model).

Flow:
1. biSPCharts Shiny-app skriver én `.rds`-fil per session til `sessions/`
   (filnavn: `<YYYYMMDDTHHMMSSZ>_<session-prefix>.rds`).
2. Denne app kloner repo'et ved render og binder alle `.rds`-filer sammen
   via `dplyr::bind_rows()` per kategori (sessions, inputs, outputs, errors).

Se `R/data_load.R` og `R/github_sync.R`.

### Kraevede env vars (Connect Cloud per-content Variables)

| Variabel | Vaerdi |
|----------|--------|
| `GITHUB_PAT` | Fine-grained PAT med `contents:read` paa data-repo |
| `PIN_REPO_URL` | `https://github.com/johanreventlow/bispcharts-analytics-data.git` |
| `PIN_REPO_BRANCH` | Valgfri (default: `main`) |

### Lokal udvikling

Kopier `.Renviron.example` til `.Renviron` og udfyld PAT.

## Render

```bash
quarto render index.qmd
```

## Tests

```r
# Fra projekt-rod
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
testthat::test_file("tests/testthat/test-data_load.R")
```
