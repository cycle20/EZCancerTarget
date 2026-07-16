# EZCancerTarget Refactoring Implementation Plan

## Problem Statement
The primary data source (clue.io) has been discontinued/retired. The project needs to be refactored to:
1. Use the existing backup data (`data/pert_list.rds` and `data/full_list.tsv`)
2. Introduce a data source abstraction layer for future extensibility
3. Create a local database (RDS or SQLite3) as the central data store
4. Export to JSON for a modern Web UI

## Current State
### Existing Data Assets
- `data/full_list.tsv`: 2,179 targets with HUGO symbol, Label, and UniProt KB ID
- `data/pert_list.rds`: Compound/perturbagen names from clue.io backup

### Current Pipeline (Deprecated)
1. `R/clue.R` → Downloads from clue.io API → `OUTPUT/clue.rds`
2. `R/dataPatch.R` → Enriches from FDA/PubMed/EMA/UniProt/KEGG/STRING → `OUTPUT/clue_patched.rds`
3. `R/renderWebPage.R` → Whisker template rendering → `OUTPUT/index.target.with.data.html`

### Current Data Sources
- **clue.io** (Broad Institute): Retired - replaced by backup data
- **FDA Label API**: Drug approval status
- **EMA**: European medicines data
- **PubMed**: Clinical trial references
- **UniProt**: Protein annotations
- **STRING-db**: Protein interactions
- **KEGG**: Pathway information

## Proposed Architecture

### Data Source Provider Interface
```
DataProvider (R6 Class / S3 Generic)
├── BackupClueProvider    # Local backup data (primary)
├── ChEMBLProvider        # Future: ChEMBL API
├── OpenTargetsProvider   # Future: Open Targets Platform
├── UniProtProvider       # Existing enrichment
├── FDAProvider           # Existing enrichment
├── EMAProvider           # Existing enrichment
├── PubMedProvider        # Existing enrichment
├── STRINGProvider        # Existing enrichment
└── KEGGProvider          # Existing enrichment
```

Each provider implements:
- `get_compounds(target_id)` - Get compounds targeting a gene
- `get_mechanism_of_action(compound_id)` - Get MoA for compound
- `get_clinical_status(compound_id)` - Get clinical trial phase
- `get_metadata()` - Provider metadata and version info

### New Pipeline Architecture
```
Input (target list)
       ↓
Target Normalization (HUGO → UniProt → Ensembl mapping)
       ↓
Data Acquisition (parallel provider queries)
       ↓
Evidence Aggregation (merge, deduplicate, score)
       ↓
Database Storage (SQLite3 or RDS)
       ↓
JSON Export
       ↓
Static Web UI (modern JS framework or enhanced current template)
```

### Database Schema (SQLite3)
```sql
-- Core entities
CREATE TABLE targets (
    id INTEGER PRIMARY KEY,
    hugo_symbol TEXT UNIQUE NOT NULL,
    uniprot_id TEXT,
    ensembl_id TEXT,
    label TEXT
);

CREATE TABLE compounds (
    id INTEGER PRIMARY KEY,
    pert_iname TEXT UNIQUE NOT NULL,
    pubchem_cid TEXT,
    chembl_id TEXT,
    drugbank_id TEXT,
    smiles TEXT,
    inchi_key TEXT
);

CREATE TABLE target_compound (
    target_id INTEGER REFERENCES targets(id),
    compound_id INTEGER REFERENCES compounds(id),
    moa TEXT,
    clinical_status TEXT,
    source TEXT,
    evidence_score REAL,
    PRIMARY KEY (target_id, compound_id)
);

-- Enrichment data
CREATE TABLE target_pathways (
    target_id INTEGER REFERENCES targets(id),
    pathway_id TEXT,
    pathway_name TEXT,
    source TEXT  -- KEGG, Reactome
);

CREATE TABLE target_interactions (
    target_id INTEGER REFERENCES targets(id),
    interactor_id TEXT,
    confidence_score REAL,
    source TEXT  -- STRING
);

CREATE TABLE target_go_terms (
    target_id INTEGER REFERENCES targets(id),
    go_id TEXT,
    go_term TEXT,
    category TEXT  -- molecular_function, biological_process, cellular_component
);

-- Clinical/regulatory data
CREATE TABLE compound_approvals (
    compound_id INTEGER REFERENCES compounds(id),
    agency TEXT,  -- FDA, EMA
    approval_status TEXT,
    label_url TEXT
);

CREATE TABLE compound_publications (
    compound_id INTEGER REFERENCES compounds(id),
    pubmed_id TEXT,
    title TEXT,
    publication_type TEXT
);
```

## Implementation Phases

### Phase 1: Stabilize & Abstract (2-3 weeks)
**Goal:** Wrap existing functionality in provider interface, add caching

#### Tasks
1. Create `R/providers/` directory structure
2. Implement base `DataProvider` class/interface in `R/providers/base.R`
3. Create `BackupClueProvider` in `R/providers/backup_clue.R`
   - Load `data/pert_list.rds` and `data/full_list.tsv`
   - Implement provider interface methods
4. Refactor `R/dataPatch.R` enrichment functions into separate providers:
   - `R/providers/uniprot.R` (extract from `xmlUniProt()`)
   - `R/providers/fda.R` (extract from `fdaLabel()`)
   - `R/providers/ema.R` (already exists at `R/download/ema.R`)
   - `R/providers/pubmed.R` (extract from `pubMed()`)
   - `R/providers/string.R` (extract from `stringInteractorsCounter()`)
   - `R/providers/kegg.R` (extract from `keggPathWayCounter()`)
5. Add SQLite3 caching layer in `R/cache.R`
   - Cache raw API responses with timestamps
   - Implement cache invalidation policy
6. Create new main entry point `R/pipeline.R`
7. Add provider contract tests in `inst/tinytest/test_providers.R`

#### Deliverables
- Provider abstraction layer
- Cached enrichment pipeline
- Unit tests for providers

### Phase 2: Database & JSON Export (2 weeks)
**Goal:** Implement SQLite3 database and JSON export

#### Tasks
1. Create database module `R/database.R`
   - Implement schema creation
   - CRUD operations for all entities
   - Migration support
2. Create `R/export.R` for JSON generation
   - Full database export to single JSON
   - Per-target JSON files for lazy loading
3. Update `R/pipeline.R` to use database storage
4. Create database population script from backup data
5. Add database integrity tests

#### Deliverables
- SQLite3 database implementation
- JSON export functionality
- Database populated with backup data

### Phase 3: Modern Web UI (2-3 weeks)
**Goal:** Create client-side rendered web interface

#### Tasks
1. Design JSON schema for web consumption
2. Create new `web/` structure:
   - `web/index.html` - Single page application shell
   - `web/js/app.js` - Main application logic
   - `web/js/data-loader.js` - JSON data loading
   - `web/css/styles.css` - Custom styles
3. Implement features:
   - Target list with search/filter
   - Target detail view (compounds, pathways, interactions)
   - Summary statistics dashboard
   - Compound detail modal
   - Export to CSV functionality
4. Ensure offline capability (all data in JSON)
5. Update `R/renderWebPage.R` to generate new format

#### Deliverables
- Modern single-page web application
- Responsive design
- Client-side search and filtering

### Phase 4: Alternative Providers (Ongoing)
**Goal:** Add ChEMBL and Open Targets as data sources

#### Tasks
1. Implement `ChEMBLProvider` in `R/providers/chembl.R`
   - Target search by UniProt ID
   - Compound activities and mechanisms
   - Clinical trial data
2. Implement `OpenTargetsProvider` in `R/providers/opentargets.R`
   - GraphQL API integration
   - Evidence scoring
   - Disease associations
3. Create evidence aggregation engine `R/aggregator.R`
   - Merge records from multiple sources
   - Deduplicate compounds
   - Composite scoring based on configurable weights
4. Add configuration file support `config.yml`
   - Enable/disable providers
   - Set evidence weights
   - API keys management

#### Deliverables
- ChEMBL provider
- Open Targets provider
- Evidence aggregation with scoring
- Configuration-driven execution

## File Structure (Post-Refactoring)
```
EZCancerTarget/
├── R/
│   ├── pipeline.R           # Main entry point
│   ├── database.R           # SQLite3 operations
│   ├── cache.R              # Response caching
│   ├── export.R             # JSON export
│   ├── aggregator.R         # Evidence aggregation
│   ├── renderWebPage.R      # Web generation (updated)
│   └── providers/
│       ├── base.R           # Provider interface
│       ├── backup_clue.R    # Local backup data
│       ├── uniprot.R        # UniProt enrichment
│       ├── fda.R            # FDA Label API
│       ├── ema.R            # EMA data
│       ├── pubmed.R         # PubMed search
│       ├── string.R         # STRING interactions
│       ├── kegg.R           # KEGG pathways
│       ├── chembl.R         # ChEMBL (Phase 4)
│       └── opentargets.R    # Open Targets (Phase 4)
├── data/
│   ├── full_list.tsv        # Target list backup
│   ├── pert_list.rds        # Compound backup
│   └── target_list.tsv      # User input
├── web/
│   ├── index.html           # SPA shell
│   ├── js/
│   │   ├── app.js
│   │   └── data-loader.js
│   └── css/
│       └── styles.css
├── inst/tinytest/
│   ├── test_providers.R
│   ├── test_database.R
│   └── test_export.R
├── config.yml               # Provider configuration
└── OUTPUT/
    ├── ezcancertarget.db    # SQLite3 database
    ├── data.json            # Full JSON export
    └── targets/             # Per-target JSON files
```

## Migration Strategy
1. Keep existing `R/clue.R` and `R/dataPatch.R` functional during transition
2. New pipeline runs in parallel, outputs compared for validation
3. Gradual migration of CI/CD workflows
4. Mark legacy code as deprecated with removal timeline

## Success Criteria
- [ ] Pipeline runs without clue.io API dependency
- [ ] All existing functionality preserved
- [ ] Database contains all backup data
- [ ] JSON export generates valid data
- [ ] Web UI displays all targets and compounds
- [ ] At least one additional provider (ChEMBL) functional
- [ ] Test coverage > 80% for new code
