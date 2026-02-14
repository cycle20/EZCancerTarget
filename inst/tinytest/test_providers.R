##
## test_providers.R: Provider contract tests
##
## Tests for the provider interface and implementations.
## Uses tinytest framework following project conventions.
##

library(tinytest)
library(stringr)
library(dplyr)

setwd('../..')
source("R/providers/base.R")
source("R/cache.R")


## =============================================================================
## DataProvider Base Class Tests
## =============================================================================

## test DataProvider initialization
test_base_provider_init <- function() {
  provider <- DataProvider$new(name = "TestProvider")

  expect_equal(provider$getName(), "TestProvider")
  expect_null(provider$cache)
  expect_true(is.list(provider$config))
}
test_base_provider_init()


## test DataProvider validation
test_base_provider_validate <- function() {
  provider <- DataProvider$new(name = "TestProvider")
  expect_true(provider$validate())

  emptyProvider <- DataProvider$new(name = "")
  expect_false(emptyProvider$validate())
}
test_base_provider_validate()


## test DataProvider fetch throws error (abstract method)
test_base_provider_fetch_abstract <- function() {
  provider <- DataProvider$new(name = "TestProvider")
  expect_error(provider$fetch("query"))
}
test_base_provider_fetch_abstract()


## test DataProvider cache key generation
test_base_provider_cache_key <- function() {
  provider <- DataProvider$new(name = "TestProvider")

  key1 <- provider$getCacheKey("simple")
  expect_equal(key1, "TestProvider:simple")

  key2 <- provider$getCacheKey(list(a = 1, b = "test"))
  expect_true(grepl("TestProvider:", key2))
  expect_true(grepl("a=1", key2))
  expect_true(grepl("b=test", key2))
}
test_base_provider_cache_key()


## =============================================================================
## DataStore Tests
## =============================================================================

## test DataStore initialization
test_datastore_init <- function() {
  # Use temporary file
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  expect_equal(store$dbPath, tmpDb)
  expect_true(file.exists(dirname(tmpDb)))

  store$close()
  unlink(tmpDb)
}
test_datastore_init()


## test DataStore get/set operations
test_datastore_get_set <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  # Set a value
  store$set("test:key1", list(a = 1, b = "hello"), provider = "test")

  # Get the value back
  result <- store$get("test:key1")
  expect_equal(result$a, 1)
  expect_equal(result$b, "hello")

  # Non-existent key returns NULL
  expect_null(store$get("nonexistent"))

  store$close()
  unlink(tmpDb)
}
test_datastore_get_set()


## test DataStore metadata
test_datastore_metadata <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  store$set("test:key1", "value", provider = "test", version = "1.0")

  meta <- store$getMetadata("test:key1")
  expect_equal(meta$provider, "test")
  expect_equal(meta$version, "1.0")
  expect_true(!is.null(meta$created_at))
  expect_true(!is.null(meta$updated_at))

  store$close()
  unlink(tmpDb)
}
test_datastore_metadata()


## test DataStore listKeys
test_datastore_list_keys <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  store$set("provider1:key1", "v1", provider = "provider1")
  store$set("provider1:key2", "v2", provider = "provider1")
  store$set("provider2:key1", "v3", provider = "provider2")

  allKeys <- store$listKeys()
  expect_equal(length(allKeys), 3)

  p1Keys <- store$listKeys(provider = "provider1")
  expect_equal(length(p1Keys), 2)

  store$close()
  unlink(tmpDb)
}
test_datastore_list_keys()


## test DataStore clearProvider
test_datastore_clear_provider <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  store$set("provider1:key1", "v1", provider = "provider1")
  store$set("provider1:key2", "v2", provider = "provider1")
  store$set("provider2:key1", "v3", provider = "provider2")

  deleted <- store$clearProvider("provider1")
  expect_equal(deleted, 2)

  remainingKeys <- store$listKeys()
  expect_equal(length(remainingKeys), 1)

  store$close()
  unlink(tmpDb)
}
test_datastore_clear_provider()


## test DataStore refresh logging
test_datastore_refresh_log <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  store$logRefresh("test_provider", "started")
  store$logRefresh("test_provider", "completed", "Success", 100)

  history <- store$getRefreshHistory(provider = "test_provider")
  expect_equal(nrow(history), 2)
  expect_equal(history$status[1], "completed")
  expect_equal(history$records_affected[1], 100)

  store$close()
  unlink(tmpDb)
}
test_datastore_refresh_log()


## test DataStore stats
test_datastore_stats <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  store$set("p1:k1", "value1", provider = "p1")
  store$set("p2:k1", "value2", provider = "p2")

  stats <- store$stats()
  expect_equal(stats$total_entries, 2)
  expect_true("p1" %in% stats$providers)
  expect_true("p2" %in% stats$providers)
  expect_true(stats$size_bytes > 0)

  store$close()
  unlink(tmpDb)
}
test_datastore_stats()


## =============================================================================
## ProviderStore Wrapper Tests
## =============================================================================

## test ProviderStore wrapper
test_provider_store_wrapper <- function() {
  tmpDb <- tempfile(fileext = ".sqlite")
  store <- DataStore$new(dbPath = tmpDb)

  providerStore <- createProviderStore(store, "myProvider")

  # Set via wrapper
  providerStore$set("key1", list(data = "test"))

  # Get via wrapper
  result <- providerStore$get("key1")
  expect_equal(result$data, "test")

  # Check actual key in store
  expect_true(store$exists("myProvider:key1"))

  # List keys
  keys <- providerStore$listKeys()
  expect_equal(length(keys), 1)

  store$close()
  unlink(tmpDb)
}
test_provider_store_wrapper()


## =============================================================================
## Provider Inheritance Tests
## =============================================================================

## test CompoundProvider interface
test_compound_provider_interface <- function() {
  # Create a concrete test implementation
  TestCompoundProvider <- R6::R6Class(
    "TestCompoundProvider",
    inherit = CompoundProvider,
    public = list(
      fetch = function(query) {
        compound <- if (is.list(query)) query$compound else query
        return(list(compound = compound, found = TRUE))
      },
      enrich = function(dataTable) { dataTable },
      getOutputColumns = function() { c("test_col") }
    )
  )

  provider <- TestCompoundProvider$new(name = "TestCompound")

  # Test fetchByCompound
  result <- provider$fetchByCompound("aspirin")
  expect_equal(result$compound, "aspirin")
  expect_true(result$found)

  # Test fetchByCompounds
  results <- provider$fetchByCompounds(c("aspirin", "ibuprofen"))
  expect_equal(length(results), 2)
  expect_true("aspirin" %in% names(results))
  expect_true("ibuprofen" %in% names(results))
}
test_compound_provider_interface()


## test ProteinProvider interface
test_protein_provider_interface <- function() {
  # Create a concrete test implementation
  TestProteinProvider <- R6::R6Class(
    "TestProteinProvider",
    inherit = ProteinProvider,
    public = list(
      fetch = function(query) {
        id <- if (is.list(query)) query$uniprot_id else query
        return(list(id = id, organism = "Human"))
      },
      enrich = function(dataTable) { dataTable },
      getOutputColumns = function() { c("test_col") }
    )
  )

  provider <- TestProteinProvider$new(name = "TestProtein")

  # Test fetchByUniprot
  result <- provider$fetchByUniprot("P12345")
  expect_equal(result$id, "P12345")
  expect_equal(result$organism, "Human")

  # Test fetchByUniprots
  results <- provider$fetchByUniprots(c("P12345", "Q67890"))
  expect_equal(length(results), 2)
}
test_protein_provider_interface()


## =============================================================================
## KEGG Pathway Counter Test (from existing test_scancer.R)
## =============================================================================

## test KEGG pathway counting logic
test_kegg_pathway_counter <- function() {
  keggText <- "ENTRY       10458             CDS       T01001
SYMBOL      BAIAP2, BAP2, FLAF3, IRSP53, WAML
NAME        (RefSeq) BAR/IMD domain containing adaptor protein 2
ORTHOLOGY   K05627  BAI1-associated protein 2
ORGANISM    hsa  Homo sapiens (human)
PATHWAY     hsa04520  Adherens junction
            hsa04810  Regulation of actin cytoskeleton
            hsa05130  Pathogenic Escherichia coli infection
            hsa05135  Yersinia infection
NETWORK     nt06135  Cytoskeletal regulation (viruses and bacteria)
"

  pattern <- stringr::regex(
    "^PATHWAY.+?^(NETWORK|DISEASE|DRUG_TARGET|BRITE)",
    multiline = TRUE,
    dotall = TRUE
  )

  numOfPathwayEntries <- stringr::str_extract(keggText, pattern) %>%
    stringr::str_count("\n")

  expect_equal(numOfPathwayEntries, 4)
}
test_kegg_pathway_counter()
