library(curl)
library(glue)
library(readxl)
library(tinytest)

setwd('../..')
source("R/dataPatch.R")


getEMAFile <- function(file, quiet = FALSE) {
  EMA_FILES_BASE_URL <- "https://www.ema.europa.eu/sites/default/files"
  url <- glue::glue("{EMA_FILES_BASE_URL}/{file}")
  if (!quiet) {
    print(glue::glue("Downloading {url}"))
  }
  curl::curl_download(url = url, destfile = file, mode ="wb", quiet = quiet)
}

readReport <- function(fileName) {
  getEMAFile(fileName)
  report <- readxl::read_excel(fileName, skip = 7)
  return(report)
}

## get tibble of data
report <- readReport("Medicines_output_european_public_assessment_reports.xlsx")
columnNames <- names(report)
print(columnNames)

## perform tests on column names
expect_equal(target = 30, length(columnNames))
expect_equal(target = "Category", columnNames[1])
expect_equal(target = "Medicine name", columnNames[2])
expect_equal(target = "International non-proprietary name (INN) / common name", columnNames[4])
expect_equal(target = "Active substance", columnNames[5])
expect_equal(target = "First published", columnNames[28])
expect_equal(target = "Revision date", columnNames[29])
expect_equal(target = "URL", columnNames[30])
