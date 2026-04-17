# Connect Cloud Setup — biSPCharts Analytics Pipeline

Trin-for-trin guide til at opsaette pin-flowet mellem biSPCharts og
biSPCharts-analytics paa Posit Connect Cloud.

## Arkitektur

```
biSPCharts (Connect Cloud)               bispcharts-analytics-data (GitHub, privat)
  └─ session$onSessionEnded()                ├─ sessions/
       └─ sync_logs_to_github()    ─push─>   │   ├─ 20260417T084211Z_abc12345.rds
                                             │   ├─ 20260417T091503Z_def67890.rds
                                             │   └─ ...
                                             └─ README.md
                                                       ↑
                                                       │ (clone + read)
biSPCharts-analytics (Connect Cloud)                   │
  └─ render index.qmd                                  │
       └─ load_analytics_data() ──clone + bind_rows──┘
```

## Engangs-opsaetning

### 1. Generer fine-grained GitHub PAT

1. Gaa til https://github.com/settings/personal-access-tokens/new
2. **Token name:** `bispcharts-analytics-pipeline`
3. **Resource owner:** `johanreventlow`
4. **Repository access:** "Only select repositories" →
   `johanreventlow/bispcharts-analytics-data`
5. **Permissions → Repository permissions:**
   - `Contents`: **Read and write** (biSPCharts skal kunne pushe)
6. Klik **Generate token** → kopiér token vaerdien straks
   (vises kun én gang)

**Note:** samme token bruges af begge apps. Hvis du vil separere
write/read, opret to tokens (men én med `Read and write` er nok).

### 2. Saet variables paa biSPCharts (write-side)

1. Gaa til https://connect.posit.cloud/bispcharts
2. Klik paa `bispcharts-app` content
3. Vaelg **Settings → Variables** (eller Advanced settings → Variables)
4. Tilfoej:

   | Variabel | Vaerdi |
   |----------|--------|
   | `GITHUB_PAT` | *(token fra step 1)* |
   | `PIN_REPO_URL` | `https://github.com/johanreventlow/bispcharts-analytics-data.git` |

5. Klik **Save**
6. **Republish** eller restart appen saa env vars loades

### 3. Saet variables paa biSPCharts-analytics (read-side)

Samme procedure paa analytics-content. Samme to env vars.

### 4. Test flowet

1. Aabn https://bispcharts-app.share.connect.posit.cloud/ og interager lidt
2. Luk browseren (trigger `onSessionEnded`)
3. Verificer ny fil i data-repo:

   ```
   gh api /repos/johanreventlow/bispcharts-analytics-data/contents/sessions --jq ".[].name"
   ```

4. Trigger render af analytics-dashboard (eller vent paa daily schedule)
5. Dashboard skal nu vise data

## Troubleshooting

### "GITHUB_PAT eller PIN_REPO_URL ikke sat — bruger tom data"

Env vars er ikke loadet. Tjek:
- Variables er gemt paa **content-niveau** (ikke account)
- App er genstarted efter variable-ændringer
- Variable-navne er staavekorrekte (case-sensitive)

### "Clone fejlede"

- Token udloebet eller revokeret → generér ny
- PIN_REPO_URL forkert → skal ende paa `.git`
- Token mangler `contents:read` paa data-repo

### "Push fejlede"

- Token mangler `contents:write`
- Data-repo branch-protection afviser push (fjern for `main`)

## PAT-rotation

Fine-grained PATs kan udloebe (1 aar max). For at rotere:
1. Generer ny PAT (step 1)
2. Opdater `GITHUB_PAT` paa begge content items
3. Republish/restart
4. Revoker gammel PAT
