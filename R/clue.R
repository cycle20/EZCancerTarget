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
library(readr)
library(whisker)

##
## Settings of global variables
##
USER_KEY <- Sys.getenv("CLUE_USER_KEY")
WEB_TEMPLATE <- "web/index.proto.html"
WEB_OUT <- "web/index.html"
## quick verification
assertthat::assert_that(!is.null(USER_KEY) && nchar(USER_KEY) > 0)
API_BASE <- "https://api.clue.io/api/"
VERBOSE <- NULL
## for verbosed httr requests use the following:
## VERBOSE <- verbose()

##### Data Section
NE.LOW10 <- c(
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
NE.LOW <- c(
  NE.LOW10,
  "ITGAM",
  "YBX3",
  "CTSS",
  "CD5",
  "C1QA",
  "KLRD1",
  "CCL21",
  "MX1",
  "GZMA",
  "ISG15",
  "PRF1",
  "CASP14",
  "CXCL2",
  "CYP35A",
  "MAGEA4",
  "LRMP",
  "ITGB4",
  "KRT17",
  "BCAT1",
  "VSNL1",
  "CAV2",
  "ANXA3",
  "ALDH2",
  "PGC",
  "VAMP8",
  "LAMB3",
  "REL",
  "TNFSF10",
  "PRAME",
  "CES1",
  "COL6A",
  "FOXI1",
  "MYC",
  "PTGS2",
  "CD44",
  "BCL3",
  "ROS1",
  "RAB27B",
  "CXCL10",
  "CCL20",
  "CCL21",
  "CXCL9"
)
NE.HIGH <- c(
  "RTN1",
  "NCAM1",
  "DNAJC6",
  "GRP",
  "CDH2",
  "SYP",
  "ID4",
  "ISL1",
  "CHGA",
  "FGF5",
  "FGF10",
  "IL9",
  "HSPB8",
  "HIC1",
  "metrn",
  "TPO",
  "LAMB4",
  "EGLN2",
  "INS",
  "SIX1",
  "L1CAM",
  "MYBL1",
  "PTN",
  "CCNA1",
  "DYSPL4",
  "CDKN2C",
  "ADAM23",
  "TP73",
  "NKX2-1",
  "AMH",
  "RBP1",
  "PAK7",
  "CXXC4",
  "CKB",
  "SOX2",
  "PAK3",
  "SMAD9",
  "DLL3",
  "FZD9",
  "COL9A3",
  "ZIC2",
  "CACNAE1"
)

# TODO: do we need information from these endpoints as well?
# - rep_fda_product
# - rep_fda_orange-book_term
# - rep_fda_exclusivity


#' Main function
#'
#' Downloads data from clue.io and represent it in
#' TSV and HTML format.
#'
#' @return
main <- function() {
  message("downloading data from clue.io...")
  result <- download(c(NE.LOW, NE.HIGH))
  message("download finished")
  # export result as TSV
  data.table::fwrite(result, "clue.tsv", sep = "\t")
  message("clue.tsv created")

  resultCollapsed <- collapseResult(result)
  ## export collapsed table as TSV
  data.table::fwrite(resultCollapsed, "clueCollapsed.tsv", sep = "\t")
  message("clueCollapsed.tsv created")
}

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

  perts <- perts(...) %>%
    select(target, pert_iname, pubchem_cid)

  x <- perts %>%
    rowwise() %>%
    mutate(target = paste(target, collapse = ", ")) %>%
    select(target, pert_iname, pubchem_cid) %>%
    arrange(target, pert_iname)

  write.table(x, file = "perts.tsv", sep = "\t")

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

#' Collapse table from clue
#'
#' Remove redundancies resulted by left joins on clue.io sub-tables.
#'
#' @param result tibble composition of clue.io sub-tables
#'
#' @return collapsed table
collapseResult <- function(result) {
  resultCollapsed <- result %>%
    select(
      HUGO,
      pert_iname,
      moa,
      final_status,
      status_source,
      drugbank_id,
      chembl_id
    ) %>%
    group_by(HUGO, pert_iname) %>%
    mutate(
      drugbank_ids = paste(unique(drugbank_id), collapse = "|"),
      chembl_ids = paste(unique(chembl_id, collapse = "|"))) %>%
    select(-c(drugbank_id, chembl_id)) %>%
    distinct()
}

## just call the main
main()
