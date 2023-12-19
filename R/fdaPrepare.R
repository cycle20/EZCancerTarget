##
## fdaPrepare.R: creates R data file(s) from FDA label JSONs
##

## Usage: call the main() from command line:
## R -e 'source("R/fdaPrepare.R"); main()'

suppressMessages(library(dplyr))
library(jsonlite)
suppressMessages(library(tibble))

main <- function() {
  # get params
  args <- commandArgs(trailingOnly = TRUE)
  prepare.FDA.RDS(args[1], args[2])
}

prepare.FDA.RDS <- function(fdaJSON, fdaRDS) {

  message(glue::glue("Reading {fdaJSON}... "), appendLF = FALSE)
  fdaData <- jsonlite::fromJSON(fdaJSON, flatten = TRUE) %>%
      tibble::tibble()
  message("done.")

  # append to already existing data
  if (file.exists(fdaRDS)) {
    message(glue::glue("Reading {fdaRDS}... "), appendLF = FALSE)
    rdsData <- readRDS(fdaRDS)
    message("done.")
    fdaData <- rbind(rdsData, fdaData)
  }

  message(glue::glue("Saving file {fdaRDS}... "), appendLF = FALSE)
  saveRDS(fdaData, fdaRDS)
  message("done.")
}

# TODO: this should be moved to a processing script
samlpeQuery <- function(file) {
  labelData <- readRDS(file)
  labelData <- labelData %>%
    dplyr::rowwise() %>%
    dplyr::filter(any(stringi::stri_detect_regex(openfda.generic_name, '^DIME.+')))

  print(labelData)
}
