# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

EZCancerTarget (package name: `scancer`) is an R package that collects drug compound data from multiple sources (CLUE Repurposing, FDA, EMA, PubMed, UniProt, STRING) and generates a static HTML summary page for drug targets.

## Build & Development Commands

```bash
# Activate renv environment (happens automatically via .Rprofile)
source("renv/activate.R")

# Restore dependencies
Rscript -e 'renv::restore()'

# Run all tests
Rscript -e 'tinytest::test_all()'

# Run specific test file
Rscript -e 'tinytest::run_test_file("inst/tinytest/test_scancer.R", verbose = 0)'
```

## Main Pipeline Scripts

Execute in order (each requires previous step's output):

```bash
# 1. Collect data from clue.io (requires CLUE_USER_KEY env var)
R -e 'source("R/clue.R"); main()'

# 2. Patch data with FDA/PubMed/EMA/UniProt information
R -e 'source("R/dataPatch.R"); main()'

# 3. Render final HTML page
R -e 'source("R/renderWebPage.R"); main()'
```

## Docker Development

```bash
# Start rocker container (set PASSWORD and optionally CLUE_USER_KEY first)
PASSWORD=yourpass exec/docker/run_rocker.bash
```

## Architecture

### Data Flow
1. `R/clue.R` → Downloads drug-target data from clue.io API → outputs `OUTPUT/clue.rds`
2. `R/dataPatch.R` → Enriches data from FDA/PubMed/EMA/UniProt/KEGG/STRING → outputs `OUTPUT/clue_patched.rds`
3. `R/renderWebPage.R` → Renders HTML using `web/template.html` (whisker templating) → outputs `OUTPUT/index.target.with.data.html`

### Key R Modules
- `R/clue.R`: API clients for clue.io endpoints (rep_drug_targets, rep_drugs, rep_samples, etc.)
- `R/dataPatch.R`: Data enrichment functions (fdaLabel, pubMed, ema, xmlUniProt, keggPathWayCounter, stringInteractorsCounter)
- `R/renderWebPage.R`: HTML generation with whisker templates
- `R/download/ema.R`: EMA-specific download utilities

### External Data Sources
- **clue.io** (Broad Institute): Primary drug/target data; requires `CLUE_USER_KEY` API key
- **FDA Label API**: Drug approval status and labeling
- **EMA**: European medicines data (from Excel file)
- **PubMed**: Clinical trial references
- **UniProt**: Protein annotations
- **STRING-db**: Protein interaction data
- **KEGG**: Pathway information

### Input/Output
- Input: `data/target_list.tsv` or Google Spreadsheet (via `TARGET_LIST_ID`)
- Output directory: `OUTPUT/` (gitignored)
- Final artifact: `OUTPUT/index.target.with.data.html`

## Testing

Uses `tinytest` framework. Test files are in `inst/tinytest/`:
- Tests require `setwd('../..')` at start to access R source files
- Tests may make real HTTP requests to external APIs

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `tests.yml`: Runs tinytest on PRs
- `clue.yml`: Full pipeline execution and deployment to gh-pages
- `cocomo.yml`: Code metrics

## Environment Variables

- `CLUE_USER_KEY`: Required for clue.io API access
- `SERVICE_TOKEN_JSON`: Google Sheets service account (for reading target lists)
- `TARGET_LIST_ID`: Google Spreadsheet ID (optional, falls back to local TSV)
