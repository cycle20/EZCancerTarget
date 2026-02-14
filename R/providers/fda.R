##
## fda.R: FDA Label data provider
##
## Fetches drug label information from FDA's FDALabel API.
## Searches for prescription and OTC drug labels by compound name.
##

source("R/providers/base.R")

library(dplyr)
library(httr)
library(jsonlite)
library(stringr)
library(glue)

#' FDALabelProvider Class
#'
#' Provider for fetching drug label information from FDA's FDALabel API.
#' Searches for Human Rx, Human OTC, and Vaccine labels.
#'
#' @export
FDALabelProvider <- R6::R6Class(
  "FDALabelProvider",
  inherit = CompoundProvider,
  public = list(
    #' @field apiUrl FDA Label API endpoint.
    apiUrl = "https://nctr-crs.fda.gov/fdalabel/services/spl/summaries",

    #' @field sleepTime Delay between requests in seconds.
    sleepTime = 30,

    #' @field ingredientFilter Whether to use strict ingredient filtering.
    ingredientFilter = FALSE,

    #' @description
    #' Initialize FDALabelProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - apiUrl: Override default FDA API URL
    #'   - sleepTime: Delay between requests
    #'   - ingredientFilter: Enable strict ingredient filtering
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "FDALabel", cache = cache, config = config)

      if (!is.null(config$apiUrl)) {
        self$apiUrl <- config$apiUrl
      }
      if (!is.null(config$sleepTime)) {
        self$sleepTime <- config$sleepTime
      }
      if (!is.null(config$ingredientFilter)) {
        self$ingredientFilter <- config$ingredientFilter
      }
    },

    #' @description
    #' Fetch FDA label data for a compound.
    #' @param query Query parameters. Accepts:
    #'   - List with 'compound' key
    #'   - Character string with compound name
    #' @return List with pert_iname and productsTable.
    fetch = function(query) {
      # Normalize query
      compoundName <- if (is.list(query) && !is.null(query$compound)) {
        query$compound
      } else if (is.character(query) && length(query) == 1) {
        query
      } else {
        stop("Query must be a compound name string or list with 'compound' key")
      }

      # Build POST request body
      postData <- private$buildPostData(compoundName)

      # Execute request
      tryCatch({
        Sys.sleep(self$sleepTime)

        response <- httr::POST(
          self$apiUrl,
          body = postData,
          config = httr::add_headers(
            "Content-Type" = "application/json; charset=UTF-8",
            "Accept" = "application/json"
          )
        )
        responseContent <- httr::content(response, as = "text", encoding = "UTF-8")
        return(private$parseResponse(responseContent, compoundName))
      }, error = function(e) {
        warning(paste0("FDALabel :: Failed to fetch ", compoundName, ": ", e$message))
        return(private$emptyResult())
      })
    },

    #' @description
    #' Enrich a data table with FDA label links.
    #' @param dataTable Input data.frame with pert_iname column.
    #' @return Enriched data.frame with fdaSearchResults column.
    enrich = function(dataTable) {
      if (!"pert_iname" %in% names(dataTable)) {
        warning("FDALabel :: dataTable must have pert_iname column")
        return(dataTable)
      }

      # Get unique compound names
      compoundList <- dataTable %>%
        dplyr::select(pert_iname) %>%
        dplyr::distinct() %>%
        dplyr::filter(!is.na(pert_iname)) %>%
        dplyr::pull(pert_iname)

      # Fetch data for each compound
      fdaResults <- list()
      for (compound in compoundList) {
        fdaResults[[compound]] <- self$fetchCached(compound)
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::mutate(fdaSearchResults = fdaResults[pert_iname])

      return(dataTable)
    },

    #' @description
    #' Get output column names.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      return(c("fdaSearchResults"))
    },

    #' @description
    #' Get FDA Label URL for a specific setId.
    #' @param setId FDA Label set ID.
    #' @return URL string.
    getLabelUrl = function(setId) {
      return(glue::glue(
        "https://nctr-crs.fda.gov/fdalabel/services/spl/set-ids/{setId}/spl-doc"
      ))
    }
  ),

  private = list(
    #' Build POST request body for FDA API
    #' @param compoundName Compound name to search.
    #' @return JSON string for POST body.
    buildPostData = function(compoundName) {
      if (!self$ingredientFilter) {
        # Search by product name
        postData <- paste0(
          '{"criteria":[{',
          '"criteria": [',
            '{"sourceEntity": "document-type",',
            '"documentTypeCodes": ["34391-3", "34390-5", "53404-0"]},',
            '{"sourceEntity": "product",',
            '"nameType": "ANY",',
            '"namePatternType": "SUBSTR",',
            '"namePattern": "', compoundName, '"}',
          '],',
          '"logOps": ["a","a"]',
          '}],"logOps":[]}'
        )
      } else {
        # Search by active ingredient
        postData <- paste0(
          '{"criteria":[{"criteria":[',
          '{"sourceEntity":"document-type","documentTypeCodes":',
          '["34391-3","34390-5","53404-0"]},{"sourceEntity":"section",',
          '"textQuery":"', compoundName,
          '","selectedLabelingType":"0","sectionTypeCode":"2-55106-9",',
          '"advanced":false}],"logOps":["a","a"]}],"logOps":[]}'
        )
      }

      # Remove whitespace
      return(stringr::str_remove_all(postData, "[[:space:]]"))
    },

    #' Parse FDA API response
    #' @param responseContent JSON response content.
    #' @param compoundName Original compound name searched.
    #' @return List with pert_iname and productsTable.
    parseResponse = function(responseContent, compoundName) {
      emptyList <- private$emptyResult()

      parsedResult <- jsonlite::fromJSON(responseContent)

      if (parsedResult$totalResultsCount == 0) {
        message(paste0("FDALabel :: ", compoundName, " :: no results found"))
        return(emptyList)
      }

      # Filter results
      products <- parsedResult$resultsArray %>%
        dplyr::filter(
          !any(grepl("first aid", productNames, ignore.case = TRUE)) &
          !any(grepl(" kit", productNames, ignore.case = TRUE)) &
          !any(grepl("KIT", dosageForms))
        )

      if (nrow(products) == 0) {
        message(paste0("FDALabel :: ", compoundName, " :: no results after filtering"))
        return(emptyList)
      }

      # Calculate ingredient match level
      products <- products %>%
        dplyr::mutate(
          matchLevel = private$ingredientsMatchLevel(compoundName, actIngrNames),
          ingrLength = private$ingrLength(actIngrUniis)
        ) %>%
        dplyr::filter(matchLevel < 5) %>%
        dplyr::group_by(matchLevel, ingrLength)

      if (nrow(products) == 0) {
        message(paste0("FDALabel :: ", compoundName, " :: no matching ingredients"))
        return(emptyList)
      }

      # Select best matches
      products <- products %>%
        dplyr::filter(!is.na(marketDates)) %>%
        dplyr::filter(marketDates == max(marketDates)) %>%
        dplyr::ungroup() %>%
        dplyr::arrange(matchLevel, ingrLength)

      productsTable <- products %>%
        dplyr::select(productNames, setId)

      return(list(
        pert_iname = compoundName,
        productsTable = productsTable
      ))
    },

    #' Calculate ingredient match level
    #' @param compoundName Compound name to match.
    #' @param ingrList Ingredient list string (semicolon-separated).
    #' @return Integer match level (1-5, lower is better).
    ingredientsMatchLevel = function(compoundName, ingrList) {
      sapply(ingrList, function(ingredients) {
        ingr <- ingredients %>%
          stringr::str_to_upper() %>%
          stringr::str_split(pattern = "; *") %>%
          unlist()

        compound <- stringr::str_to_upper(compoundName)

        if (compound %in% ingr) {
          return(1L)  # exact match
        } else if (any(stringr::str_starts(ingr, compound))) {
          return(2L)  # starts with
        } else if (any(stringr::str_ends(ingr, compound))) {
          return(3L)  # ends with
        } else if (any(grepl(compound, ingr))) {
          return(4L)  # contains
        } else {
          return(5L)  # no match
        }
      })
    },

    #' Count number of ingredients
    #' @param actIngrUniis Ingredient UNIIs string (semicolon-separated).
    #' @return Integer count.
    ingrLength = function(actIngrUniis) {
      sapply(actIngrUniis, function(uniis) {
        parts <- uniis %>%
          stringr::str_to_upper() %>%
          stringr::str_split(pattern = "; *") %>%
          unlist()
        return(length(parts))
      })
    },

    #' Return empty result structure
    #' @return List with NA values.
    emptyResult = function() {
      return(list(pert_iname = NA, productsTable = NA))
    }
  )
)


#' Create a configured FDALabelProvider instance
#'
#' @param sleepTime Delay between requests in seconds.
#' @param ingredientFilter Use strict ingredient filtering.
#' @param cache Optional CacheManager instance.
#' @return Configured FDALabelProvider instance.
#' @export
createFDALabelProvider <- function(sleepTime = 30, ingredientFilter = FALSE, cache = NULL) {
  FDALabelProvider$new(
    cache = cache,
    config = list(
      sleepTime = sleepTime,
      ingredientFilter = ingredientFilter
    )
  )
}
