##
## kegg.R: KEGG pathway database provider
##
## Fetches pathway information from KEGG REST API.
## Counts the number of pathways associated with target proteins.
##

source("R/providers/base.R")

library(dplyr)
library(httr)
library(readr)
library(stringr)
library(glue)

#' KEGGProvider Class
#'
#' Provider for fetching pathway data from KEGG REST API.
#' Counts pathways associated with protein targets.
#'
#' @export
KEGGProvider <- R6::R6Class(
  "KEGGProvider",
  inherit = ProteinProvider,
  public = list(
    #' @field apiUrl KEGG REST API base URL.
    apiUrl = "http://rest.kegg.jp/get/",

    #' @field sleepTime Delay between requests in seconds.
    sleepTime = 5,

    #' @description
    #' Initialize KEGGProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - apiUrl: Override default KEGG API URL
    #'   - sleepTime: Delay between requests
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "KEGG", cache = cache, config = config)

      if (!is.null(config$apiUrl)) {
        self$apiUrl <- config$apiUrl
      }
      if (!is.null(config$sleepTime)) {
        self$sleepTime <- config$sleepTime
      }
    },

    #' @description
    #' Fetch KEGG entry data for a gene.
    #' @param query Query parameters. Accepts:
    #'   - List with 'kegg_id' key
    #'   - Character string with KEGG gene ID
    #' @return Character string with KEGG entry data.
    fetch = function(query) {
      # Normalize query
      keggId <- if (is.list(query) && !is.null(query$kegg_id)) {
        query$kegg_id
      } else if (is.character(query) && length(query) == 1) {
        query
      } else {
        stop("Query must be a KEGG ID string or list with 'kegg_id' key")
      }

      url <- paste0(self$apiUrl, keggId)

      tryCatch({
        Sys.sleep(self$sleepTime)

        response <- httr::GET(url)
        result <- httr::content(response, as = "text")

        return(result)
      }, error = function(e) {
        warning(paste0("KEGG :: Failed to fetch ", keggId, ": ", e$message))
        return(NA_character_)
      })
    },

    #' @description
    #' Count pathways in KEGG entry data.
    #' @param keggText KEGG entry text.
    #' @return Integer count of pathways.
    countPathways = function(keggText) {
      if (is.na(keggText) || is.null(keggText)) {
        return(0L)
      }

      # Regex to extract PATHWAY section
      keggRegex <- stringr::regex(
        "^PATHWAY.+?^(NETWORK|DISEASE|DRUG_TARGET|BRITE)",
        multiline = TRUE,
        dotall = TRUE
      )

      numOfPathways <- keggText %>%
        stringr::str_extract(keggRegex) %>%
        stringr::str_count("\n")

      return(ifelse(is.na(numOfPathways), 0L, as.integer(numOfPathways)))
    },

    #' @description
    #' Enrich a data table with KEGG pathway counts.
    #' Requires UniProtData column with KEGG IDs from UniProt provider.
    #' @param dataTable Input data.frame with UniProtData column.
    #' @return Enriched data.frame with NumberOfKEGGPathways column.
    enrich = function(dataTable) {
      if (!"UniProtData" %in% names(dataTable)) {
        warning("KEGG :: dataTable must have UniProtData column (from UniProt provider)")
        return(dataTable)
      }

      # Get unique UniProt data entries
      uniProtList <- dataTable %>%
        dplyr::select(UniProtData) %>%
        dplyr::distinct() %>%
        dplyr::pull(1)

      # Build cache of pathway counts
      keggCache <- list()
      for (uniProtData in uniProtList) {
        count <- 0L
        if (!is.null(uniProtData) && hasName(uniProtData, "KEGG")) {
          keggId <- uniProtData$KEGG
          keggText <- self$fetchCached(keggId)
          count <- self$countPathways(keggText)
        }
        # Use list representation as key
        key <- paste(names(uniProtData), collapse = "_")
        keggCache[[key]] <- count
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::rowwise() %>%
        dplyr::mutate(
          NumberOfKEGGPathways = {
            key <- paste(names(UniProtData), collapse = "_")
            keggCache[[key]]
          }
        )

      return(dataTable)
    },

    #' @description
    #' Enrich using pre-computed UniProt data.
    #' @param dataTable Input data.frame with UNIPROT_KB_ID column.
    #' @param uniProtDataList Named list of UniProt data by ID.
    #' @return Enriched data.frame with NumberOfKEGGPathways column.
    enrichFromUniProtData = function(dataTable, uniProtDataList) {
      # Build cache
      keggCache <- list()
      for (id in names(uniProtDataList)) {
        uniProtData <- uniProtDataList[[id]]
        count <- 0L
        if (!is.null(uniProtData) && hasName(uniProtData, "KEGG")) {
          keggId <- uniProtData$KEGG
          keggText <- self$fetchCached(keggId)
          count <- self$countPathways(keggText)
        }
        keggCache[[id]] <- count
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::rowwise() %>%
        dplyr::mutate(
          NumberOfKEGGPathways = keggCache[[UNIPROT_KB_ID]]
        )

      return(dataTable)
    },

    #' @description
    #' Get output column names.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      return(c("NumberOfKEGGPathways"))
    },

    #' @description
    #' Get KEGG entry URL for a gene ID.
    #' @param keggId KEGG gene ID.
    #' @return URL string.
    getEntryUrl = function(keggId) {
      return(glue::glue("https://www.kegg.jp/entry/{keggId}"))
    },

    #' @description
    #' Validate provider configuration.
    #' @return TRUE if valid, FALSE otherwise.
    validate = function() {
      if (!super$validate()) {
        return(FALSE)
      }

      # Test connectivity with a known gene
      tryCatch({
        result <- self$fetch("hsa:7157")  # TP53
        return(!is.na(result))
      }, error = function(e) {
        warning(paste0("KEGG validation failed: ", e$message))
        return(FALSE)
      })
    }
  )
)


#' Create a configured KEGGProvider instance
#'
#' @param sleepTime Delay between requests in seconds.
#' @param cache Optional CacheManager instance.
#' @return Configured KEGGProvider instance.
#' @export
createKEGGProvider <- function(sleepTime = 5, cache = NULL) {
  KEGGProvider$new(
    cache = cache,
    config = list(sleepTime = sleepTime)
  )
}
