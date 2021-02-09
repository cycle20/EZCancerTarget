##
## clue.R: collect data from clue.io
##
## NOTE: clue.io API access requires registration
##
## API key is assigned to the clue.io user profile.
## This script reads it from CLUE_USER_KEY environment variable.
##

library(assertthat)
library(data.table)
library(dplyr)
library(glue)
library(httr)
library(jsonlite)

##
## Settings of global variables
##
USER_KEY <- Sys.getenv("CLUE_USER_KEY")
## quick verification
assertthat::assert_that(!is.null(USER_KEY) && nchar(USER_KEY) > 0)
API_BASE <- "https://api.clue.io/api/"
VERBOSE <- NULL
## for verbosed httr requests use the following:
## VERBOSE <- verbose()

# TODO: do we need information from these endpoints as well?
# - rep_fda_product
# - rep_fda_orange-book_term
# - rep_fda_exclusivity

#' Get drug-targets information from clue.io
#'
#' @param ... list of official HUGO gene symbols
#'
#' @return data.frame with "name", "pert_iname",
#' "private_source" and "source" columns.
rep_drug_targets <- function(...) {
  apiFunction <- "rep_drug_targets"

  filterParams <- list(
    where = list(
      name = list(inq = c(...))
    )
  )
  filterParams <- jsonlite::toJSON(filterParams)

  ## concatenate URL with parameters
  requestUrl <- glue("{API_BASE}{apiFunction}?filter={filterParams}")
  result <- getWithUserKey(requestUrl)

  return(getJSONContentAsDataFrame(result))
}

#' MoAs from clue.io
#'
#' Client side of rep_drug_moas API endpoint.
#'
#' @param ... list of internal (clue.io) perturbation identifiers.
#'
#' @return data.frame of perturbagens with associated indications and diseases.
rep_drug_moas <- function(...) {
  apiFunction <- "rep_drug_moas"

  filterParams <- list(
    where = list(
      pert_iname = list(inq = c(...))
    )
  )
  filterParams <- jsonlite::toJSON(filterParams)

  ## concatenate URL with parameters
  requestUrl <- glue("{API_BASE}{apiFunction}?filter={filterParams}")
  result <- getWithUserKey(requestUrl)

  return(getJSONContentAsDataFrame(result))
}

#' Drug-disease/indication from clue.io
#'
#' Client side of rep_drug_indications API endpoint.
#'
#' @param ... list of internal (clue.io) perturbation identifiers.
#'
#' @return data.frame of perturbagens with associated indications and diseases.
rep_drug_indications <- function(...) {
  apiFunction <- "rep_drug_indications"

  filterParams <- list(
    where = list(
      pert_iname = list(inq = c(...))
    )
  )
  filterParams <- jsonlite::toJSON(filterParams)

  ## concatenate URL with parameters
  requestUrl <- glue("{API_BASE}{apiFunction}?filter={filterParams}")
  result <- getWithUserKey(requestUrl)

  return(getJSONContentAsDataFrame(result))
}

#' Get drug information from clue.io
#'
#' Client side of rep_drugs API endpoint.
#'
#' @param ... list of internal (clue.io) perturbation identifiers.
#'
#' @return data.frame of the details.
rep_drugs <- function(...) {
  apiFunction <- "rep_drugs"

  filterParams <- list(
    where = list(
      pert_iname = list(inq = c(...))
    )
  )
  filterParams <- jsonlite::toJSON(filterParams)

  ## concatenate URL with parameters
  requestUrl <- glue("{API_BASE}{apiFunction}?filter={filterParams}")
  result <- getWithUserKey(requestUrl)

  return(getJSONContentAsDataFrame(result))
}

#' Get perturbation data from clue.io.
#'
#' Client side of perts API endpoint.
#'
#' @param ...
#'
#' @return data.frame of the details.
#'         NOTE: Targets with no matches excluded from the result table.
perts <- function(...) {
  apiFunction <- "perts"
  filterParams <- list(
    where = list(
      target = list(inq = c(...))
    )
  )
  filterParams <- jsonlite::toJSON(filterParams)

  ## concatenate URL with parameters
  requestUrl <- glue("{API_BASE}{apiFunction}?filter={filterParams}")

  response <- getWithUserKey(requestUrl)
  responseFrame <- getJSONContentAsDataFrame(response)
  ## selection of relevant fields
  responseFrame <-
    responseFrame %>%
    select(
      id,
      target,
      pert_iname,
      moa,
      description,
      status,
      pubchem_cid
    )
  return(responseFrame)
}

#' GET request
#'
#' @param requestUrl
#'
#' @return list object that represents HTTP response data
getWithUserKey <- function(requestUrl) {
  result <- httr::GET(url = requestUrl,
    config = add_headers(user_key = USER_KEY), VERBOSE)
  return(result)
}

#' Convert HTTP response body to data.frame
#'
#' Utility function, used by clue.io API calls.
#'
#' @param httrResponse result of an HTTP request performed by an httr function
#'
#' @return A data.frame object that contains data coerced from JSON response.
getJSONContentAsDataFrame <- function(httrResponse) {
  txt <- httr::content(httrResponse, as = "text")
  list <- fromJSON(txt)
  return(as.data.frame(list))
}


#' Download data from endpoints.
#'
#' Download and join data from different
#' clue.io REST API endpoints.
#'
#' @param ... list of HUGO names of genes.
#'
#' @return Final data.frame composed from multiple datasets.
download <- function(...) {

  ## helper function
  null.to.na <- function(x) {
    if(is.null(x)) x <- NA
    return(x)
  }
  null.to.na <- Vectorize(null.to.na)

  repDrugTargets <- rep_drug_targets(...) %>%
    rename(HUGO = name) %>%
    select(-c(id))
  repDrugMoAs <- rep_drug_moas(repDrugTargets$pert_iname) %>%
    select(pert_iname, moa = name, -c(id))
  repDrugIndications <- rep_drug_indications(repDrugTargets$pert_iname) %>%
    rename(indication_source = source) %>%
    select(-c(id))
  repDrugs <- rep_drugs(repDrugTargets$pert_iname) %>%
    select(-c(id))
  perts <- perts(...) %>%
    select(target, pert_iname, pubchem_cid)

  browser()

  result <- repDrugTargets %>%
    left_join(repDrugs) %>%
    left_join(repDrugMoAs) %>%
    left_join(repDrugIndications) %>%
    left_join(perts) %>%
    arrange(HUGO) %>%
    mutate(orange_book = null.to.na(orange_book)) %>%
    ## re-position and exclusion of columns
    select(
      HUGO,
      pert_iname,
      moa,
      final_status,
      pubchem_cid,
      chembl_id,
      source,
      ttd_id,
      drugbank_id,
      status_source, ## source of final_status
      clinical_notes,
      orange_book,
      disease_area,
    	indication,
      indication_source,
      ## exclude some optional columns
      -c(synonyms, in_cmap, iuphar_id, animal_only)
    )

  return(result)
}

##
# CD70 = P32970
# CXCR2 = P25025
# MMP7 = P09237
# TP63 = Q9H3D4
# ANXA1 = P04083
# KRT5 = P13647
# IFI27 = P40305
# FCGR1A = P12314
# BIRC3 = Q13489
# ITBG6 = P18564

result <- download(
  "CD70",
  "CXCR2",
  "MMP7",
  "TP63",
  "ANXA1",
  "KRT5",
  "IFI27",
  "FCGR1A",
  "BIRC3",
  "ITBG6"
)

## export result as TSV
data.table::fwrite(result, "clue.tsv", sep = "\t")
message("clue.tsv created")
