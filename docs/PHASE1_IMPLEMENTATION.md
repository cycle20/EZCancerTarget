# Phase 1 Implementation: Stabilize & Abstract

Phase 1 implementation complete. This document describes the new provider-based architecture with persistent data storage.

## Overview

The existing functionality from `R/dataPatch.R` has been wrapped in a provider interface pattern, with SQLite3-based persistent storage replacing the TSV-based caching. Data refresh is now a separate manual operation.

## New Files Created

### Provider Framework

| File | Description |
|------|-------------|
| `R/providers/base.R` | R6 base classes: `DataProvider`, `EnrichmentProvider`, `CompoundProvider`, `ProteinProvider` |
| `R/providers/backup_clue.R` | `BackupClueProvider` - loads `data/pert_list.rds` and `data/full_list.tsv` |
| `R/providers/uniprot.R` | `UniProtProvider` - fetches GO terms, STRING/KEGG/Reactome cross-refs |
| `R/providers/fda.R` | `FDALabelProvider` - searches FDA Label API for drug labels |
| `R/providers/ema.R` | `EMAProvider` - matches compounds against EMA Excel report |
| `R/providers/pubmed.R` | `PubMedProvider` - fetches clinical trial references |
| `R/providers/string.R` | `STRINGProvider` - fetches protein interaction counts |
| `R/providers/kegg.R` | `KEGGProvider` - fetches pathway counts |

### Storage & Pipeline

| File | Description |
|------|-------------|
| `R/cache.R` | `DataStore` - SQLite3 persistent storage for UI consumption (no TTL expiration) |
| `R/pipeline.R` | Main entry point - reads from DataStore to assemble enriched data |
| `R/refresh_data.R` | Manual refresh script - fetches fresh data from providers |

### Tests

| File | Description |
|------|-------------|
| `inst/tinytest/test_providers.R` | Contract tests for providers and DataStore |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Manual Refresh Process                      │
│                    (R/refresh_data.R)                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │   FDA    │ │  PubMed  │ │  UniProt │ │   EMA    │  ...       │
│  │ Provider │ │ Provider │ │ Provider │ │ Provider │            │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘            │
│       │            │            │            │                  │
│       └────────────┴────────────┴────────────┘                  │
│                          │                                      │
│                          ▼                                      │
│              ┌───────────────────────┐                          │
│              │      DataStore        │                          │
│              │  (SQLite3 Database)   │                          │
│              │  OUTPUT/datastore.db  │                          │
│              └───────────┬───────────┘                          │
└──────────────────────────┼──────────────────────────────────────┘
                           │
                           │ (Persistent Storage)
                           │
┌──────────────────────────┼──────────────────────────────────────┐
│                          ▼                                      │
│              ┌───────────────────────┐                          │
│              │      Pipeline         │                          │
│              │   (R/pipeline.R)      │                          │
│              └───────────┬───────────┘                          │
│                          │                                      │
│                          ▼                                      │
│              ┌───────────────────────┐                          │
│              │  clue_patched.rds     │  ──────▶  UI / HTML      │
│              └───────────────────────┘                          │
│                     UI Consumption                              │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

### Refresh Data (Manual Operation)

```bash
# Refresh all provider data
Rscript R/refresh_data.R

# Refresh specific providers
Rscript R/refresh_data.R --provider fda,pubmed

# Refresh only protein-related providers
Rscript R/refresh_data.R --provider uniprot,kegg,string

# Check refresh status
Rscript R/refresh_data.R --status

# List available providers
Rscript R/refresh_data.R --list
```

### Run Pipeline

```bash
# Run pipeline (uses persistent DataStore)
R -e 'source("R/pipeline.R"); main()'

# Check pipeline status
R -e 'source("R/pipeline.R"); getPipelineStatus()'
```

### Run Tests

```bash
# Run provider tests
Rscript -e 'tinytest::run_test_file("inst/tinytest/test_providers.R")'

# Run all tests
Rscript -e 'tinytest::test_all()'
```

## Provider Interface

All providers inherit from `DataProvider` and implement:

- `fetch(query)` - Fetch data for a single query
- `fetchBatch(queries)` - Fetch data for multiple queries
- `validate()` - Validate provider configuration
- `getName()` - Get provider identifier

Enrichment providers additionally implement:

- `enrich(dataTable)` - Enrich a data.frame with provider data
- `getOutputColumns()` - List columns added by enrichment

## DataStore API

```r
# Create store
store <- createDataStore("OUTPUT/datastore.sqlite")

# Basic operations
store$set(key, value, provider = "name")
store$get(key)
store$delete(key)
store$exists(key)

# Query operations
store$listKeys(provider = NULL)
store$getMetadata(key)
store$stats()

# Maintenance
store$clearProvider("provider_name")
store$clearAll()

# Refresh logging
store$logRefresh(provider, status, message, recordsAffected)
store$getRefreshHistory(provider = NULL, limit = 100)
```

## Migration Notes

- The original `R/dataPatch.R` and `R/clue.R` remain unchanged for backward compatibility
- The new pipeline reads from DataStore but falls back to legacy RDS files if DataStore is empty
- Run `Rscript R/refresh_data.R` to populate the DataStore before using the new pipeline
