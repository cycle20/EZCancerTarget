##
## test_ema_search.R
##

setwd('../..')
source("R/dataPatch.R")

## get tibble of data ----
report <- readReport("medicines-output-medicines-report_en.xlsx")
columnNames <- names(report)
print(columnNames)

## perform tests on column names ----
expect_equal(target = 39, length(columnNames))
expect_equal(target = "Category", columnNames[1])
expect_equal(target = "Medicine name", columnNames[2])
expect_equal(target = "International non-proprietary name (INN) / common name", columnNames[7])
expect_equal(target = "Active substance", columnNames[8])
expect_equal(target = "Authorisation status", columnNames[4])
expect_equal(target = "First published", columnNames[37])
expect_equal(target = "Revision date", columnNames[38])
expect_equal(target = "URL", columnNames[39])


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
expect_equal(target = "Authorised", filtered$`Authorisation status`[1])

report <- readReport("list-withdrawn-medicinal-products_en.xlsx", skip = 16)
filtered <- report %>% dplyr::filter(
  grepl(`Active Substance (s)`, pattern = "pipobromano", ignore.case = TRUE)
)
expect_equal(target = 1, nrow(filtered))
## NOTE: extra coma at the end of name
expect_equal(target = "REDCYTE", filtered$`Product name`[1])


# readReport("Medicines_output_summaries_of_opinion.xlsx")
# readReport("Medicines_output_paediatric_investigation_plans.xlsx")
# readReport("Medicines_output_orphan_designations.xlsx")
# readReport("Medicines_output_referrals.xlsx")
# readReport("Medicines_output_shortages.xlsx")
# readReport("Medicines_output_herbal_medicines.xlsx")
# readReport("Medicines_output_opinions_outside_eu.xlsx")

## check URLs ------------------------------

## arrange
clueTable <- tibble::as_tibble(list(
  pert_iname = c('padeliporfin', 'empagliflozin')
))
## act
clueTable <- ema(clueTable)
## assert
expect_equal(
  target = 'https://www.ema.europa.eu/en/medicines/human/EPAR/tookad',
  current = clueTable$emaLinks[1][[1]]
)
expect_equal(
  target = 'https://www.ema.europa.eu/en/medicines/human/EPAR/glyxambi',
  current = clueTable$emaLinks[2][[1]]
)
