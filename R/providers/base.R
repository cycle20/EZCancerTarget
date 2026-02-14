##
## base.R: Base class for data providers
##
## This module defines the abstract DataProvider interface that all
## data providers must implement.
##

library(R6)

#' DataProvider Base Class
#'
#' Abstract base class defining the interface for all data providers.
#' Each provider fetches data from a specific source (API, file, database)
#' and returns it in a standardized format.
#'
#' @field name Character string identifying the provider.
#' @field cache Reference to a CacheManager instance (optional).
#' @field config List of provider-specific configuration options.
#'
#' @export
DataProvider <- R6::R6Class(
  "DataProvider",
  public = list(
    #' @field name Provider name for identification and logging.
    name = NULL,

    #' @field cache Optional cache manager instance.
    cache = NULL,

    #' @field config Provider-specific configuration.
    config = list(),

    #' @description
    #' Initialize a new DataProvider.
    #' @param name Character string identifying the provider.
    #' @param cache Optional CacheManager instance.
    #' @param config List of provider-specific configuration options.
    initialize = function(name, cache = NULL, config = list()) {
      self$name <- name
      self$cache <- cache
      self$config <- config
    },

    #' @description
    #' Get the provider name.
    #' @return Character string with provider name.
    getName = function() {
      return(self$name)
    },

    #' @description
    #' Fetch data from the provider source.
    #' This method must be implemented by subclasses.
    #' @param query Query parameters (provider-specific).
    #' @return Data in provider-specific format.
    fetch = function(query) {
      stop(paste0(
        "fetch() must be implemented by subclass: ",
        class(self)[1]
      ))
    },

    #' @description
    #' Fetch data for multiple queries (batch operation).
    #' Default implementation calls fetch() for each query.
    #' Subclasses may override for more efficient batch operations.
    #' @param queries List of query parameters.
    #' @return List of results keyed by query identifier.
    fetchBatch = function(queries) {
      results <- list()
      for (i in seq_along(queries)) {
        query <- queries[[i]]
        key <- if (!is.null(names(queries))) {
          names(queries)[i]
        } else {
          as.character(i)
        }
        results[[key]] <- tryCatch(
          self$fetch(query),
          error = function(e) {
            warning(paste0(
              self$name, " :: Error fetching query '", key, "': ", e$message
            ))
            return(NULL)
          }
        )
      }
      return(results)
    },

    #' @description
    #' Validate provider configuration and connectivity.
    #' Subclasses should override to perform provider-specific validation.
    #' @return TRUE if validation passes, FALSE otherwise.
    validate = function() {
      if (is.null(self$name) || nchar(self$name) == 0) {
        warning("Provider name is not set")
        return(FALSE)
      }
      return(TRUE)
    },

    #' @description
    #' Transform raw fetched data into a standardized format.
    #' Subclasses should override to perform provider-specific transformation.
    #' @param rawData Raw data from fetch().
    #' @return Transformed data.
    transform = function(rawData) {
      return(rawData)
    },

    #' @description
    #' Get a cache key for a given query.
    #' @param query Query parameters.
    #' @return Character string cache key.
    getCacheKey = function(query) {
      queryStr <- if (is.list(query)) {
        paste(names(query), unlist(query), sep = "=", collapse = "&")
      } else {
        as.character(query)
      }
      return(paste0(self$name, ":", queryStr))
    },

    #' @description
    #' Fetch data with caching support.
    #' @param query Query parameters.
    #' @param forceRefresh If TRUE, bypass cache and fetch fresh data.
    #' @return Cached or freshly fetched data.
    fetchCached = function(query, forceRefresh = FALSE) {
      if (is.null(self$cache)) {
        return(self$fetch(query))
      }

      cacheKey <- self$getCacheKey(query)

      if (!forceRefresh) {
        cached <- self$cache$get(cacheKey)
        if (!is.null(cached)) {
          return(cached)
        }
      }

      result <- self$fetch(query)
      self$cache$set(cacheKey, result)
      return(result)
    },

    #' @description
    #' Print provider information.
    print = function() {
      cat(paste0("<DataProvider: ", self$name, ">\n"))
      cat(paste0("  Cache: ", ifelse(is.null(self$cache), "disabled", "enabled"), "\n"))
      cat(paste0("  Config keys: ", paste(names(self$config), collapse = ", "), "\n"))
    }
  )
)


#' EnrichmentProvider Base Class
#'
#' Specialized provider for enriching existing data tables.
#' Extends DataProvider with methods for table enrichment.
#'
#' @export
EnrichmentProvider <- R6::R6Class(
  "EnrichmentProvider",
  inherit = DataProvider,
  public = list(
    #' @description
    #' Enrich a data table with additional information.
    #' This method must be implemented by subclasses.
    #' @param dataTable Input data.frame or tibble.
    #' @return Enriched data.frame with additional columns.
    enrich = function(dataTable) {
      stop(paste0(
        "enrich() must be implemented by subclass: ",
        class(self)[1]
      ))
    },

    #' @description
    #' Get the list of column names this provider adds.
    #' @return Character vector of column names.
    getOutputColumns = function() {
      stop(paste0(
        "getOutputColumns() must be implemented by subclass: ",
        class(self)[1]
      ))
    }
  )
)


#' CompoundProvider Base Class
#'
#' Specialized provider for fetching compound/drug information.
#' Extends DataProvider with compound-specific methods.
#'
#' @export
CompoundProvider <- R6::R6Class(
  "CompoundProvider",
  inherit = EnrichmentProvider,
  public = list(
    #' @description
    #' Fetch data for a single compound.
    #' @param compoundName Character string with compound name.
    #' @return Compound data in provider-specific format.
    fetchByCompound = function(compoundName) {
      return(self$fetch(list(compound = compoundName)))
    },

    #' @description
    #' Fetch data for multiple compounds.
    #' @param compoundNames Character vector of compound names.
    #' @return Named list of results keyed by compound name.
    fetchByCompounds = function(compoundNames) {
      queries <- as.list(compoundNames)
      names(queries) <- compoundNames
      return(self$fetchBatch(queries))
    }
  )
)


#' ProteinProvider Base Class
#'
#' Specialized provider for fetching protein/target information.
#' Extends DataProvider with protein-specific methods.
#'
#' @export
ProteinProvider <- R6::R6Class(
  "ProteinProvider",
  inherit = EnrichmentProvider,
  public = list(
    #' @description
    #' Fetch data for a single protein by UniProt ID.
    #' @param uniprotId Character string with UniProt accession.
    #' @return Protein data in provider-specific format.
    fetchByUniprot = function(uniprotId) {
      return(self$fetch(list(uniprot_id = uniprotId)))
    },

    #' @description
    #' Fetch data for multiple proteins.
    #' @param uniprotIds Character vector of UniProt accessions.
    #' @return Named list of results keyed by UniProt ID.
    fetchByUniprots = function(uniprotIds) {
      queries <- as.list(uniprotIds)
      names(queries) <- uniprotIds
      return(self$fetchBatch(queries))
    }
  )
)
