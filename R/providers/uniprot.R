##
## uniprot.R: UniProt data provider
##
## Fetches protein annotations from UniProt XML API including:
## - GO terms (molecular function, biological process, cellular component)
## - Cross-references (STRING, KEGG, Reactome)
##

source("R/providers/base.R")

library(dplyr)
library(xml2)
library(glue)

#' UniProtProvider Class
#'
#' Provider for fetching protein annotation data from UniProt.
#' Extracts GO terms and database cross-references from UniProt XML.
#'
#' @export
UniProtProvider <- R6::R6Class(
  "UniProtProvider",
  inherit = ProteinProvider,
  public = list(
    #' @field baseUrl Base URL for UniProt XML API.
    baseUrl = "https://rest.uniprot.org/uniprotkb/{id}.xml",

    #' @field sleepTime Delay between requests in seconds.
    sleepTime = 5,

    #' @field sleepTimeOnCacheHit Reduced delay when cache hit.
    sleepTimeOnCacheHit = 2,

    #' @description
    #' Initialize UniProtProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - baseUrl: Override default UniProt URL template
    #'   - sleepTime: Delay between requests
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "UniProt", cache = cache, config = config)

      if (!is.null(config$baseUrl)) {
        self$baseUrl <- config$baseUrl
      }
      if (!is.null(config$sleepTime)) {
        self$sleepTime <- config$sleepTime
      }
    },

    #' @description
    #' Fetch UniProt data for a protein.
    #' @param query Query parameters. Accepts:
    #'   - List with 'uniprot_id' key
    #'   - Character string with UniProt accession
    #' @return List with extracted protein annotations.
    fetch = function(query) {
      # Normalize query
      uniprotId <- if (is.list(query) && !is.null(query$uniprot_id)) {
        query$uniprot_id
      } else if (is.character(query) && length(query) == 1) {
        query
      } else {
        stop("Query must be a UniProt ID string or list with 'uniprot_id' key")
      }

      # Build URL
      url <- glue::glue(self$baseUrl, id = uniprotId)

      # Fetch XML
      tryCatch({
        Sys.sleep(self$sleepTime)
        xmlDoc <- xml2::read_xml(url)
        return(private$parseXML(xmlDoc))
      }, error = function(e) {
        warning(paste0("UniProt :: Failed to fetch ", uniprotId, ": ", e$message))
        return(private$emptyResult())
      })
    },

    #' @description
    #' Enrich a data table with UniProt annotations.
    #' @param dataTable Input data.frame with UNIPROT_KB_ID column.
    #' @return Enriched data.frame with UniProtData column.
    enrich = function(dataTable) {
      if (!"UNIPROT_KB_ID" %in% names(dataTable)) {
        warning("UniProt :: dataTable must have UNIPROT_KB_ID column")
        return(dataTable)
      }

      # Get unique UniProt IDs
      uniprotIds <- dataTable %>%
        dplyr::select(UNIPROT_KB_ID) %>%
        dplyr::distinct() %>%
        dplyr::filter(!is.na(UNIPROT_KB_ID)) %>%
        dplyr::pull(UNIPROT_KB_ID)

      # Fetch data for each ID
      uniprotData <- list()
      for (id in uniprotIds) {
        uniprotData[[id]] <- self$fetchCached(id)
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::rowwise() %>%
        dplyr::mutate(UniProtData = list(uniprotData[[UNIPROT_KB_ID]]))

      return(dataTable)
    },

    #' @description
    #' Get output column names.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      return(c("UniProtData"))
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
        result <- self$fetch("P53_HUMAN")
        return(!is.null(result))
      }, error = function(e) {
        warning(paste0("UniProt validation failed: ", e$message))
        return(FALSE)
      })
    }
  ),

  private = list(
    #' Parse UniProt XML response
    #' @param xmlDoc XML document from UniProt.
    #' @return List with extracted annotations.
    parseXML = function(xmlDoc) {
      root <- xml2::xml_root(xmlDoc)

      # XPath for database references
      xpath <- paste0(
        # GO functional (F:) references
        "//dbReference[@type='GO']",
          "//property[@type='term'][starts-with(@value, 'F:')]",
          "/parent::node()",

        # GO cellular components (C:) references
        " | //dbReference[@type='GO']",
          "//property[@type='term'][starts-with(@value, 'C:')]",
          "/parent::node()",

        # GO biological process (P:) references
        " | //dbReference[@type='GO']",
          "//property[@type='term'][starts-with(@value, 'P:')]",
          "/parent::node()",

        # STRING, Reactome or KEGG references
        " | //dbReference[@type='STRING' or @type='Reactome' or @type='KEGG']"
      )

      dbReferences <- xml2::xml_find_all(x = root, xpath = xpath)

      # Initialize result structure
      result <- list(
        molecularFunction = NULL,
        subCellularLocation = NULL,
        biologicalProcess = NULL,
        Reactome = list(),
        STRING = NULL,
        KEGG = NULL
      )

      # Process each reference
      for (dbref in dbReferences) {
        type <- xml2::xml_attr(dbref, "type")
        referenceId <- xml2::xml_attr(dbref, "id")

        if (type == "STRING") {
          result[["STRING"]] <- referenceId
        } else if (type == "KEGG") {
          result[["KEGG"]] <- referenceId
        } else if (type == "Reactome") {
          pathway <- xml2::xml_find_first(dbref, ".//property[@type='pathway name']") %>%
            xml2::xml_attr(attr = "value")
          result$Reactome[[referenceId]] <- pathway
        } else if (type == "GO") {
          termValue <- xml2::xml_find_first(dbref, ".//property[@type='term']") %>%
            xml2::xml_attr(attr = "value")

          termType <- private$getGOTermType(termValue)
          newItem <- c(substring(termValue, 3))
          names(newItem) <- referenceId
          result[[termType]] <- c(result[[termType]], newItem)
        }
      }

      return(result)
    },

    #' Determine GO term type from value prefix
    #' @param termValue GO term value string.
    #' @return Term type: "molecularFunction", "biologicalProcess", or "subCellularLocation".
    getGOTermType = function(termValue) {
      if (startsWith(termValue, "F:")) {
        return("molecularFunction")
      } else if (startsWith(termValue, "C:")) {
        return("subCellularLocation")
      } else if (startsWith(termValue, "P:")) {
        return("biologicalProcess")
      } else {
        stop(paste0("Unexpected GO term prefix: ", termValue))
      }
    },

    #' Return empty result structure
    #' @return List with NULL values.
    emptyResult = function() {
      return(list(
        molecularFunction = NULL,
        subCellularLocation = NULL,
        biologicalProcess = NULL,
        Reactome = list(),
        STRING = NULL,
        KEGG = NULL
      ))
    }
  )
)


#' Create a configured UniProtProvider instance
#'
#' @param sleepTime Delay between requests in seconds.
#' @param cache Optional CacheManager instance.
#' @return Configured UniProtProvider instance.
#' @export
createUniProtProvider <- function(sleepTime = 5, cache = NULL) {
  UniProtProvider$new(
    cache = cache,
    config = list(sleepTime = sleepTime)
  )
}
