##
## backup_clue.R: Backup/offline provider for clue.io data
##
## This provider loads pre-downloaded clue.io data from local files,
## serving as a fallback when the API is unavailable or for offline usage.
##

source("R/providers/base.R")

library(dplyr)
library(readr)
library(tibble)

#' BackupClueProvider Class
#'
#' Provider that loads drug/perturbagen data from local backup files
#' (data/pert_list.rds and data/full_list.tsv) instead of querying
#' the clue.io API directly.
#'
#' @export
BackupClueProvider <- R6::R6Class(

"BackupClueProvider",
  inherit = DataProvider,
  public = list(
    #' @field pertList Character vector of perturbagen names from pert_list.rds.
    pertList = NULL,

    #' @field fullList Data frame from full_list.tsv with target-compound mappings.
    fullList = NULL,

    #' @field pertListPath Path to pert_list.rds file.
    pertListPath = "data/pert_list.rds",

    #' @field fullListPath Path to full_list.tsv file.
    fullListPath = "data/full_list.tsv",

    #' @description
    #' Initialize BackupClueProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - pertListPath: Path to pert_list.rds
    #'   - fullListPath: Path to full_list.tsv
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "BackupClue", cache = cache, config = config)

      # Override default paths if provided in config
      if (!is.null(config$pertListPath)) {
        self$pertListPath <- config$pertListPath
      }
      if (!is.null(config$fullListPath)) {
        self$fullListPath <- config$fullListPath
      }
    },

    #' @description
    #' Load data from backup files. Called lazily on first data access.
    #' @return Invisible NULL.
    loadData = function() {
      if (is.null(self$pertList) && file.exists(self$pertListPath)) {
        message(paste0("Loading perturbagen list from ", self$pertListPath))
        self$pertList <- readRDS(self$pertListPath)
      }

      if (is.null(self$fullList) && file.exists(self$fullListPath)) {
        message(paste0("Loading full target list from ", self$fullListPath))
        self$fullList <- readr::read_tsv(
          self$fullListPath,
          col_types = readr::cols(.default = "c"),
          show_col_types = FALSE
        )
      }

      invisible(NULL)
    },

    #' @description
    #' Fetch perturbagen data for given target(s).
    #' @param query Query parameters. Accepts:
    #'   - List with 'targets' key (character vector of HUGO gene symbols)
    #'   - Character vector of HUGO gene symbols
    #'   - Single HUGO gene symbol string
    #' @return Data frame with matching compounds for the given targets.
    fetch = function(query) {
      self$loadData()

      # Normalize query to character vector of targets
      targets <- if (is.list(query) && !is.null(query$targets)) {
        query$targets
      } else if (is.character(query)) {
        query
      } else {
        stop("Query must be a character vector of targets or list with 'targets' key")
      }

      if (is.null(self$fullList)) {
        warning("BackupClue: full_list.tsv not loaded, returning empty result")
        return(tibble::tibble())
      }

      # Find the HUGO column (first column)
      hugoCol <- names(self$fullList)[1]

      result <- self$fullList %>%
        dplyr::filter(.data[[hugoCol]] %in% targets)

      return(result)
    },

    #' @description
    #' Get all perturbagen names from the backup data.
    #' @return Character vector of perturbagen names.
    getPertList = function() {
      self$loadData()
      return(self$pertList)
    },

    #' @description
    #' Get all target-compound mappings from the backup data.
    #' @return Data frame with all target-compound relationships.
    getFullList = function() {
      self$loadData()
      return(self$fullList)
    },

    #' @description
    #' Check if a compound exists in the backup data.
    #' @param compoundName Character string with compound name.
    #' @return TRUE if compound exists, FALSE otherwise.
    hasCompound = function(compoundName) {
      self$loadData()
      if (is.null(self$pertList)) {
        return(FALSE)
      }
      return(compoundName %in% self$pertList)
    },

    #' @description
    #' Get compounds targeting a specific gene.
    #' @param hugo HUGO gene symbol.
    #' @return Data frame with compounds targeting the gene.
    getCompoundsForTarget = function(hugo) {
      return(self$fetch(hugo))
    },

    #' @description
    #' Validate that backup files exist and can be loaded.
    #' @return TRUE if validation passes, FALSE otherwise.
    validate = function() {
      if (!super$validate()) {
        return(FALSE)
      }

      if (!file.exists(self$pertListPath)) {
        warning(paste0("Backup file not found: ", self$pertListPath))
        return(FALSE)
      }

      if (!file.exists(self$fullListPath)) {
        warning(paste0("Backup file not found: ", self$fullListPath))
        return(FALSE)
      }

      # Try loading data
      tryCatch({
        self$loadData()
        return(TRUE)
      }, error = function(e) {
        warning(paste0("Failed to load backup data: ", e$message))
        return(FALSE)
      })
    },

    #' @description
    #' Print provider information.
    print = function() {
      cat("<BackupClueProvider>\n")
      cat(paste0("  Pert list path: ", self$pertListPath, "\n"))
      cat(paste0("  Full list path: ", self$fullListPath, "\n"))
      cat(paste0("  Pert list loaded: ", !is.null(self$pertList), "\n"))
      cat(paste0("  Full list loaded: ", !is.null(self$fullList), "\n"))
      if (!is.null(self$pertList)) {
        cat(paste0("  Number of perturbagens: ", length(self$pertList), "\n"))
      }
      if (!is.null(self$fullList)) {
        cat(paste0("  Number of records: ", nrow(self$fullList), "\n"))
      }
    }
  )
)


#' Create a configured BackupClueProvider instance
#'
#' Factory function for creating BackupClueProvider with default or custom paths.
#'
#' @param pertListPath Path to pert_list.rds file.
#' @param fullListPath Path to full_list.tsv file.
#' @param cache Optional CacheManager instance.
#' @return Configured BackupClueProvider instance.
#' @export
createBackupClueProvider <- function(
  pertListPath = "data/pert_list.rds",
  fullListPath = "data/full_list.tsv",
  cache = NULL
) {
  BackupClueProvider$new(
    cache = cache,
    config = list(
      pertListPath = pertListPath,
      fullListPath = fullListPath
    )
  )
}
