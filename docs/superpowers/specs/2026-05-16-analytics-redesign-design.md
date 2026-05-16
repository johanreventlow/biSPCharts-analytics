# Analytics-redesign — Design

**Status:** Proposed
**Dato:** 2026-05-16
**Forfatter:** Brainstormet via superpowers:brainstorming
**Scope:** biSPCharts-analytics dashboard + roadmap for instrumentering i biSPCharts-app

---

## 1. Problem-statement + designrammer

**Kerneproblem:** Nuværende KPI'er er proxy-tal uden bundet decision-job.

Konkrete eksempler:

- "Unikke besøgende" — monotont voksende, ej afgrænset til tidsvindue → ej brugbar som tendens
- "Completion rate" — tæller `chart_type`-valg ≠ faktisk fuldført analyse; tidsmismatch mellem tæller (alle inputs) + nævner (7d sessions)
- "Gns. varighed" — labelet "gennemsnit", men beregnet som median; session_duration støjet pga. lange åbne tabs
- "Top indikator" — rå fri tekst → "Tryksår" / "tryksår" / "tryksår LUH" / "test" konkurrerer i samme bucket
- "Trend uge/uge" — partial uge sammenlignes med fuld uge → bias
- "Wizard-flow Upload" — defineret som total sessions, men mange har ej uploadet noget → overestimat

**Designrammer:**

1. **Hver KPI har et decision-job** — én sætning der besvarer "hvilken beslutning ændres af dette tal?". KPI uden decision-job slettes.
2. **Tidsvinduer skal være eksplicitte** og konsistente per view (7d / 28d / siden launch).
3. **Fri tekst normaliseres** før den vises som KPI (lowercase + trim + fuzzy-clustering for top-N; rå tekst kun i drill-down).
4. **Funnel-trin defineres ud fra adfærd, ej tilstedeværelse** (fx "upload-trin" = sessions med ej-tom data-upload, ikke alle sessions).
5. **To views med eget vokabular:** Produkt (friction-fokuseret), Ledelse (adoption-fokuseret). Internt brug — ingen public/community-view.
6. **Lag 1 leverbar uden ændringer i biSPCharts;** Lag 2 dokumenterer udvidelser med separate ROI-vurderinger.

---

## 2. Målgrupper + decision-jobs

### View P — Produktudvikler

Beslutning: hvor skal næste sprint fokus ligge?

Decision-jobs:

- Hvilket wizard-step taber flest brugere? → prioritér UX-fix
- Stiger fejl-rate efter sidste release? → rollback eller hotfix?
- Hvilke features bruges aldrig? → sunset-kandidater
- Bremser performance konkrete browser/OS-kombinationer? → kompatibilitets-arbejde
- Hvilke brugere oplever crashes (klynge-analyse)? → reproducer + fix

### View L — Ledelse/stakeholder

Beslutning: skal vi udbrede + investere mere?

Decision-jobs:

- Hvor mange hospitaler + afdelinger bruger biSPCharts aktivt (sidste 28d)?
- Vokser adoption uge for uge? Flader retention ud?
- Hvilke afdelinger bruger mest? Hvilke har stagneret?
- Hvor mange analyser leveres faktisk (eksport-events)? Bruges AI-fortolkning?
- Hvilke indikator-kategorier dominerer (tryksår, fald, infektion …)? Signal om use case-bredde.

**Eksplicit ud af scope:** Public/community-view for klinikere — dashboardet ses kun internt.

---

## 3. Lag 1 — Quick wins på eksisterende data

Alt nedenstående bygges uden ændringer i biSPCharts. Hver KPI har: decision-job → definition → datakilde → kendt risiko.

### View P (Produkt)

**P1. Aktive sessions (7d / 28d)**

- Decision: Er trafikken stabil? Pludselig drop = produktionsproblem.
- Definition: `count(sessions WHERE server_connected ≥ now() - Xd AND session_duration ≥ 30s)`. 30s-tærskel filtrerer drive-by-tabs.
- Kilde: `sessions`
- Risiko: 30s-tærskel arbitrær — eksponér som konstant i `utils_normalize.R`.

**P2. Wizard-frafald per trin (corrected funnel — Lag 1 proxy)**

- Decision: Hvor sker friction?
- Definition: Trin udledt af input-hændelser per session:
  - Trin 1 *Data tilgængelig*: session har input matching `auto_restore_data` ELLER første "kolonne-valg"-input (svag proxy fordi `paste_data_input` er ekskluderet)
  - Trin 2 *Kolonner valgt*: session har input matching `^(skift|frys|target|maal)_column$`
  - Trin 3 *Diagramtype valgt*: session har input `chart_type` med ej-tom value
  - Trin 4 *Output genereret*: session har row i `outputs` med name matchende SPC-plot
  - Trin 5 *Eksport*: session har input matchende `^export_` (præcis prefix)
- Kilde: `inputs` + `outputs` joined på `sessionid`
- Risiko: Trin 1 er svagt — markeres som "datainput-detekteret (proxy)". Erstattes af eksakte events i Fase 3 (I2).

**P3. Fejl-cluster top 10 (28d)**

- Decision: Hvilke fejl rammer flest unikke sessions?
- Definition: errors grupperet på normaliseret error_message (strip linjenumre + dynamiske ID'er), tæller unikke sessionid.
- Kilde: `errors`
- Risiko: Fejl-strenge varierer; regex-normalisering kræves.

**P4. Performance percentiler (p50 / p95) per nøgle-metric**

- Decision: Er load-tid acceptabel? P95 > 5s → undersøg.
- Definition: percentiler af `load_complete_ms`, `ttfb_ms`, `dom_ready_ms`. Erstatter boxplot.
- Kilde: `analytics_performance`
- Risiko: Outliers fra langsomme netværk — vis p50 + p95 separat, ikke gennemsnit.

**P5. Browser/OS-distribution + fejl-rate per kombination**

- Decision: Er én browser problematisk?
- Definition: Cross-tab af browser × fejl-frekvens per session.
- Kilde: `client_meta` + `errors`
- Risiko: Lav volumen for visse browsere → vis kun kombinationer med ≥ 5 sessions.

**P6. Feature-adoption rate**

- Decision: Bruger nogen feature X? Hvis nej, sunset-kandidat.
- Definition: For hver tracked input-id: % sessions der minimum udløste den én gang (28d-vindue).
- Kilde: `inputs`
- Risiko: Liste over feature-id'er skal vedligeholdes manuelt; dokumentér i config.

### View L (Ledelse)

**L1. Aktive analyser (28d)**

- Decision: Bruges systemet operationelt?
- Definition: count sessions der nåede trin 4 (output genereret) i 28d-vinduet.
- Kilde: `outputs` + `sessions`
- Risiko: Tæller arbejdsleg vs. ægte analyser — markér eksplicit som "completed visualizations", ikke "patient-rettede analyser".

**L2. Eksporterede analyser (28d) + eksport-type fordeling**

- Decision: Forlader output appen? Hvor (PDF / Word / AI / billede)?
- Definition: distinct sessions med matchende `^export_(pdf|docx|png|svg|ai)_` input-id'er.
- Kilde: `inputs`
- Risiko: Input-id-mønster skal verificeres mod biSPCharts; afvigelser fanger ej eksporter. Præciseres i Fase 2 (I3).

**L3. Top 20 indikator-titler (normaliseret + clustered)**

- Decision: Hvilke kvalitetstemaer dominerer?
- Definition: Pipeline:
  1. Filtrer `inputs` på `name == "indicator_title"`
  2. Drop tomme + < 3 tegn
  3. Lowercase + trim + collapse whitespace
  4. Drop test-værdier via stop-liste ("test", "abc", "asdf", …)
  5. Fuzzy-cluster med `stringdist::stringdistmatrix` (Jaro-Winkler) + threshold 0.15
  6. Pick repræsentant per klynge (mest hyppige variant)
  7. Top 20 efter unikke sessions
- Kilde: `inputs`
- Risiko: Clustering-parametre kræver tuning; vis altid antal varianter per klynge så user kan vurdere kvaliteten.

**L4. Trend uger 1-12 (rullende vindue)**

- Decision: Vokser brug eller plateauer?
- Definition: ISO-uger med fuld-uge-flag; plottes som linje med markering af partial uge.
- Kilde: `sessions`
- Risiko: Partial uge må aldrig sammenlignes med fuld uge i deltaer.

**L5. Retention-kohorter (week-cohort retention)**

- Decision: Vender brugere tilbage?
- Definition: visitor_id grupperet efter første-besøgs-uge; cellerne viser % af kohorten aktive i uge N+1, N+2, …
- Kilde: `client_meta` + `sessions`
- Risiko: visitor_id mistes ved cleared localStorage → underestimat retention. Note: "lower bound for retention".

**L6. Use case-fordeling (chart-type × indikator-cluster)**

- Decision: Hvilke chart-typer driver hvilke use cases?
- Definition: heatmap mellem chart_type-værdier og top-20 indicator-cluster.
- Kilde: `inputs`
- Risiko: Krydstabel kan blive sparsom — vis kun celler med ≥ 3 sessions.

### KPI'er der fjernes fra nuværende dashboard

| Nuværende | Årsag |
|-----------|-------|
| Unikke besøgende (uden tidsvindue) | Monotont; ej beslutningsdrevet |
| Completion rate (chart_type-baseret) | Forkert proxy; erstattes af P2 + L1 |
| Gns. varighed (mislabeled median) | Støjet; lange tabs forstyrrer; intet decision-job |
| Top indikator (rå fri tekst) | Erstattes af L3 normaliseret |
| Trend uge/uge (partial week-bias) | Erstattes af L4 med fuld-uge-flag |
| Wizard-flow Upload=alle | Erstattes af P2 corrected funnel |

---

## 4. Lag 2 — Instrumenterings-roadmap

Hver post: decision-job-unlock → nyt felt/event → biSPCharts-ændring → privacy/consent-konsekvens → indsats-estimat (S/M/L).

### I1. Hospital + afdeling som tracked inputs (HØJ)

- **Unlocker:** L-view segmentering (adoption per hospital/afdeling), retention per afdeling, geografisk spredning.
- **Felt:** Eksisterende `department` + nyt `hospital` som synlige `textInput`'er i wizard-trin 0 / metadata-panel.
- **biSPCharts-ændring:** Tilføj to `textInput` i wizard. Skal NOT være ekskluderet i `exclude_input_id` → bliver auto-tracked af shinylogs.
- **Privacy:** Internt dashboard — droppet eksplicit privacy-mitigation per beslutning.
- **Indsats:** S (≈ 2 timer biSPCharts + dashboard-parsing).

### I2. Wizard-step events (HØJ)

- **Unlocker:** Eksakt step-frafald (P2 erstattes af reel telemetry, ej proxy).
- **Felt:** Custom shinylogs-event via `shinylogs::track_event()` med `event_name = "wizard_step_completed"` + payload `list(step = N, duration_ms = …)`.
- **biSPCharts-ændring:** Tilføj observers i wizard-gates der fyrer event ved hver step-completion (wizard-gates infrastruktur eksisterer allerede).
- **Privacy:** Ingen ny PII. Eksisterende consent dækker.
- **Indsats:** M (≈ 1 dag, kræver tests + gate-mapping).

### I3. Eksport-typing (MEDIUM)

- **Unlocker:** L2 præcis (PDF vs Word vs AI vs PNG) i stedet for regex-match.
- **Felt:** Custom event `export_initiated` med `format`, `success/fail`, `duration_ms`.
- **biSPCharts-ændring:** Hook i `mod_export_download` + `mod_export_ai`.
- **Privacy:** Ingen ny PII.
- **Indsats:** S (≈ 3 timer).

### I4. Data-karakteristik (MEDIUM)

- **Unlocker:** Hvor store datasæt analyserer folk? Hvilke datatyper? Korrelerer størrelse med performance/fejl?
- **Felt:** Custom event `dataset_loaded` med `n_rows`, `n_cols`, `column_types_summary` (counts per type), `source` (paste/file/restore). **Ingen kolonne-navne eller værdier** (PHI-risiko).
- **biSPCharts-ændring:** Hook efter data-validation success.
- **Privacy:** Tæller + typer er ej PHI. Påkrævet eksplicit udelukkelse af kolonne-navne + værdier.
- **Indsats:** M.

### I5. AI-feature-brug (MEDIUM)

- **Unlocker:** Bruges BFHllm/AI-eksport? Værdifuld for ledelse-rapport.
- **Felt:** Custom event `ai_feature_used` med `feature_id` (export_ai, kommentar-generering osv.), `model_id`, `latency_ms`, `success/fail`.
- **biSPCharts-ændring:** Hook i AI-relaterede moduler. **Ingen prompt-indhold logges** (defensive coding).
- **Indsats:** S–M.

### I6. Valideringsfejl-typer (LAV)

- **Unlocker:** Hvilke valideringsregler rammer flest (skip vs fix)? Signal om upload-UX.
- **Felt:** Custom event `validation_failed` med `rule_id`, `step`, `user_action` (fix/skip/abandon).
- **biSPCharts-ændring:** Hook i validation-engine.
- **Indsats:** M.

### I7. Repeat-analysis-detection (LAV)

- **Unlocker:** Loyalitet — vender folk tilbage til samme analyse? Indikerer "operational use" vs "eksperimentering".
- **Felt:** Hash af (visitor_id, normaliseret indicator_title, kolonne-mapping-fingeraftryk) → "analysis_signature". Logget per session.
- **biSPCharts-ændring:** Compute signature efter wizard-completion.
- **Indsats:** M.

### Bundle-prioritering

- **Bundle A (HØJ ROI, lav indsats):** I1 + I3 → låser ledelses-segmentering + præcis eksport-typing. ≈ 1-2 dages arbejde i biSPCharts + dashboard-parsing.
- **Bundle B (MEDIUM):** I2 + I4 → eksakt wizard-funnel + data-karakteristik. ≈ 2-3 dage.
- **Bundle C (LANGSIGTET):** I5 + I6 + I7 → AI-brug + valideringsmønstre + retention-signatur. Tages når Bundle A + B er stabile.

---

## 5. Datamodel + transformationer

### Rå-tabeller (uændret schema fra shinylogs)

| Tabel | Nøgle | Felter (relevante) |
|-------|-------|--------------------|
| `sessions` | `sessionid` | `app`, `user`, `server_connected`, `server_disconnected`, nested client-info |
| `inputs` | `sessionid` + `timestamp` + `name` | `name`, `value`, `type`, `binding` |
| `outputs` | `sessionid` + `timestamp` + `name` | `name`, `binding`, `type` |
| `errors` | `sessionid` + `timestamp` | `error`, `binding`, `type` |

### Afledt fact-tabel: `session_facts`

Bygges via reduce over rå-tabeller. Kolonner:

| Kolonne | Type | Kilde | Lag |
|---------|------|-------|-----|
| `sessionid` | chr | sessions | - |
| `connected_at` | POSIXct | sessions.server_connected | - |
| `disconnected_at` | POSIXct | sessions.server_disconnected | - |
| `duration_sec` | num | beregnet | - |
| `engaged` | lgl | `duration_sec >= 30` | 1 |
| `visitor_id` | chr | client_metadata | 1 |
| `browser` | factor | parsed user_agent | 1 |
| `os` | factor | parsed user_agent | 1 |
| `hospital_raw` | chr | inputs[name=="hospital"] (NA hvis ej instrumenteret) | 2 (I1) |
| `department_raw` | chr | inputs[name=="department"] | 2 (I1) |
| `hospital` | chr | normaliseret (trim, lowercase, cluster) | 2 |
| `department` | chr | normaliseret | 2 |
| `indicator_title_raw` | chr | inputs[name=="indicator_title"] | 1 |
| `indicator_cluster` | chr | fuzzy-cluster label | 1 |
| `chart_type` | factor | inputs[name=="chart_type"] | 1 |
| `step_data_proxy` | lgl | proxy for data-trin (Lag 1) | 1 |
| `step_columns` | lgl | session matched column-input regex | 1 |
| `step_chart_type` | lgl | session har chart_type | 1 |
| `step_output_generated` | lgl | session har row i outputs matching SPC | 1 |
| `step_exported` | lgl | session har row i inputs matching `^export_` | 1 |
| `export_formats` | list-col | vector af eksport-formater | 1 + 2 |
| `n_errors` | int | count rows i errors per session | 1 |
| `error_signatures` | list-col | normaliserede error-hashes | 1 |
| `load_complete_ms` | num | analytics_performance | 1 |
| `ttfb_ms` | num | analytics_performance | 1 |
| `dom_ready_ms` | num | analytics_performance | 1 |
| `is_test_session` | lgl | heuristik (test-titler, intern visitor_id, kort varighed) | 1 |
| `dataset_n_rows` | int | event dataset_loaded | 2 (I4) |
| `dataset_n_cols` | int | event dataset_loaded | 2 (I4) |
| `ai_features_used` | list-col | events ai_feature_used | 2 (I5) |
| `wizard_step_durations` | list-col | events wizard_step_completed | 2 (I2) |

### Filstruktur

```
R/
├── data_load.R               # uændret (clone + bind_rows)
├── github_sync.R             # uændret
├── transform_sessions.R      # NY — bygger session_facts fra rå
├── transform_indicators.R    # NY — fuzzy-clustering pipeline
├── transform_funnel.R        # NY — Lag 1 proxy + Lag 2 events
├── kpi_product.R             # NY — View P KPI'er
├── kpi_management.R          # NY — View L KPI'er
├── plot_product.R            # NY — View P grafer
├── plot_management.R         # NY — View L grafer
└── utils_normalize.R         # NY — string-normalisering, test-filter, stop-lister
```

### Cache-strategi

Quarto render kører ved scheduled deployment (dagligt). Transform-pipeline kan tage tid hvis sessions vokser. Brug qs-fil-cache i `.cache/` med sessions-dir-fingerprint som key, hvis render-tid > 30s.

Cache invalidation: `hash(paste(sort(list.files(sessions_dir)), collapse=","))` → ny fil = ny key → recompute.

### Test-fixtures

`tests/testthat/fixtures/`:

- `synthetic_sessions.rds` — 50 sessions med varierende kombinationer (test-sessions, engaged, eksporter, fejl)
- `synthetic_indicator_titles.csv` — input til fuzzy-cluster-tests (kendte clusters + støj)

### Filer der ændres / fjernes

- `index.qmd` — split i to dashboard-tabs (P + L), drop nuværende value boxes
- `R/kpi_calculations.R` — slettes (erstattes af kpi_product/management.R)
- `R/plot_overview.R` — slettes
- `R/plot_technical.R` — opdeles + flyttes til plot_product.R / plot_management.R

---

## 6. Privacy + compliance

Per beslutning droppes: k-anonymitet, PHI-regex-filter i indicator_title, retention-reduktion, consent-modal-tekst-opdatering, generelle compliance-handlinger.

Tilbageværende tekniske regler (kvalitet/defensive coding, ej compliance):

- **Test-session-filter** i `utils_normalize.R` — heuristik: indicator_title in stop-liste, intern visitor_id, varighed < 10s. Sessions flag'es `is_test_session = TRUE` + ekskluderes default fra views.
- **AI-events må ej logge prompt/response** (I5) — kun model_id, latency, success-bool.
- **Dataset-events må ej logge kolonne-navne/værdier** (I4) — kun tællere + type-summary.

---

## 7. Implementering — faseopdeling

### Fase 1 — Quick wins (uden biSPCharts-ændringer)

**Mål:** Erstat nuværende dashboard med fixed KPI-katalog. Leverbar isoleret.

**Arbejdsblokke (rækkefølge):**

1. **Filstruktur-refactor** — slet `kpi_calculations.R`, `plot_overview.R`, `plot_technical.R`. Opret `utils_normalize.R`, `transform_sessions.R`, `transform_indicators.R`, `transform_funnel.R`.
2. **session_facts builder** — `build_session_facts(sessions, inputs, outputs, errors, client_meta, perf_metrics)`. Test mod synthetic fixture (50 sessions).
3. **Indicator-clustering pipeline** — `normalize_indicator_titles()` + `cluster_indicator_titles()` (Jaro-Winkler, threshold 0.15). Test: kendte clusters (tryksår-varianter), stop-liste, < 3 tegn drops.
4. **Funnel-builder (Lag 1 proxy)** — `build_wizard_funnel(session_facts)` → 5-trins tibble. Test: synthetic sessions med forskellige step-kombinationer.
5. **KPI-moduler split** — `kpi_product.R` (P1-P6) + `kpi_management.R` (L1-L6 uden hospital/afdeling).
6. **Plot-moduler split** — `plot_product.R` + `plot_management.R`.
7. **Dashboard-restruktur** — `index.qmd` → to tabs ("Produkt" + "Ledelse"). Drop value boxes; hver KPI får decision-job-tekst under titel.
8. **Cache-lag** — kun hvis render > 30s. qs-fil-cache i `.cache/` med sessions-dir-hash som key.

**Tests-mål Fase 1:** ≥ 80% coverage på transforms + KPI-funktioner. Plot-funktioner røg-tester (kører uden fejl mod tom + fuld fixture).

**Estimeret indsats:** 2-3 dage.

### Fase 2 — Bundle A (I1 + I3)

**Mål:** Aktivér ledelses-segmentering (hospital + afdeling) + præcis eksport-typing.

**Arbejdsblokke:**

1. **biSPCharts-side (separat PR i biSPCharts-repo):**
   - I1: Tilføj `hospital` + `department` som `textInput` i wizard-metadata-trin
   - I3: Custom event `export_initiated` via `shinylogs::track_event()` i `mod_export_download` + `mod_export_ai`
   - Tests + lintr + `devtools::check()`
2. **Analytics-dashboard-side:**
   - Udvid `build_session_facts()` med `hospital_raw`, `department_raw`, `export_formats`
   - Tilføj `cluster_hospital_department()` (samme stringdist-pipeline som indicators)
   - Udvid L1 med segmentering, L2 med eksport-format-split, L3 med hospital-filter
   - Heatmap L6 chart-type × indikator-cluster med dropdown for hospital-filter

**Estimeret indsats:** 1-2 dage biSPCharts + 1 dag dashboard.

### Fase 3 — Bundle B (I2 + I4)

**Mål:** Erstat Lag 1 funnel-proxy med eksakte wizard-step-events. Tilføj dataset-karakteristik.

**Arbejdsblokke:**

1. **biSPCharts-side:**
   - I2: `track_event("wizard_step_completed", list(step, duration_ms))` i wizard-gates
   - I4: `track_event("dataset_loaded", list(n_rows, n_cols, column_types_summary, source))` efter validation-success
   - Tests for event-payload-skema
2. **Analytics-dashboard-side:**
   - Erstat `transform_funnel.R` proxy-logik med event-baseret beregning
   - Tilføj P2 step-duration-percentiler (p50 / p95 per step)
   - Ny graf: dataset-størrelse-distribution + korrelation med performance

**Estimeret indsats:** 2-3 dage.

### Fase 4 — Bundle C (I5 + I6 + I7, langsigtet)

Skydes til Fase 1-3 stabile + observeret behov. Specificeres ej i detaljer nu — kun roadmap-noter.

### Rollout-strategi

- Fase 1 leveres som single PR i biSPCharts-analytics-repo. Ingen breaking changes til data-pipeline.
- Fase 2 kræver koordineret release: biSPCharts merge + deploy FØRST, vent på 2-3 dages data-akkumulering, DEREFTER dashboard-PR med segmentering.
- Fase 3 samme pattern.
- Hver fase: separate spec → plan → implementation-cykler. Denne spec dækker Fase 1 fuldt + Fase 2-4 som roadmap.

---

## 8. Success criteria + validering

### Funktionelle kriterier (Fase 1)

- [ ] Dashboard renderer uden fejl mod tom data-repo, mod synthetic fixture, mod prod-data
- [ ] To tabs: "Produkt" + "Ledelse". Nuværende "Overblik" + "Teknisk" fjernet
- [ ] P1-P6 + L1-L6 (uden hospital/afdeling) viser meningsfulde værdier eller "Ingen data"-placeholder
- [ ] Hver KPI har label med decision-job-tekst (én sætning under titel)
- [ ] Funnel viser 5 trin, ikke 3, og bruger Lag 1 proxy-logik korrekt
- [ ] Indicator-clustering producerer ≤ 20 clusters fra synthetic-fixture med ≥ 200 titler
- [ ] Trend-graf viser fuld-uge-flag for partial uge
- [ ] Test-sessions ekskluderet default (toggle for at vise)

### Datakvalitets-kriterier

- [ ] `session_facts` schema verificeres mod typed-expectation (`expect_named`, `expect_type`)
- [ ] Manglende felter i rå data degraderer gracefully (NA, ikke crash)
- [ ] Performance-percentiler beregnes kun når n ≥ 10 sessions i vinduet

### Performance-kriterier

- [ ] Render-tid ≤ 30s mod prod-data (uden cache)
- [ ] Med cache: ≤ 5s når sessions-dir uændret

### Test-dækning

- [ ] `utils_normalize.R`: ≥ 90%
- [ ] `transform_sessions.R`: ≥ 85%
- [ ] `transform_indicators.R`: ≥ 85%
- [ ] `transform_funnel.R`: ≥ 85%
- [ ] `kpi_product.R` + `kpi_management.R`: ≥ 80%
- [ ] Plot-funktioner: smoke tests (ej content-assertions)

### Validering før Fase 1 deploy

1. Kør dashboard lokalt mod kopi af prod-data
2. Sammenlign nye KPI'er med nuværende: dokumentér ændringer i `docs/CHANGES.md`
3. Manuelt eyeball hver KPI: "matcher dette decision-job-teksten? Giver tallet mening?"
4. Render `index.qmd` mod tom data-repo → forventer "Ingen data" overalt, ej crash
5. Render mod synthetic fixture → forventer kendte værdier i KPI'er

### Validering før Fase 2 deploy

1. Verificér at biSPCharts-side faktisk udsender `hospital` + `department` inputs + `export_initiated` event
2. Vent ≥ 3 dage efter biSPCharts-deploy
3. Tjek at session_facts-builder fanger nye felter (`!is.na(hospital_raw)` rate > 0)
4. Deploy dashboard-side først efter felter konstateret

### Success-metrik for selve omdesignet (efter 30d)

- [ ] Antal KPI'er du faktisk bruger til beslutninger ≥ 50% af KPI-katalog (ellers: trim)
- [ ] Mindst én konkret produkt-beslutning truffet baseret på View P
- [ ] Mindst én konkret ledelse-rapport leveret baseret på View L

---

## 9. Beslutninger truffet undervejs

- **Mix-targeting:** P + L views, intet community/public-view
- **Bredt brainstorm-scope:** Lag 1 quick wins + Lag 2 roadmap, prioritering bagefter
- **Hybrid-tilgang (C):** decision-job-først per KPI, plus data-inventar i to lag
- **Privacy-mitigations droppet:** dashboard er internt → k-anon, PHI-regex, retention-reduktion, consent-bump alle ekskluderet
- **Test-session-filter beholdes** som kvalitets-issue, ikke privacy
