##
## pipeline.R: Main data pipeline entry point
##
## Orchestrates data providers to build the enriched dataset for UI consumption.
## Reads from the persistent DataStore populated by refresh_data.R.
##
## Usage from command line:
## R -e 'source("R/pipeline.R"); main()'
##

##
## Load dependencies
##
library(dplyr)
library(glue)
library(readr)

##
## Load modules
##
source("R/cache.R")
source("R/providers/base.R")
source("R/providers/backup_clue.R")
source("R/providers/uniprot.R")
source("R/providers/fda.R")
source("R/providers/ema.R")
source("R/providers/pubmed.R")
source("R/providers/string.R")
source("R/providers/kegg.R")

##
## Configuration
##
OUTPUT_DIR <- "OUTPUT"
DATASTORE_PATH <- glue::glue("{OUTPUT_DIR}/datastore.sqlite")
TARGET_LIST_RDS <- glue::glue("{OUTPUT_DIR}/targetList.rds")
CLUE_RDS <- glue::glue("{OUTPUT_DIR}/clue.rds")
CLUE_PATCHED_RDS <- glue::glue("{OUTPUT_DIR}/clue_patched.rds")


#' Main Pipeline Function
#'
#' Reads data from the persistent DataStore and assembles the
#' enriched dataset for UI rendering.
#'
#' @param outputDir Output directory path.
#' @return Enriched data.frame.
#' @export
main <- function(outputDir = OUTPUT_DIR) {
  message("=== EZCancerTarget Pipeline ===")
  message(glue::glue("Output directory: {outputDir}"))

  # Initialize data store
  dataStore <- createDataStore(glue::glue("{outputDir}/datastore.sqlite"))
  message(glue::glue("DataStore initialized: {dataStore$dbPath}"))

  # Check data availability
  stats <- dataStore$stats()
  message(glue::glue("DataStore contains {stats$total_entries} entries"))

  if (stats$total_entries == 0) {
    stop("DataStore is empty. Run 'Rscript R/refresh_data.R' first to populate data.")
  }

  # Load target list
  targetList <- loadTargetList(outputDir)
  message(glue::glue("Loaded {nrow(targetList)} targets"))

  # Load clue data (from store or legacy RDS)
  clueData <- loadClueData(dataStore, outputDir)
  message(glue::glue("Loaded clue data: {nrow(clueData)} compounds"))

  # Join target list with clue data
  result <- targetList %>%
    dplyr::left_join(clueData, by = "HUGO") %>%
    dplyr::rowwise() %>%
    dplyr::mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID))) %>%
    dplyr::filter(has_data == TRUE)

  message(glue::glue("Joined data: {nrow(result)} records with data"))

  # Load enrichment data from store
  result <- enrichFromStore(result, dataStore)

  # Save result
  saveRDS(result, file = glue::glue("{outputDir}/clue_patched.rds"))
  message(glue::glue("Saved enriched data to {outputDir}/clue_patched.rds"))

  # Close data store

  dataStore$close()

  message("=== Pipeline completed ===")
  return(result)
}


#' Load Target List
#'
#' @param outputDir Output directory.
#' @return Target list data.frame.
loadTargetList <- function(outputDir) {
  targetListPath <- glue::glue("{outputDir}/targetList.rds")

  if (!file.exists(targetListPath)) {
    stop(glue::glue("Target list not found: {targetListPath}"))
  }

  return(readRDS(targetListPath))
}


#' Load Clue Data
#'
#' Loads clue.io data from DataStore or falls back to legacy RDS.
#'
#' @param dataStore DataStore instance.
#' @param outputDir Output directory.
#' @return Clue data.frame.
loadClueData <- function(dataStore, outputDir) {
  # Try loading from store first
  clueData <- dataStore$get("clue:compounds")

  if (!is.null(clueData)) {
    message("Loaded clue data from DataStore")
    return(clueData)
  }

  # Fall back to legacy RDS
  legacyPath <- glue::glue("{outputDir}/clue.rds")
  if (file.exists(legacyPath)) {
    message(glue::glue("Loading clue data from legacy file: {legacyPath}"))
    clueData <- readRDS(legacyPath) %>%
      dplyr::filter(!is.na(source))
    return(clueData)
  }

  stop("No clue data available in DataStore or legacy file")
}


#' Enrich Data from Store
#'
#' Applies enrichment data from the persistent DataStore.
#'
#' @param dataTable Input data.frame.
#' @param dataStore DataStore instance.
#' @return Enriched data.frame.
enrichFromStore <- function(dataTable, dataStore) {
  # Get unique identifiers
  compounds <- dataTable %>%
    dplyr::select(pert_iname) %>%
    dplyr::distinct() %>%
    dplyr::filter(!is.na(pert_iname)) %>%
    dplyr::pull(pert_iname)

  uniprotIds <- dataTable %>%
    dplyr::select(UNIPROT_KB_ID) %>%
    dplyr::distinct() %>%
    dplyr::filter(!is.na(UNIPROT_KB_ID)) %>%
    dplyr::pull(UNIPROT_KB_ID)

  message(glue::glue("Enriching {length(compounds)} compounds and {length(uniprotIds)} proteins"))

  # Load FDA data
  fdaData <- loadProviderData(dataStore, "fda", compounds)
  dataTable <- dataTable %>%
    dplyr::mutate(fdaSearchResults = fdaData[pert_iname])

  # Load PubMed data
  pubmedData <- loadProviderData(dataStore, "pubmed", compounds)
  dataTable <- dataTable %>%
    dplyr::mutate(
      pubMedPreClinicalLinks = list(pubmedData[[pert_iname]]),
      PubMedCounter = length(unlist(pubMedPreClinicalLinks))
    )

  # Load EMA data
  emaData <- loadProviderData(dataStore, "ema", compounds)
  dataTable <- dataTable %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      emaLinks = if (!is.null(emaData[[pert_iname]])) emaData[[pert_iname]]$url else NA_character_,
      emaProduct = if (!is.null(emaData[[pert_iname]])) emaData[[pert_iname]]$productName else NA_character_
    )

  # Load UniProt data
  uniprotData <- loadProviderData(dataStore, "uniprot", uniprotIds)
  dataTable <- dataTable %>%
    dplyr::rowwise() %>%
    dplyr::mutate(UniProtData = list(uniprotData[[UNIPROT_KB_ID]]))

  # Load KEGG pathway counts
  keggData <- loadProviderData(dataStore, "kegg", uniprotIds)
  dataTable <- dataTable %>%
    dplyr::rowwise() %>%
    dplyr::mutate(NumberOfKEGGPathways = {
      keggText <- keggData[[UNIPROT_KB_ID]]
      if (is.null(keggText) || is.na(keggText)) 0L else countKeggPathways(keggText)
    })

  # Load STRING interactor counts
  stringData <- loadProviderData(dataStore, "string", uniprotIds)
  dataTable <- dataTable %>%
    dplyr::rowwise() %>%
    dplyr::mutate(NumberOfSTRINGInteractors = {
      result <- stringData[[UNIPROT_KB_ID]]
      if (is.null(result) || !tibble::is_tibble(result)) 0L else nrow(result)
    })

  return(dataTable)
}


#' Load Provider Data from Store
#'
#' @param dataStore DataStore instance.
#' @param providerName Provider name prefix.
#' @param keys Keys to load.
#' @return Named list of data.
loadProviderData <- function(dataStore, providerName, keys) {
  result <- list()
  for (key in keys) {
    storeKey <- paste0(providerName, ":", key)
    result[[key]] <- dataStore$get(storeKey)
  }
  return(result)
}


#' Count KEGG Pathways
#'
#' @param keggText KEGG entry text.
#' @return Integer count.
countKeggPathways <- function(keggText) {
  if (is.na(keggText) || is.null(keggText)) {
    return(0L)
  }

  keggRegex <- stringr::regex(
    "^PATHWAY.+?^(NETWORK|DISEASE|DRUG_TARGET|BRITE)",
    multiline = TRUE,
    dotall = TRUE
  )

  numOfPathways <- keggText %>%
    stringr::str_extract(keggRegex) %>%
    stringr::str_count("\n")

  return(ifelse(is.na(numOfPathways), 0L, as.integer(numOfPathways)))
}


#' Get Pipeline Status
#'
#' Returns status information about the pipeline and data freshness.
#'
#' @param outputDir Output directory path.
#' @return List with status information.
#' @export
getPipelineStatus <- function(outputDir = OUTPUT_DIR) {
  dataStore <- createDataStore(glue::glue("{outputDir}/datastore.sqlite"))
  stats <- dataStore$stats()

  refreshHistory <- dataStore$getRefreshHistory(limit = 10)

  dataStore$close()

  return(list(
    datastore_stats = stats,
    recent_refreshes = refreshHistory
  ))
}
