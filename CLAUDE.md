# Claude Instructions — biSPCharts Analytics

## Project Overview

- **Project Type:** Quarto Dashboard
- **Purpose:** Visualisering af biSPCharts brugsstatistik fra shinylogs
- **Deploy:** Posit Connect Cloud, daglig scheduled rendering
- **Sprog:** Dansk

## Tech Stack

- Quarto (format: dashboard)
- bslib (layout, value boxes)
- pins (laes data fra Connect Cloud)
- ggplot2, dplyr, tidyr, lubridate, scales
- BFHtheme (hospital-branding)

## Data

Data laeser fra pin "spc-analytics-logs" via pins::pin_read().
Pin indeholder en liste med 4 data.frames: sessions, inputs, outputs, errors.

## Render

quarto render index.qmd
