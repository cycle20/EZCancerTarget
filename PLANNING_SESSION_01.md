Swith to branch: issue_54_full_target_list

This is a conversation with ChatGPT on EZCancerTarget.
It is a planning of a huge refactoring to improve this R package, since clue.io is discontinued/retired.
Now we have a backup of clue.io data in data/pert_list.rds and data/full_list.tsv
These are probably the initial input data of the workflow to generate and create a database (RDS or SQLite3 format).
This database can be converted into a json file and that can be loaded and displayed in a Web UI.
Something similare to described by the template in web/template.html.
Create a detailed implementation plan for this vision and consider the roadmap at the end of the conversation.
Save it into IMPLEMENTATION_PLAN.md commit it with a conventional commit message and pushd it to the remote GitHub repository.


--------------------------

# EZCancerTarget Refactoring Discussion

------------------------------------------------------------------------

## User

what do you know about EZCancerTarget project?

------------------------------------------------------------------------

## Assistant

Here's an overview of the **EZCancerTarget** project based on available
scientific and project information:

### 📌 What EZCancerTarget Is

**EZCancerTarget** is an open-access, data-aggregating drug-repurposing
and target-validation platform designed to help researchers identify and
prioritize potential therapeutic targets and compounds in cancer
research. It integrates information from multiple public biomedical
databases into a structured, user-friendly system.

### 🧠 Core Purpose & Motivation

-   Created to simplify interpretation and aggregation of molecular and
    pharmacological data for cancer targets.
-   Supports smaller research teams without deep bioinformatics
    expertise.
-   Emphasizes transparency and reproducibility.

### 💡 Key Features & Functions

#### Data Aggregation & Search:

-   Uses Clue.io's drug-repurposing hub as its primary search engine.
-   Integrates data from sources such as PubChem, DrugBank, PubMed, EMA,
    UniProt, STRING, GeneCards, Gene Ontology.

#### Report Generation:

-   Produces downloadable HTML reports.
-   Includes clinical status, mechanisms of action, and links to
    external databases.

#### Molecular Context:

-   Functional annotations (GO terms)
-   Pathways
-   Interactors
-   Subcellular localization
-   Literature references

### 🧪 How It Works

1.  Users prepare a target list (HUGO gene names, UniProt IDs).
2.  R scripts fetch drug-target associations via Clue.io.
3.  Data is enriched from additional sources.
4.  A structured report is generated.

### 📌 Research Context

-   Initially focused on aggressive cancers (SCLC, TNBC, pancreatic
    adenocarcinoma).
-   Extensible to custom target lists.

### 🧑‍🔬 Intended Users

-   Translational scientists
-   Clinical researchers
-   Bioinformatics beginners
-   Small research teams

------------------------------------------------------------------------

## User

Can you provide refactoring ideas? Since clue.io is an archived source
and maybe it is obsoleted?

------------------------------------------------------------------------

## Assistant

Yes --- and that's the right architectural moment to rethink the design.

Below are structured, actionable refactoring ideas:

# 1. Introduce a Data Source Abstraction Layer

Refactor Clue.io into a provider interface:

DrugTargetProvider\
├── ClueProvider (legacy)\
├── LINCSProvider\
├── OpenTargetsProvider\
├── ChEMBLProvider\
├── CustomCSVProvider

Each provider implements:

-   get_compounds(target_id)\
-   get_mechanism_of_action(compound_id)\
-   get_evidence_score(target, compound)\
-   get_metadata()

Benefits: - Replaceable sources - Parallel validation - Cleaner
testing - Future-proof design

------------------------------------------------------------------------

# 2. Move to Multi-Source Evidence Federation

Instead of:

clue.io → report

Refactor to:

multiple providers\
↓\
evidence aggregator\
↓\
scoring engine\
↓\
report

Define a unified evidence record:

EvidenceRecord:\
- source\
- confidence\
- evidence_type\
- citation

Then compute composite scoring.

------------------------------------------------------------------------

# 3. Introduce Canonical Internal Data Model

Normalize entities internally:

Target:\
- uniprot_id\
- ensembl_id\
- hugo_symbol

Compound:\
- chembl_id\
- pubchem_id\
- smiles

All providers must map to this schema.

------------------------------------------------------------------------

# 4. Modular Pipeline Stages

Refactor into explicit stages:

1.  Input parsing\
2.  Target normalization\
3.  Data acquisition\
4.  Evidence aggregation\
5.  Scoring\
6.  Report generation

Each stage: - Pure where possible\
- Serializable outputs\
- Cacheable

------------------------------------------------------------------------

# 5. Add Caching Layer

Options: - SQLite\
- DuckDB\
- JSON cache

Cache raw API responses with timestamps for: - Reproducibility\
- Offline analysis\
- Regression testing

------------------------------------------------------------------------

# 6. Testing Refactor

Add provider contract tests:

-   test_get_compounds_returns_valid_schema()\
-   test_handles_missing_target()\
-   test_rate_limit_behavior()

Use mocked API responses to avoid brittleness.

------------------------------------------------------------------------

# 7. Configuration-Driven Execution

Example config:

providers:\
- chembl\
- open_targets

weights:\
chembl: 0.6\
open_targets: 0.4

Allows ranking experimentation without code changes.

------------------------------------------------------------------------

# 8. CLI Modularization

ezct fetch\
ezct aggregate\
ezct score\
ezct report

Improves automation and CI workflows.

------------------------------------------------------------------------

# 9. Scientific Separation of Concerns

Split into:

Target Knowledge Module\
Drug Evidence Module\
Integration Layer

Enables independent evolution of components.

------------------------------------------------------------------------

# 10. Migration Roadmap

## Phase 1 -- Stabilize

-   Wrap Clue.io in interface\
-   Add tests\
-   Add caching

## Phase 2 -- Parallel Providers

-   Implement ChEMBL + Open Targets\
-   Compare outputs

## Phase 3 -- Aggregation Engine

-   Composite scoring\
-   Evidence weighting

## Phase 4 -- Deprecate Clue.io

-   Mark as legacy\
-   Keep optional fallback
