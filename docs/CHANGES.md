# Analytics-dashboard ændringer — 2026-05-17

## Sammendrag

Dashboard refactored fra "Overblik" + "Teknisk" til "Produkt" + "Ledelse".
Alle KPI'er har eksplicit decision-job + kendte fejl er fixet.

## Mapping af gamle → nye KPI'er

| Gammel KPI | Status | Erstatning |
|-----------|--------|-----------|
| Sessions denne uge | Erstattet | P1 (engaged + tidsvindue) |
| Unikke besøgende (uden vindue) | Erstattet | Ledelse value box (visitor_id i 28d) |
| Completion rate (chart_type) | Erstattet | P2 (funnel) + L1 (output_generated) |
| Gns. varighed (mislabeled median) | Fjernet | Ingen — støjet, intet decision-job |
| Top indikator (rå fri tekst) | Erstattet | L3 normaliseret + clustered |
| Trend uge/uge (partial bias) | Erstattet | L4 weekly trend med partial-flag |
| Wizard-flow Upload=alle | Erstattet | P2 5-trins corrected funnel |
| Sessions per dag | Bevaret | P1 trend-plot (filtreret til engaged) |
| Top 10 indikatorer | Erstattet | L3 clustered |
| Feature-brug | Erstattet | P6 adoption-rate (% sessions) |
| Wizard-flow med frafald | Erstattet | P2 |
| Fejl-oversigt | Erstattet | P3 normaliseret cluster |
| Performance (boxplot) | Erstattet | P4 p50/p95 percentil-bar |
| Browser/OS | Erstattet | P5 (krydset med fejl-rate) |
| Nye vs. tilbagevendende | Erstattet | L5 cohort retention |
| Tidsmønstre heatmap | Fjernet | Ikke prioriteret — kan tilføjes igen senere |

## Nye konstanter (R/utils_normalize.R)

Alle tærskler eksponeret i `ANALYTICS_CONSTANTS`:

- `engaged_duration_sec = 30` — minimum varighed for "engaged" session
- `indicator_cluster_threshold = 0.2` — Jaro-Winkler threshold for fuzzy-cluster (bumped fra 0.15 i task 7 for at dække "tryksaar afsnit B"-variant; JW = 0.176)
- `browser_min_sessions = 5` — minimum sessions per browser/OS-kombination
- `heatmap_min_cell = 3` — minimum sessions per heatmap-celle
- `perf_min_n = 10` — minimum n for percentil-beregning
- `test_session_max_duration = 10` — sessions kortere flag'es som test
- `stop_words` — ("test", "abc", "asdf", "qwerty", "xxx", "123", "test123", "lorem", "ipsum")
- `export_regex = "^export_(pdf|docx|png|svg|ai)_"` — formats-detection
- `column_input_regex = "^(skift|frys|target|maal)_column$"` — column-step detection

## Nye filer

- `R/utils_normalize.R` — konstanter + tekst-helpers + is_test_session
- `R/transform_sessions.R` — `build_session_facts()`
- `R/transform_indicators.R` — fuzzy-clustering (Jaro-Winkler)
- `R/transform_funnel.R` — 5-trins wizard funnel
- `R/kpi_product.R` — P1-P6
- `R/kpi_management.R` — L1-L6 (uden hospital/afdeling)
- `R/plot_product.R` + `R/plot_management.R`
- `tests/testthat/fixtures/synthesize.R` — synthetic fixture generator
- `tests/testthat/fixtures/synthetic_sessions.rds` — 50-sessions test-fixture
- `tests/testthat/helper-setup.R` — auto-source af R/*.R

## Slettet

- `R/kpi_calculations.R`, `R/plot_overview.R`, `R/plot_technical.R`

## Forberedelser til Fase 2 (Bundle A)

Når biSPCharts tilføjer `hospital` + `department` som inputs:

- `build_session_facts()` er allerede klargjort med `hospital_raw` + `department_raw`-placeholder (NA indtil felter ankommer)
- L1, L3, L6 udvides med hospital/afdeling-segmentering
- Se `docs/superpowers/specs/2026-05-16-analytics-redesign-design.md` sektion 4 + 7

## Test-strategi

- Synthetic fixture: `tests/testthat/fixtures/synthetic_sessions.rds`
- Regenerér via: `Rscript tests/testthat/fixtures/synthesize.R`
- Kør alle tests: `Rscript -e "testthat::test_dir('tests/testthat')"`
- Aktuel test-coverage: 123 PASS, 1 SKIP (env-gated PAT integration), 0 FAIL

## Render-tid

Måling pr. 2026-05-17:

- Mod tom data (PAT="" PIN_REPO_URL=""): ~5.3s
- Mod synthetic fixture (50 sessions): ~6.8s

Begge under 30s-threshold; cache-lag ej nødvendigt nu. Hvis prod-data vokser
betragteligt, implementér qs-fil-cache (se spec sektion 5).

## Kendte issues + opfølgning

1. **Export-format-regex bug** (`R/utils_normalize.R:20`): `export_regex` mangler
   `.*$` for at konsumere suffix. `kpi_export_breakdown` har defensive
   prefix-strip-workaround. Foreslå opfølgning: fix upstream regex + remove
   workaround.

2. **Threshold 0.15 → 0.2**: Spec-doc + plan-doc i `docs/superpowers/`
   nævner stadig 0.15. Opdatér ved næste større doc-pass.

3. **Lag 2 instrumentering**: Hospital/afdeling/wizard-events kræver
   biSPCharts-PR (Fase 2 Bundle A). Se spec sektion 4.
