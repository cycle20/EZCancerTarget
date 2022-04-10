
WORK_DIR <- getwd()
setwd('../..')
source("R/renderWebPage.R")

cluePatched <- readRDS(PATCHED.CLUE.INPUT)

cluePatched <- cluePatched %>%
  dplyr::select(HUGO, UniProtData) %>%
  dplyr::distinct() %>%
  dplyr::arrange(HUGO)


cluePatched <- cluePatched %>% dplyr::mutate(
  RP = length(UniProtData$Reactome),            # `Reactome pathways`
  KP = 'TBD',                                   # `KEGG pathways`
  SN = 'TBD',                                   # `STRING neighbores`
  MF = length(UniProtData$molecularFunction),   # `Molecular Functions`
  SL = length(UniProtData$subCellularLocation), # `Subcellular Locations`
  BP = length(UniProtData$biologicalProcess)    # `Biological Processes`
)

expect_equal(cluePatched$HUGO[1], 'ANXA1')
expect_equal(cluePatched$KP[1], 'TBD')
expect_equal(cluePatched$MF[1], 7)
expect_equal(cluePatched$SL[1], 25)
expect_equal(cluePatched$BP[1], 51)


expect_equal(cluePatched$HUGO[4], 'RBP1')
expect_equal(cluePatched$KP[4], 'TBD')
expect_equal(cluePatched$MF[4], 2)
expect_equal(cluePatched$SL[4], 5)
expect_equal(cluePatched$BP[4], 0)


setwd(WORK_DIR)
