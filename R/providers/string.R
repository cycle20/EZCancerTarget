##
## string.R: STRING database provider
##
## Fetches protein-protein interaction data from STRING-db.
## Counts high-confidence interaction partners for target proteins.
##

source("R/providers/base.R")

library(dplyr)
library(httr)
library(glue)

#' STRINGProvider Class
#'
#' Provider for fetching protein interaction data from STRING-db.
#' Counts interaction partners with high confidence scores.
#'
#' @export
STRINGProvider <- R6::R6Class(
  "STRINGProvider",
  inherit = ProteinProvider,
  public = list(
    #' @field apiUrl STRING API endpoint.
    apiUrl = "https://string-db.org/api/tsv/interaction_partners",

    #' @field species NCBI taxonomy ID for human.
    species = 9606,

    #' @field requiredScore Minimum confidence score (0-1000).
    requiredScore = 900,

    #' @field limit Maximum number of interactors (0 = unlimited).
    limit = 0,

    #' @field sleepTime Delay between requests in seconds.
    sleepTime = 5,

    #' @description
    #' Initialize STRINGProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - species: NCBI taxonomy ID
    #'   - requiredScore: Minimum confidence score
    #'   - sleepTime: Delay between requests
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "STRING", cache = cache, config = config)

      if (!is.null(config$species)) {
        self$species <- config$species
      }
      if (!is.null(config$requiredScore)) {
        self$requiredScore <- config$requiredScore
      }
      if (!is.null(config$sleepTime)) {
        self$sleepTime <- config$sleepTime
      }
    },

    #' @description
    #' Build STRING API URL for a protein identifier.
    #' @param stringId STRING protein identifier.
    #' @return URL string.
    buildApiUrl = function(stringId) {
      return(glue::glue(
        "{self$apiUrl}?identifiers={stringId}&species={self$species}",
        "&limit={self$limit}&required_score={self$requiredScore}"
      ))
    },

    #' @description
    #' Fetch STRING interaction data for a protein.
    #' @param query Query parameters. Accepts:
    #'   - List with 'string_id' key
    #'   - Character string with STRING identifier
    #' @return Data frame with interaction partners.
    fetch = function(query) {
      # Normalize query
      stringId <- if (is.list(query) && !is.null(query$string_id)) {
        query$string_id
      } else if (is.character(query) && length(query) == 1) {
        query
      } else {
        stop("Query must be a STRING ID string or list with 'string_id' key")
      }

      url <- self$buildApiUrl(stringId)

      tryCatch({
        Sys.sleep(self$sleepTime)

        response <- httr::GET(url)
        result <- httr::content(response)

        return(result)
      }, error = function(e) {
        warning(paste0("STRING :: Failed to fetch ", stringId, ": ", e$message))
        return(NA)
      })
    },

    #' @description
    #' Count interaction partners for a protein.
    #' @param stringId STRING protein identifier.
    #' @return Integer count of interactors.
    countInteractors = function(stringId) {
      result <- self$fetchCached(stringId)

      if (tibble::is_tibble(result)) {
        return(nrow(result))
      }
      return(0L)
    },

    #' @description
    #' Enrich a data table with STRING interactor counts.
    #' Requires UniProtData column with STRING IDs from UniProt provider.
    #' @param dataTable Input data.frame with UniProtData column.
    #' @return Enriched data.frame with NumberOfSTRINGInteractors column.
    enrich = function(dataTable) {
      if (!"UniProtData" %in% names(dataTable)) {
        warning("STRING :: dataTable must have UniProtData column (from UniProt provider)")
        return(dataTable)
      }

      # Get unique UniProt data entries
      uniProtList <- dataTable %>%
        dplyr::select(UniProtData) %>%
        dplyr::distinct() %>%
        dplyr::pull(1)

      # Build cache of interactor counts
      interactorsCache <- list()
      for (uniProtData in uniProtList) {
        count <- 0L
        if (!is.null(uniProtData) && hasName(uniProtData, "STRING")) {
          stringId <- uniProtData$STRING
          result <- self$fetchCached(stringId)
          if (tibble::is_tibble(result)) {
            count <- nrow(result)
          }
        }
        # Use list representation as key
        key <- paste(names(uniProtData), collapse = "_")
        interactorsCache[[key]] <- count
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::rowwise() %>%
        dplyr::mutate(
          NumberOfSTRINGInteractors = {
            key <- paste(names(UniProtData), collapse = "_")
            interactorsCache[[key]]
          }
        )

      return(dataTable)
    },

    #' @description
    #' Enrich using pre-computed UniProt data.
    #' @param dataTable Input data.frame with UNIPROT_KB_ID column.
    #' @param uniProtDataList Named list of UniProt data by ID.
    #' @return Enriched data.frame with NumberOfSTRINGInteractors column.
    enrichFromUniProtData = function(dataTable, uniProtDataList) {
      # Build cache
      interactorsCache <- list()
      for (id in names(uniProtDataList)) {
        uniProtData <- uniProtDataList[[id]]
        count <- 0L
        if (!is.null(uniProtData) && hasName(uniProtData, "STRING")) {
          stringId <- uniProtData$STRING
          result <- self$fetchCached(stringId)
          if (tibble::is_tibble(result)) {
            count <- nrow(result)
          }
        }
        interactorsCache[[id]] <- count
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::rowwise() %>%
        dplyr::mutate(
          NumberOfSTRINGInteractors = interactorsCache[[UNIPROT_KB_ID]]
        )

      return(dataTable)
    },

    #' @description
    #' Get output column names.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      return(c("NumberOfSTRINGInteractors"))
    },

    #' @description
    #' Validate provider configuration.
    #' @return TRUE if valid, FALSE otherwise.
    validate = function() {
      if (!super$validate()) {
        return(FALSE)
      }

      # Test connectivity with a known protein
      tryCatch({
        result <- self$fetch("TP53")
        return(!is.null(result))
      }, error = function(e) {
        warning(paste0("STRING validation failed: ", e$message))
        return(FALSE)
      })
    }
  )
)


#' Create a configured STRINGProvider instance
#'
#' @param requiredScore Minimum confidence score (0-1000).
#' @param sleepTime Delay between requests in seconds.
#' @param cache Optional CacheManager instance.
#' @return Configured STRINGProvider instance.
#' @export
createSTRINGProvider <- function(requiredScore = 900, sleepTime = 5, cache = NULL) {
  STRINGProvider$new(
    cache = cache,
    config = list(
      requiredScore = requiredScore,
      sleepTime = sleepTime
    )
  )
}
