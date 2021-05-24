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
library(googlesheets4)
library(httr)
library(jsonlite)
library(readr)
library(whisker)

##
## Settings of global variables
##
USER_KEY <- Sys.getenv("CLUE_USER_KEY")
## quick verification
assertthat::assert_that(!is.null(USER_KEY) && nchar(USER_KEY) > 0)
TARGET.INPUT <- "INPUT/target_list.tsv"
TARGET.LIST.ID <- Sys.getenv("TARGET_LIST_ID")
SERVICE_TOKEN_JSON_VAR_NAME <- "SERVICE_TOKEN_JSON"
API_BASE <- "https://api.clue.io/api/"
VERBOSE <- NULL
## for verbosed httr requests use the following:
## VERBOSE <- verbose()
OUTPUT <- "OUTPUT"
CLUE.RDS <- glue::glue("{OUTPUT}/clue.rds")
CLUE.COLLAPSED.TSV <- glue::glue("{OUTPUT}/clueCollapsed.tsv")
PERTS.TSV <- glue::glue("{OUTPUT}/perts.tsv")
## pert API call result with each columns
PERTS_WIDE.TSV <- glue::glue("{OUTPUT}/perts_wide.tsv")
TARGET_LIST.RDS <- glue::glue("{OUTPUT}/targetList.rds")

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
  ## read input list of targets
  if (TARGET.LIST.ID != character(1)) {
    message(glue::glue("reading data from spreadsheet..."))
    targetList <- readGoogleSpreadSheet(
        SERVICE_TOKEN_JSON_VAR_NAME, TARGET.LIST.ID
      )

    message(glue::glue("reading data from spreadsheet done"))
  } else {
    message(glue::glue("reading data from {TARGET.INPUT}..."))
    targetList <- readr::read_tsv(TARGET.INPUT)

    message(glue::glue("reading from {TARGET.INPUT} done"))
  }

  targetList <- targetList %>%
    rename(HUGO = 1, Label = 2, UNIPROT_KB_ID = 3) %>%
    select(HUGO, Label, UNIPROT_KB_ID) %>%
    dplyr::filter(!is.na(HUGO))

  targetListVector <- targetList %>% pull(HUGO)
  print(glue::glue("Input list: {targetListVector}"))

  # prepare output directory
  dir.create(OUTPUT, recursive = TRUE, showWarnings = FALSE)

  message("downloading data from clue.io...")
  result <- download(targetListVector)
  message("download finished")


  # create output files ---------------------------------------------------

  # export result as RDS
  saveRDS(result, CLUE.RDS)
  message(glue::glue("{CLUE.RDS} created"))

  resultCollapsed <- collapseResult(result)
  ## export collapsed table as TSV
  data.table::fwrite(resultCollapsed, CLUE.COLLAPSED.TSV, sep = "\t")
  message(glue::glue("{CLUE.COLLAPSED.TSV} created"))

  saveRDS(targetList, TARGET_LIST.RDS)
}


#' Read Google SpreadSheet
#'
#' @param authTokenEnvName OS environment variable containing JSON token
#' @param driveFileId unique
#'
#' @return spreadsheet first sheet as tibble
readGoogleSpreadSheet <- function(authTokenEnvName, driveFileId) {
  jsonString <- Sys.getenv(authTokenEnvName)

  googlesheets4::gs4_auth(
    path = jsonString,
    scopes = "https://www.googleapis.com/auth/spreadsheets.readonly"
  )

  googlesheets4::read_sheet(driveFileId)
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


#' Get sample information from clue.io
#'
#' @param ... list of official HUGO gene symbols
#'
#' @return data.frame with "broad_id", "catalog_no",
#' "expected_mass", "id", "InChIKey", "pert_id", "pert_iname", "pubchem_cid",
#' "purity", "qc_filename", "qc_ID", "qc_result", "sample_ID", "smiles",
#' "vendor" and "vendor_name" columns.
rep_samples <- function(...) {
  apiFunction <- "rep_samples"

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
      #id,
      # other fields?
      alt_name,
      pert_id,
      inchi_key,
      pert_url,
      # pert_summary, # maybe "description" is enough
      pcl_membership,

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
  ## function to transform and save perts data
  pertsSaveAndExport <- function(pertsData) {
    p <- perts %>%
      mutate(
        alt_name = null.to.na(alt_name),
        pert_url = null.to.na(pert_url),
        moa = null.to.na(moa)
      )
    data.table::fwrite(p, file = PERTS_WIDE.TSV, sep = "\t")
    message(glue::glue("{PERTS_WIDE.TSV} created"))

    pertsData <- pertsData %>%
        rowwise() %>%
        mutate(target = paste(target, collapse = "|")) %>%
        ## what are the other fields?
        select(target, pert_iname, pubchem_cid) %>%
        arrange(target, pert_iname)

    data.table::fwrite(pertsData, file = PERTS.TSV, sep = "\t")
    message(glue::glue("{PERTS.TSV} created"))
    return(invisible(NULL))
  }

  ## helper function
  null.to.na <- function(x) {
    if (is.list(x) || is.vector(x)) return(x)
    if(is.null(x)) x <- NA
    return(x)
  }
  null.to.na <- Vectorize(null.to.na)

  ## get data from "perts" endpoint
  perts <- perts(...)
  pertsSaveAndExport(perts)
  # Renaming to avoid conflict with moa from repDrugMoAs
  perts <- perts %>%
    rename(
      moa_from_perts = moa,
      pubchem_cid_from_perts = pubchem_cid
    )
    # TODO: alt_name excluded since its complicated list values with NULLs
    # select(-c(alt_name))

  repDrugTargets <- rep_drug_targets(...) %>%
    rename(HUGO = name) %>%
    select(-c(id))
  repDrugMoAs <- rep_drug_moas(repDrugTargets$pert_iname) %>%
    select(pert_iname, moa = name, -c(id))
  repDrugIndications <- rep_drug_indications(repDrugTargets$pert_iname) %>%
    rename(indication_source = source) %>%
    select(-c(id))
  repDrugs <- rep_drugs(repDrugTargets$pert_iname) %>%
    mutate(rep_drugs.pert_iname = pert_iname) %>%
    select(-c(id))
  repSamples <- rep_samples(repDrugTargets$pert_iname) %>%
    # In this case "pert_id" the join key to "pert" dataset
    select(pert_iname, pert_id, InChIKey, pubchem_cid, broad_id) %>%
    rename(
      # rep_samples.pert_iname = pert_iname,
      rep_samples.pert_id = pert_id,
      # rep_samples.pubchem_cid = pubchem_cid,
      rep_samples.InChIKey = InChIKey
    )

  ## joining tables
  result <- repDrugTargets %>%
    left_join(repDrugs) %>%
    left_join(repDrugMoAs) %>%
    left_join(repDrugIndications) %>%
    left_join(repSamples) %>%
    left_join(perts) %>%
    arrange(HUGO) %>%
    mutate(
      source = null.to.na(source),
      orange_book = null.to.na(orange_book),

      # variables from perts
      alt_name = null.to.na(alt_name),
      moa_from_perts = null.to.na(moa_from_perts),
      pcl_membership = null.to.na(pcl_membership),
      pert_url = null.to.na(pert_url)
    ) %>%
    ## re-position and exclusion of columns
    select(
      HUGO,
      pert_iname,
      pubchem_cid,
      synonyms,
      moa,
      moa_from_perts,
      final_status,
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
      alt_name,
      pert_id, # BRD-...
      rep_samples.pert_id,
      inchi_key,
      rep_samples.InChIKey,
      pert_url,
      pcl_membership,

      ## exclude some optional columns
      -c(in_cmap, iuphar_id, animal_only)
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
      chembl_id,
      pubchem_cid
    ) %>%
    group_by(HUGO, pert_iname) %>%
    mutate(
      drugbank_id = paste(unique(drugbank_id), collapse = "|"),
      pubchem_cid = paste(unique(pubchem_cid), collapse = "|"),
      chembl_id = paste(unique(chembl_id, collapse = "|"))) %>%
    distinct()
}


## just call the main
main()
