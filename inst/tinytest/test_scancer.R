library(curl)
library(glue)
library(readxl)
library(tinytest)

setwd('../..')
source("R/dataPatch.R")


## get tibble of data ----
report <- readReport("Medicines_output_european_public_assessment_reports.xlsx")
columnNames <- names(report)
print(columnNames)

## perform tests on column names ----
expect_equal(target = 30, length(columnNames))
expect_equal(target = "Category", columnNames[1])
expect_equal(target = "Medicine name", columnNames[2])
expect_equal(target = "International non-proprietary name (INN) / common name", columnNames[4])
expect_equal(target = "Active substance", columnNames[5])
expect_equal(target = "First published", columnNames[28])
expect_equal(target = "Revision date", columnNames[29])
expect_equal(target = "URL", columnNames[30])


## test filtering ----
filtered <- report %>% dplyr::filter(`Active substance` == "sotorasib" )
expect_equal(target = 1, nrow(filtered))
expect_equal(target = "Lumykras", filtered$`Medicine name`[1])


## test filtering with regex ----
filtered <- report %>% dplyr::filter( grepl(`Active substance`, pattern = "sotorasib" ))
expect_equal(target = 1, nrow(filtered))
expect_equal(target = "Lumykras", filtered$`Medicine name`[1])

