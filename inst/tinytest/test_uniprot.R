##
## test_uniprot.R
##

setwd('../..')
source("R/dataPatch.R")

## arrange
clueTable <- tibble::as_tibble(list(
  UNIPROT_KB_ID = c(
    'P01133'
  )
))

## act
clueTable <- xmlUniProt(clueTable)

## assert

# P01133
expect_equal(
  target = "calcium ion binding",
  current = clueTable$UniProtData[["P01133"]][["molecularFunction"]][["GO:0005509"]]
)
expect_equal(
  target = "extracellular exosome",
  current = clueTable$UniProtData[["P01133"]][["subCellularLocation"]][["GO:0070062"]]
)
expect_equal(
  target = "positive regulation of MAPK cascade",
  current = clueTable$UniProtData[["P01133"]][["biologicalProcess"]][["GO:0043410"]]
)
expect_equal(
  target = "SHC1 events in ERBB2 signaling",
  current = clueTable$UniProtData[["P01133"]][["Reactome"]][["R-HSA-1250196"]]
)
expect_equal(
  target = "9606.ENSP00000265171",
  current = clueTable$UniProtData[["P01133"]][["STRING"]]
)
expect_equal(
  target = "hsa:1950",
  current = clueTable$UniProtData[["P01133"]][["KEGG"]]
)
