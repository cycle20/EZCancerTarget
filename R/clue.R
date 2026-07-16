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

  message("building drug-target table from local snapshot...")
  result <- download(targetListVector)
  message(glue::glue("built table: {nrow(result)} target-compound rows"))


  # create output files ---------------------------------------------------

  # export result as RDS
  saveRDS(result, CLUE.RDS)
  message(glue::glue("{CLUE.RDS} created"))

  saveRDS(targetList, TARGET_LIST.RDS)
}

#' Build a target-centric drug table from the local snapshot.
#'
#' The clue.io REST API is retired, so data now comes from the locally stored
#' Broad Repurposing Hub snapshot (\code{PERTS.INPUT}). That snapshot is
#' drug-centric: each row is a compound with a pipe-separated \code{target}
#' field of HUGO gene symbols. This explodes it into a target-centric table
#' (one row per HUGO/compound pair) and maps the available columns onto the
#' schema the rest of the pipeline joins on. Columns that were only available
#' from the retired API are kept as NA so downstream code stays intact.
#'
#' @param targets Character vector of HUGO gene symbols to keep. When NULL,
#'   all targets present in the snapshot are returned.
#'
#' @return Final data.frame keyed by HUGO.
#' @import dplyr
download <- function(targets = NULL) {

  perts <- readRDS(PERTS.INPUT)

  ## Explode the pipe-separated `target` field into one row per HUGO symbol.
  ## (tidyr is not available in the runtime image, so use base-R row
  ## expansion.) Drugs with no annotated target yield an NA HUGO and are
  ## dropped below.
  targetLists <- strsplit(as.character(perts$target), "\\|")
  rowIndex <- rep(seq_len(nrow(perts)), lengths(targetLists))
  result <- perts[rowIndex, , drop = FALSE]
  result$HUGO <- trimws(unlist(targetLists))

  result <- result %>%
    filter(!is.na(HUGO) & HUGO != "") %>%
    ## `clinical_phase` is the snapshot's equivalent of the API `final_status`
    rename(final_status = clinical_phase)

  ## restrict to the requested target genes, if any
  if (!is.null(targets) && length(targets) > 0) {
    result <- result %>% filter(HUGO %in% targets)
  }

  ## Columns only available from the retired clue.io API; kept as NA so the
  ## downstream schema (dataPatch.R / renderWebPage.R) stays intact.
  apiOnlyColumns <- c(
    "pubchem_cid", "synonyms", "chembl_id", "source", "ttd_id",
    "status_source", "clinical_notes", "orange_book", "indication_source",
    "rep_samples.pert_id", "rep_samples.InChIKey"
  )
  for (col in apiOnlyColumns) {
    result[[col]] <- NA
  }

  ## re-position columns to the schema downstream code expects
  columnOrder <- c(
    "HUGO", "pert_iname", "pubchem_cid", "synonyms", "moa", "final_status",
    "chembl_id", "source", "ttd_id", "status_source", "clinical_notes",
    "orange_book", "disease_area", "indication", "indication_source",
    "rep_samples.pert_id", "rep_samples.InChIKey"
  )
  result <- result %>%
    arrange(HUGO) %>%
    select(all_of(columnOrder))

  return(result)
}
