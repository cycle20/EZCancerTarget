##
## ema.R: EMA (European Medicines Agency) data provider
##
## Fetches drug approval information from EMA's published Excel report.
## Matches compounds against the active substance field.
##

source("R/providers/base.R")

library(dplyr)
library(readxl)
library(curl)
library(stringr)
library(glue)

#' EMAProvider Class
#'
#' Provider for fetching drug approval information from EMA.
#' Downloads and parses the EMA public assessment reports Excel file.
#'
#' @export
EMAProvider <- R6::R6Class(
  "EMAProvider",
  inherit = CompoundProvider,
  public = list(
    #' @field emaBaseUrl Base URL for EMA files.
    emaBaseUrl = "https://www.ema.europa.eu/sites/default/files",

    #' @field emaFileName EMA Excel report filename.
    emaFileName = "Medicines_output_european_public_assessment_reports.xlsx",

    #' @field outputDir Directory for downloaded files.
    outputDir = "OUTPUT",

    #' @field reportTable Cached report data.
    reportTable = NULL,

    #' @description
    #' Initialize EMAProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - emaFileName: Override default EMA file name
    #'   - outputDir: Directory for downloads
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "EMA", cache = cache, config = config)

      if (!is.null(config$emaFileName)) {
        self$emaFileName <- config$emaFileName
      }
      if (!is.null(config$outputDir)) {
        self$outputDir <- config$outputDir
      }
    },

    #' @description
    #' Load the EMA report from Excel file.
    #' Downloads if not present locally.
    #' @return Data frame with EMA report data.
    loadReport = function() {
      if (!is.null(self$reportTable)) {
        return(self$reportTable)
      }

      reportFile <- file.path(self$outputDir, self$emaFileName)

      # Download if needed
      if (!file.exists(reportFile)) {
        private$downloadEMAFile(self$emaFileName, reportFile)
      }

      # Read Excel file (skip header rows)
      self$reportTable <- readxl::read_excel(reportFile, skip = 7)
      return(self$reportTable)
    },

    #' @description
    #' Fetch EMA data for a compound.
    #' @param query Query parameters. Accepts:
    #'   - List with 'compound' key
    #'   - Character string with compound name
    #' @return List with url and productName.
    fetch = function(query) {
      # Normalize query
      compoundName <- if (is.list(query) && !is.null(query$compound)) {
        query$compound
      } else if (is.character(query) && length(query) == 1) {
        query
      } else {
        stop("Query must be a compound name string or list with 'compound' key")
      }

      reportTable <- self$loadReport()

      message(paste0("EMA SEARCH: compound: ", compoundName))

      # Filter by active substance
      matches <- reportTable %>%
        dplyr::filter(private$compareCompounds(`Active substance`, compoundName))

      if (nrow(matches) == 0) {
        return(list(
          url = NA_character_,
          productName = NA_character_
        ))
      }

      # Return first match
      return(list(
        url = matches$URL[1],
        productName = matches$`Medicine name`[1]
      ))
    },

    #' @description
    #' Enrich a data table with EMA links.
    #' @param dataTable Input data.frame with pert_iname column.
    #' @return Enriched data.frame with emaLinks and emaProduct columns.
    enrich = function(dataTable) {
      if (!"pert_iname" %in% names(dataTable)) {
        warning("EMA :: dataTable must have pert_iname column")
        return(dataTable)
      }

      # Get unique compound names
      compoundList <- dataTable %>%
        dplyr::select(pert_iname) %>%
        dplyr::distinct() %>%
        dplyr::filter(!is.na(pert_iname)) %>%
        dplyr::pull(pert_iname)

      # Fetch data for each compound
      emaResults <- list()
      for (compound in compoundList) {
        emaResults[[compound]] <- self$fetchCached(compound)
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::rowwise() %>%
        dplyr::mutate(
          emaLinks = emaResults[[pert_iname]]$url,
          emaProduct = emaResults[[pert_iname]]$productName
        )

      return(dataTable)
    },

    #' @description
    #' Get output column names.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      return(c("emaLinks", "emaProduct"))
    },

    #' @description
    #' Get EMA product information PDF URL.
    #' @param urlName URL name from EMA report.
    #' @return PDF URL string.
    getProductInfoUrl = function(urlName) {
      urlName <- stringr::str_remove(urlName, "^https:.+/")
      return(glue::glue(
        "https://www.ema.europa.eu/en/documents/product-information/{urlName}-epar-product-information_en.pdf"
      ))
    },

    #' @description
    #' Validate provider configuration.
    #' @return TRUE if valid, FALSE otherwise.
    validate = function() {
      if (!super$validate()) {
        return(FALSE)
      }

      # Try loading report
      tryCatch({
        self$loadReport()
        return(TRUE)
      }, error = function(e) {
        warning(paste0("EMA validation failed: ", e$message))
        return(FALSE)
      })
    }
  ),

  private = list(
    #' Download EMA Excel file
    #' @param fileName File to download.
    #' @param destFile Destination path.
    downloadEMAFile = function(fileName, destFile) {
      url <- glue::glue("{self$emaBaseUrl}/{fileName}")
      message(paste0("Downloading ", url))

      dir.create(dirname(destFile), recursive = TRUE, showWarnings = FALSE)
      curl::curl_download(url = url, destfile = destFile, mode = "wb", quiet = FALSE)
    },

    #' Compare compound names (case-insensitive, ignore special chars)
    #' @param substance Active substance from EMA report.
    #' @param compound Compound name to search.
    #' @return TRUE if match, FALSE otherwise.
    compareCompounds = function(substance, compound) {
      pattern <- "[()+]"
      cleanSubstance <- stringr::str_remove_all(substance, pattern)
      cleanCompound <- stringr::str_remove_all(compound, pattern)
      compoundRegex <- stringr::regex(cleanCompound, ignore_case = TRUE)
      return(stringr::str_detect(cleanSubstance, compoundRegex))
    }
  )
)


#' Create a configured EMAProvider instance
#'
#' @param outputDir Directory for downloaded files.
#' @param cache Optional CacheManager instance.
#' @return Configured EMAProvider instance.
#' @export
createEMAProvider <- function(outputDir = "OUTPUT", cache = NULL) {
  EMAProvider$new(
    cache = cache,
    config = list(outputDir = outputDir)
  )
}
