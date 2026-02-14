##
## pubmed.R: PubMed data provider
##
## Fetches clinical trial and review article references from PubMed.
## Searches for compound names with specific publication type filters.
##

source("R/providers/base.R")

library(dplyr)
library(rvest)
library(stringr)
library(glue)

#' PubMedProvider Class
#'
#' Provider for fetching clinical trial references from PubMed.
#' Searches with filters for clinical trials, reviews, and meta-analyses.
#'
#' @export
PubMedProvider <- R6::R6Class(
  "PubMedProvider",
  inherit = CompoundProvider,
  public = list(
    #' @field baseUrl PubMed base URL.
    baseUrl = "https://pubmed.ncbi.nlm.nih.gov/",

    #' @field searchFilters Publication type filters.
    searchFilters = c(
      "&filter=pubt.clinicaltrial",
      "&filter=pubt.meta-analysis",
      "&filter=pubt.randomizedcontrolledtrial",
      "&filter=pubt.review",
      "&filter=pubt.systematicreview"
    ),

    #' @field maxResults Maximum results to request.
    maxResults = 200,

    #' @field displayMaxLinks Maximum links to display per compound.
    displayMaxLinks = 3,

    #' @field sleepTime Delay between requests in seconds.
    sleepTime = 30,

    #' @description
    #' Initialize PubMedProvider.
    #' @param cache Optional CacheManager instance.
    #' @param config Configuration options. May include:
    #'   - sleepTime: Delay between requests
    #'   - maxResults: Max results to fetch
    #'   - displayMaxLinks: Max links to show
    initialize = function(cache = NULL, config = list()) {
      super$initialize(name = "PubMed", cache = cache, config = config)

      if (!is.null(config$sleepTime)) {
        self$sleepTime <- config$sleepTime
      }
      if (!is.null(config$maxResults)) {
        self$maxResults <- config$maxResults
      }
      if (!is.null(config$displayMaxLinks)) {
        self$displayMaxLinks <- config$displayMaxLinks
      }
    },

    #' @description
    #' Build PubMed search URL for a compound.
    #' @param compound Compound name to search.
    #' @return URL string.
    buildSearchUrl = function(compound) {
      filterString <- paste(self$searchFilters, collapse = "")
      return(paste0(
        self$baseUrl,
        "?term=", URLencode(compound),
        "&size=", self$maxResults,
        filterString
      ))
    },

    #' @description
    #' Fetch PubMed references for a compound.
    #' @param query Query parameters. Accepts:
    #'   - List with 'compound' key
    #'   - Character string with compound name
    #' @return Character vector of PubMed article IDs (PMIDs).
    fetch = function(query) {
      # Normalize query
      compoundName <- if (is.list(query) && !is.null(query$compound)) {
        query$compound
      } else if (is.character(query) && length(query) == 1) {
        query
      } else {
        stop("Query must be a compound name string or list with 'compound' key")
      }

      searchUrl <- self$buildSearchUrl(compoundName)

      tryCatch({
        Sys.sleep(self$sleepTime)

        # Download search results page
        htmlDoc <- rvest::read_html(searchUrl)

        # Extract article IDs from meta tag
        xpath <- 'string(/html/head/meta[@name = "log_displayeduids"]/@content)'
        idsString <- htmlDoc %>%
          rvest::html_element(xpath = xpath)

        # Parse comma-separated IDs
        articleIds <- idsString %>%
          stringr::str_split(pattern = ",") %>%
          unlist()

        # Return NULL for empty results
        if (length(articleIds) == 1 && articleIds[1] == "") {
          return(NULL)
        }

        return(articleIds)
      }, error = function(e) {
        warning(paste0("PubMed :: Failed to fetch ", compoundName, ": ", e$message))
        return(NULL)
      })
    },

    #' @description
    #' Enrich a data table with PubMed references.
    #' @param dataTable Input data.frame with pert_iname column.
    #' @return Enriched data.frame with pubMedPreClinicalLinks and PubMedCounter columns.
    enrich = function(dataTable) {
      if (!"pert_iname" %in% names(dataTable)) {
        warning("PubMed :: dataTable must have pert_iname column")
        return(dataTable)
      }

      # Get unique compound names
      compoundList <- dataTable %>%
        dplyr::select(pert_iname) %>%
        dplyr::distinct() %>%
        dplyr::filter(!is.na(pert_iname)) %>%
        dplyr::pull(pert_iname)

      # Fetch data for each compound
      pubmedResults <- list()
      for (compound in compoundList) {
        pubmedResults[[compound]] <- self$fetchCached(compound)
      }

      # Add to table
      dataTable <- dataTable %>%
        dplyr::mutate(
          pubMedPreClinicalLinks = list(pubmedResults[[pert_iname]]),
          PubMedCounter = length(unlist(pubMedPreClinicalLinks))
        )

      return(dataTable)
    },

    #' @description
    #' Get output column names.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      return(c("pubMedPreClinicalLinks", "PubMedCounter"))
    },

    #' @description
    #' Get PubMed article URL for a PMID.
    #' @param pmid PubMed article ID.
    #' @return URL string.
    getArticleUrl = function(pmid) {
      return(paste0(self$baseUrl, pmid))
    },

    #' @description
    #' Format PMIDs as HTML links.
    #' @param pmids Character vector of PMIDs.
    #' @param compound Compound name for search link fallback.
    #' @return HTML string with links.
    formatAsHtml = function(pmids, compound) {
      title <- "<strong>From PubMed:</strong>"

      if (is.null(pmids) || all(is.na(pmids))) {
        searchUrl <- self$buildSearchUrl(compound)
        searchLink <- glue::glue('<a href="{searchUrl}" target="_blank">No search result</a>')
        return(paste(c(title, searchLink), collapse = "<br />"))
      }

      # Limit to display max
      pmids <- head(pmids, n = self$displayMaxLinks)

      links <- sapply(pmids, function(pmid) {
        url <- self$getArticleUrl(pmid)
        return(glue::glue('<a href="{url}" target="_blank">PubMed {pmid}</a>'))
      })

      return(paste(c(title, links), collapse = "<br />"))
    }
  )
)


#' Create a configured PubMedProvider instance
#'
#' @param sleepTime Delay between requests in seconds.
#' @param cache Optional CacheManager instance.
#' @return Configured PubMedProvider instance.
#' @export
createPubMedProvider <- function(sleepTime = 30, cache = NULL) {
  PubMedProvider$new(
    cache = cache,
    config = list(sleepTime = sleepTime)
  )
}
