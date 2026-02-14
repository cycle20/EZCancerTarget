#!/usr/bin/env Rscript
##
## refresh_data.R: Manual data refresh script
##
## This script fetches fresh data from all providers and stores it
## in the persistent DataStore for UI consumption.
##
## Usage from command line:
##   Rscript R/refresh_data.R              # Refresh all providers
##   Rscript R/refresh_data.R --provider fda    # Refresh specific provider
##   Rscript R/refresh_data.R --provider uniprot,kegg  # Multiple providers
##   Rscript R/refresh_data.R --list       # List available providers
##   Rscript R/refresh_data.R --status     # Show refresh status
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

# Available providers for refresh
AVAILABLE_PROVIDERS <- c("fda", "pubmed", "ema", "uniprot", "kegg", "string")


#' Main Refresh Function
#'
#' Refreshes data from specified providers (or all if none specified).
#'
#' @param providers Character vector of provider names to refresh.
#' @param outputDir Output directory path.
#' @return Invisible NULL.
#' @export
main <- function(providers = NULL, outputDir = OUTPUT_DIR) {
  message("=== EZCancerTarget Data Refresh ===")
  message(glue::glue("Timestamp: {Sys.time()}"))

  # Initialize data store
  dataStore <- createDataStore(glue::glue("{outputDir}/datastore.sqlite"))
  message(glue::glue("DataStore: {dataStore$dbPath}"))

  # Determine which providers to refresh
  if (is.null(providers) || length(providers) == 0) {
    providers <- AVAILABLE_PROVIDERS
    message("Refreshing ALL providers")
  } else {
    invalid <- setdiff(providers, AVAILABLE_PROVIDERS)
    if (length(invalid) > 0) {
      stop(glue::glue("Unknown providers: {paste(invalid, collapse = ', ')}"))
    }
    message(glue::glue("Refreshing providers: {paste(providers, collapse = ', ')}"))
  }

  # Load input data (compounds and proteins to refresh)
  inputData <- loadInputData(outputDir)
  compounds <- inputData$compounds
  uniprotIds <- inputData$uniprotIds

  message(glue::glue("Input: {length(compounds)} compounds, {length(uniprotIds)} proteins"))

  # Refresh each provider
  for (providerName in providers) {
    tryCatch({
      refreshProvider(providerName, dataStore, compounds, uniprotIds)
    }, error = function(e) {
      message(glue::glue("ERROR refreshing {providerName}: {e$message}"))
      dataStore$logRefresh(providerName, "failed", e$message)
    })
  }

  # Print summary
  stats <- dataStore$stats()
  message(glue::glue("\n=== Refresh Summary ==="))
  message(glue::glue("Total entries in DataStore: {stats$total_entries}"))
  message(glue::glue("Providers: {paste(stats$providers, collapse = ', ')}"))

  dataStore$close()
  message("=== Refresh completed ===")

  return(invisible(NULL))
}


#' Load Input Data for Refresh
#'
#' Extracts compound names and UniProt IDs from available data sources.
#'
#' @param outputDir Output directory.
#' @return List with compounds and uniprotIds vectors.
loadInputData <- function(outputDir) {
  compounds <- character(0)
  uniprotIds <- character(0)

  # Try loading from clue.rds
  cluePath <- glue::glue("{outputDir}/clue.rds")
  if (file.exists(cluePath)) {
    clueData <- readRDS(cluePath)

    compounds <- clueData %>%
      dplyr::filter(!is.na(pert_iname)) %>%
      dplyr::pull(pert_iname) %>%
      unique()
  }

  # Try loading from targetList.rds
  targetListPath <- glue::glue("{outputDir}/targetList.rds")
  if (file.exists(targetListPath)) {
    targetList <- readRDS(targetListPath)

    if ("UNIPROT_KB_ID" %in% names(targetList)) {
      uniprotIds <- targetList %>%
        dplyr::filter(!is.na(UNIPROT_KB_ID)) %>%
        dplyr::pull(UNIPROT_KB_ID) %>%
        unique()
    }
  }

  # Fallback to backup files
  if (length(compounds) == 0) {
    pertListPath <- "data/pert_list.rds"
    if (file.exists(pertListPath)) {
      compounds <- readRDS(pertListPath)
      message(glue::glue("Loaded {length(compounds)} compounds from backup"))
    }
  }

  return(list(
    compounds = compounds,
    uniprotIds = uniprotIds
  ))
}


#' Refresh a Single Provider
#'
#' @param providerName Provider name.
#' @param dataStore DataStore instance.
#' @param compounds Character vector of compound names.
#' @param uniprotIds Character vector of UniProt IDs.
refreshProvider <- function(providerName, dataStore, compounds, uniprotIds) {
  message(glue::glue("\n--- Refreshing {providerName} ---"))
  dataStore$logRefresh(providerName, "started")

  startTime <- Sys.time()
  recordCount <- 0

  if (providerName == "fda") {
    recordCount <- refreshFDA(dataStore, compounds)
  } else if (providerName == "pubmed") {
    recordCount <- refreshPubMed(dataStore, compounds)
  } else if (providerName == "ema") {
    recordCount <- refreshEMA(dataStore, compounds)
  } else if (providerName == "uniprot") {
    recordCount <- refreshUniProt(dataStore, uniprotIds)
  } else if (providerName == "kegg") {
    recordCount <- refreshKEGG(dataStore, uniprotIds)
  } else if (providerName == "string") {
    recordCount <- refreshSTRING(dataStore, uniprotIds)
  }

  elapsed <- difftime(Sys.time(), startTime, units = "mins")
  message(glue::glue("{providerName}: Refreshed {recordCount} records in {round(elapsed, 2)} minutes"))

  dataStore$logRefresh(providerName, "completed",
    glue::glue("Elapsed: {round(elapsed, 2)} mins"),
    recordCount
  )
}


#' Refresh FDA Data
#' @param dataStore DataStore instance.
#' @param compounds Compound names.
#' @return Number of records refreshed.
refreshFDA <- function(dataStore, compounds) {
  provider <- createFDALabelProvider(sleepTime = 30)
  count <- 0

  for (compound in compounds) {
    tryCatch({
      result <- provider$fetch(compound)
      dataStore$set(
        key = paste0("fda:", compound),
        value = result,
        provider = "fda"
      )
      count <- count + 1
      if (count %% 10 == 0) message(glue::glue("  FDA: {count}/{length(compounds)}"))
    }, error = function(e) {
      warning(glue::glue("FDA error for {compound}: {e$message}"))
    })
  }

  return(count)
}


#' Refresh PubMed Data
#' @param dataStore DataStore instance.
#' @param compounds Compound names.
#' @return Number of records refreshed.
refreshPubMed <- function(dataStore, compounds) {
  provider <- createPubMedProvider(sleepTime = 30)
  count <- 0

  for (compound in compounds) {
    tryCatch({
      result <- provider$fetch(compound)
      dataStore$set(
        key = paste0("pubmed:", compound),
        value = result,
        provider = "pubmed"
      )
      count <- count + 1
      if (count %% 10 == 0) message(glue::glue("  PubMed: {count}/{length(compounds)}"))
    }, error = function(e) {
      warning(glue::glue("PubMed error for {compound}: {e$message}"))
    })
  }

  return(count)
}


#' Refresh EMA Data
#' @param dataStore DataStore instance.
#' @param compounds Compound names.
#' @return Number of records refreshed.
refreshEMA <- function(dataStore, compounds) {
  provider <- createEMAProvider()
  count <- 0

  for (compound in compounds) {
    tryCatch({
      result <- provider$fetch(compound)
      dataStore$set(
        key = paste0("ema:", compound),
        value = result,
        provider = "ema"
      )
      count <- count + 1
      if (count %% 50 == 0) message(glue::glue("  EMA: {count}/{length(compounds)}"))
    }, error = function(e) {
      warning(glue::glue("EMA error for {compound}: {e$message}"))
    })
  }

  return(count)
}


#' Refresh UniProt Data
#' @param dataStore DataStore instance.
#' @param uniprotIds UniProt IDs.
#' @return Number of records refreshed.
refreshUniProt <- function(dataStore, uniprotIds) {
  provider <- createUniProtProvider(sleepTime = 5)
  count <- 0

  for (id in uniprotIds) {
    tryCatch({
      result <- provider$fetch(id)
      dataStore$set(
        key = paste0("uniprot:", id),
        value = result,
        provider = "uniprot"
      )
      count <- count + 1
      if (count %% 10 == 0) message(glue::glue("  UniProt: {count}/{length(uniprotIds)}"))
    }, error = function(e) {
      warning(glue::glue("UniProt error for {id}: {e$message}"))
    })
  }

  return(count)
}


#' Refresh KEGG Data
#' @param dataStore DataStore instance.
#' @param uniprotIds UniProt IDs.
#' @return Number of records refreshed.
refreshKEGG <- function(dataStore, uniprotIds) {
  # First need UniProt data to get KEGG IDs
  keggProvider <- createKEGGProvider(sleepTime = 5)
  count <- 0

  for (uniprotId in uniprotIds) {
    # Get UniProt data for KEGG ID
    uniprotData <- dataStore$get(paste0("uniprot:", uniprotId))

    if (!is.null(uniprotData) && !is.null(uniprotData$KEGG)) {
      keggId <- uniprotData$KEGG
      tryCatch({
        result <- keggProvider$fetch(keggId)
        dataStore$set(
          key = paste0("kegg:", uniprotId),
          value = result,
          provider = "kegg"
        )
        count <- count + 1
        if (count %% 10 == 0) message(glue::glue("  KEGG: {count}"))
      }, error = function(e) {
        warning(glue::glue("KEGG error for {keggId}: {e$message}"))
      })
    }
  }

  return(count)
}


#' Refresh STRING Data
#' @param dataStore DataStore instance.
#' @param uniprotIds UniProt IDs.
#' @return Number of records refreshed.
refreshSTRING <- function(dataStore, uniprotIds) {
  stringProvider <- createSTRINGProvider(sleepTime = 5)
  count <- 0

  for (uniprotId in uniprotIds) {
    # Get UniProt data for STRING ID
    uniprotData <- dataStore$get(paste0("uniprot:", uniprotId))

    if (!is.null(uniprotData) && !is.null(uniprotData$STRING)) {
      stringId <- uniprotData$STRING
      tryCatch({
        result <- stringProvider$fetch(stringId)
        dataStore$set(
          key = paste0("string:", uniprotId),
          value = result,
          provider = "string"
        )
        count <- count + 1
        if (count %% 10 == 0) message(glue::glue("  STRING: {count}"))
      }, error = function(e) {
        warning(glue::glue("STRING error for {stringId}: {e$message}"))
      })
    }
  }

  return(count)
}


#' Show Refresh Status
#'
#' Displays current status of the data store and recent refresh history.
#'
#' @param outputDir Output directory path.
showStatus <- function(outputDir = OUTPUT_DIR) {
  dataStore <- createDataStore(glue::glue("{outputDir}/datastore.sqlite"))

  stats <- dataStore$stats()
  cat("\n=== DataStore Status ===\n")
  cat(glue::glue("Database: {stats$db_path}\n"))
  cat(glue::glue("Total entries: {stats$total_entries}\n"))
  cat(glue::glue("Size: {stats$size_mb} MB\n"))
  cat(glue::glue("Providers: {paste(stats$providers, collapse = ', ')}\n"))

  if (!is.na(stats$oldest_update)) {
    cat(glue::glue("Oldest update: {stats$oldest_update}\n"))
    cat(glue::glue("Newest update: {stats$newest_update}\n"))
  }

  # Recent refresh history
  history <- dataStore$getRefreshHistory(limit = 20)
  if (nrow(history) > 0) {
    cat("\n=== Recent Refresh History ===\n")
    for (i in 1:min(10, nrow(history))) {
      row <- history[i, ]
      cat(glue::glue("{row$timestamp} | {row$provider} | {row$status} | {row$records_affected} records\n"))
    }
  }

  dataStore$close()
}


#' List Available Providers
listProviders <- function() {
  cat("\n=== Available Providers ===\n")
  for (p in AVAILABLE_PROVIDERS) {
    cat(glue::glue("  - {p}\n"))
  }
  cat("\nUsage:\n")
  cat("  Rscript R/refresh_data.R                    # Refresh all\n")
  cat("  Rscript R/refresh_data.R --provider fda     # Refresh specific\n")
  cat("  Rscript R/refresh_data.R --status           # Show status\n")
}


##
## Command-line interface
##
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)

  if ("--list" %in% args) {
    listProviders()
  } else if ("--status" %in% args) {
    showStatus()
  } else if ("--provider" %in% args) {
    idx <- which(args == "--provider")
    if (idx < length(args)) {
      providers <- strsplit(args[idx + 1], ",")[[1]]
      main(providers = providers)
    } else {
      stop("--provider requires a value")
    }
  } else {
    main()
  }
}
