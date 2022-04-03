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
expect_equal(target = "Authorisation status", columnNames[8])
expect_equal(target = "First published", columnNames[28])
expect_equal(target = "Revision date", columnNames[29])
expect_equal(target = "URL", columnNames[30])


## test filtering ----
filtered <- report %>% dplyr::filter(`Active substance` == "sotorasib" )
expect_equal(target = 1, nrow(filtered))
expect_equal(target = "Lumykras", filtered$`Medicine name`[1])


## test filtering with regex ----
filtered <- report %>% dplyr::filter(grepl(`Active substance`, pattern = "sotorasib"))
expect_equal(target = 1, nrow(filtered))
expect_equal(target = "Lumykras", filtered$`Medicine name`[1])


## test withdrawn applications ----
filtered <- report %>% dplyr::filter(
  grepl(`Active substance`, pattern = "padeliporfin", ignore.case = TRUE)
)
expect_equal(target = 1, nrow(filtered))
## NOTE: extra coma at the end of name
expect_equal(target = "Tookad", filtered$`Medicine name`[1])
expect_equal(target = "Withdrawn", filtered$`Authorisation status`[1])

report <- readReport("Medicines_output_withdrawn_applications.xlsx")
filtered <- report %>% dplyr::filter(
  grepl(`Active substance`, pattern = "padeliporfin", ignore.case = TRUE)
)
expect_equal(target = 1, nrow(filtered))
## NOTE: extra coma at the end of name
expect_equal(target = "Tookad,", filtered$`Medicine name`[1])


# readReport("Medicines_output_summaries_of_opinion.xlsx")
# readReport("Medicines_output_paediatric_investigation_plans.xlsx")
# readReport("Medicines_output_orphan_designations.xlsx")
# readReport("Medicines_output_referrals.xlsx")
# readReport("Medicines_output_shortages.xlsx")
# readReport("Medicines_output_herbal_medicines.xlsx")
# readReport("Medicines_output_opinions_outside_eu.xlsx")
