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
expect_equal(target = "Authorised", filtered$`Authorisation status`[1])

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

## test concept of processing KEGG REST API result ----
## arrange
keggText <- "ENTRY       10458             CDS       T01001
SYMBOL      BAIAP2, BAP2, FLAF3, IRSP53, WAML
NAME        (RefSeq) BAR/IMD domain containing adaptor protein 2
ORTHOLOGY   K05627  BAI1-associated protein 2
ORGANISM    hsa  Homo sapiens (human)
PATHWAY     hsa04520  Adherens junction
            hsa04810  Regulation of actin cytoskeleton
            hsa05130  Pathogenic Escherichia coli infection
            hsa05135  Yersinia infection
NETWORK     nt06135  Cytoskeletal regulation (viruses and bacteria)
  ELEMENT   N01094  Escherichia Eae/Tir/TccP to Actin signaling pathway
BRITE       KEGG Orthology (KO) [BR:hsa00001]
             09140 Cellular Processes
              09144 Cellular community - eukaryotes
               04520 Adherens junction
                10458 (BAIAP2)
              09142 Cell motility
               04810 Regulation of actin cytoskeleton
                10458 (BAIAP2)
             09160 Human Diseases
              09171 Infectious disease: bacterial
               05130 Pathogenic Escherichia coli infection
                10458 (BAIAP2)
               05135 Yersinia infection
                10458 (BAIAP2)
             09180 Brite Hierarchies
              09182 Protein families: genetic information processing
               04131 Membrane trafficking [BR:hsa04131]
                10458 (BAIAP2)
            Membrane trafficking [BR:hsa04131]
             Endocytosis
              Bin/Amphiphysin/Rvs (BAR) family proteins
               I-BAR proteins
                10458 (BAIAP2)
POSITION    17:81035131..81117434
"
## act
pattern <- stringr::regex("^PATHWAY.+?^(NETWORK|DISEASE|DRUG_TARGET|BRITE)", multiline = TRUE, dotall = TRUE)
numOfPathwayEntries <- stringr::str_extract(keggText, pattern) %>%
  stringr::str_count("\n")
## assert
expect_equal(target = 4, numOfPathwayEntries)


url <- 'https://string-db.org/api/tsv/interaction_partners?identifiers=TP53&species=9606&limit=0&required_score=900'
result <- httr::GET(url)
result <- httr::content(result)
countOfPartners <- nrow(result)
expect_equal(target = 426, countOfPartners)
