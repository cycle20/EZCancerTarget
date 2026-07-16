# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

EZCancerTarget (package name: `scancer`) is an R package that collects drug compound data from multiple sources (CLUE Repurposing, FDA, EMA, PubMed, UniProt, STRING) and generates a static HTML summary page for drug targets.

## Build & Development Commands

> **Run all R in the `ezct` container — never on the host.** This project's R
> dependencies live in the `cycle20/ezct` runtime image (managed via renv). Do
> NOT install R packages or run `Rscript`/`R` on the host, as that pollutes the
> host environment. Every R command below should be executed inside the
> container. See [Running R in the container](#running-r-in-the-container).

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

### Running R in the container

`exec/docker/run_pipeline.bash` is the canonical example: it bind-mounts the
project at `/app` and runs R non-interactively in the SLIM runtime image. Use
the same pattern for any ad-hoc R command, test, or script. The container's
`app` user is uid 1000, matching the host project ownership, so mounted writes
land with correct ownership.

```bash
# General form: run an arbitrary R expression in the container
docker run --rm \
  --volume "$(pwd)":/app \
  -w /app \
  cycle20/ezct:3.1.0 \
  R --quiet --no-save -e 'YOUR_R_CODE_HERE'

# Run the full pipeline (or a single stage) via the helper script
exec/docker/run_pipeline.bash          # clue -> patch -> render
exec/docker/run_pipeline.bash clue     # single stage

# Run tests in the container
docker run --rm --volume "$(pwd)":/app -w /app cycle20/ezct:3.1.0 \
  Rscript -e 'tinytest::test_all()'
```

> **Caution — `source("R/refresh_data.R")` auto-runs a full refresh.** Scripts
> with a `if (!interactive()) { ... }` CLI block (e.g. `R/refresh_data.R`) will
> execute `main()` when sourced under `R -e`/`Rscript`, because those are
> non-interactive. To source *only the function definitions* for testing,
> mask `interactive()` first:
> `R --quiet --no-save -e 'interactive <- function() TRUE; source("R/refresh_data.R"); <your test>'`

## Main Pipeline Scripts

Execute in order (each requires previous step's output):

```bash
# 1. Collect data from clue.io (reads local data/repurposing_drugs_*.rds;
#    the clue.io API is retired, so no API key is needed)
R -e 'source("R/clue.R"); main()'

# 2. Patch data with FDA/PubMed/EMA/UniProt information
R -e 'source("R/dataPatch.R"); main()'

# 3. Render final HTML page
R -e 'source("R/renderWebPage.R"); main()'
```

## Docker Development

```bash
# Start rocker container (set PASSWORD first)
PASSWORD=yourpass exec/docker/run_rocker.bash
```

## Architecture

### Data Flow
1. `R/clue.R` → Assembles drug-target data from a local clue.io snapshot (`data/repurposing_drugs_*.rds`; live API retired) → outputs `OUTPUT/clue.rds`
2. `R/dataPatch.R` → Enriches data from FDA/PubMed/EMA/UniProt/KEGG/STRING → outputs `OUTPUT/clue_patched.rds`
3. `R/renderWebPage.R` → Renders HTML using `web/template.html` (whisker templating) → outputs `OUTPUT/index.target.with.data.html`

### Key R Modules
- `R/clue.R`: API clients for clue.io endpoints (rep_drug_targets, rep_drugs, rep_samples, etc.)
- `R/dataPatch.R`: Data enrichment functions (fdaLabel, pubMed, ema, xmlUniProt, keggPathWayCounter, stringInteractorsCounter)
- `R/renderWebPage.R`: HTML generation with whisker templates
- `R/download/ema.R`: EMA-specific download utilities

### External Data Sources
- **clue.io** (Broad Institute): Primary drug/target data. The live API is retired; `R/clue.R` now reads a local snapshot (`data/repurposing_drugs_*.rds`), so no API key is required.
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
- Run tests **inside the container** (see [Running R in the container](#running-r-in-the-container))

### Low-volume data refresh (harnessing minimal data)

`R/refresh_data.R` fetches provider data for the **entire** input list (~6800
compounds, ~2200 proteins), which is slow and hits external APIs heavily. For
development/testing, use `--limit N` to cap each provider to the first `N`
samples. This keeps downloads small (e.g. 5-7 per provider):

```bash
# Test one provider with 5 samples, in the container
docker run --rm --volume "$(pwd)":/app -w /app cycle20/ezct:3.1.0 \
  Rscript R/refresh_data.R --provider fda --limit 5

# Combine providers; --limit applies to both compound- and protein-based ones
docker run --rm --volume "$(pwd)":/app -w /app cycle20/ezct:3.1.0 \
  Rscript R/refresh_data.R --provider fda,uniprot --limit 5
```

Input for the refresh comes from `OUTPUT/clue.rds` (compounds) and
`OUTPUT/targetList.rds` (UniProt IDs), which are produced by `R/clue.R`. When
those are absent, `loadInputData()` falls back to the committed backups
`data/pert_list.rds` (compounds) and `data/full_list.tsv` (UniProt IDs), so a
limited refresh can run without first executing the clue.io download stage.
**Running the full refresh without `--limit` is very time-consuming — avoid it
during routine development.**

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `tests.yml`: Runs tinytest on PRs
- `clue.yml`: Full pipeline execution and deployment to gh-pages
- `cocomo.yml`: Code metrics

## Environment Variables

- `SERVICE_TOKEN_JSON`: Google Sheets service account (for reading target lists)
- `TARGET_LIST_ID`: Google Spreadsheet ID (optional, falls back to local TSV)
