##
## clue.R: collect data from clue.io
##

## Usage: call the main() from command line:
## R -e 'source("R/clue.R"); main()'

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
TARGET.INPUT <- "data/full_list.tsv"
TARGET.INPUT <- "data/target_list.tsv"
PERTS.INPUT <- "data/repurposing_drugs_20200324.rds"
VERBOSE <- NULL
## for verbosed httr requests use the following:
## VERBOSE <- verbose()
OUTPUT <- "OUTPUT"
CLUE.RDS <- glue::glue("{OUTPUT}/clue.rds")
TARGET_LIST.RDS <- glue::glue("{OUTPUT}/targetList.rds")

#' Main function
#'
#' Downloads data from clue.io and represent it in
#' TSV and HTML format.
#'
#' @return
main <- function() {
  ## read input list of targets
  message(glue::glue("reading data from {TARGET.INPUT}..."))
  targetList <- readr::read_tsv(TARGET.INPUT)

  message(glue::glue("reading from {TARGET.INPUT} done"))

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

  saveRDS(targetList, TARGET_LIST.RDS)
}

#' Download data from endpoints.
#'
#' Download and join data from different
#' clue.io REST API endpoints.
#'
#' @param ... list of HUGO names of genes.
#'
#' @return Final data.frame composed from multiple datasets.
#' @import dplyr
download <- function(...) {

  perts <- readRDS(PERTS.INPUT)

  repDrugTargets <- perts %>%
    rename(HUGO = name) %>%
    select(-c(id))

  ## joining tables
  result <- repDrugTargets %>%
    arrange(HUGO) %>%
    mutate(
      source = null.to.na(source),
      orange_book = null.to.na(orange_book),
    ) %>%
    ## re-position and exclusion of columns
    select(
      HUGO,
      pert_iname,
      pubchem_cid,
      synonyms,
      moa,
      final_status,
      chembl_id,
      source,
      ttd_id,
      # drugbank_id, NOTE: must be supplied from elsewhere. e.g. PubChem
      status_source, ## source of final_status
      clinical_notes,
      orange_book,
      disease_area,
      indication,
      indication_source,
      rep_samples.pert_id,
      rep_samples.InChIKey,

      ## exclude some optional columns
      -c(in_cmap, iuphar_id, animal_only)
    )
  return(result)
}
