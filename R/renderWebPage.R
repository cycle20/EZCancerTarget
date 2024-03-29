##
## renderWebPage.R: Present data as webpage(s)
##

## Usage: call the main() from command line:
## R -e 'source("R/renderWebPage.R"); main()'


library(assertthat)
library(dplyr)
library(glue)
library(readr)
library(rvest)
library(stringr)
library(whisker)


##
## Settings of global variables
##
WEB_TEMPLATE <- "web/template.html"
OUTPUT <- "OUTPUT"
WEB_OUT <- glue::glue("{OUTPUT}/index.target.with.data.html")
WEB_OUT_NODATA <- glue::glue("{OUTPUT}/index.target.no_data.html")
TARGET.INPUT <- "data/target_list.tsv"
TARGET_LIST.RDS <- glue::glue("{OUTPUT}/targetList.rds")
# CLUE.INPUT <- glue::glue("{OUTPUT}/clue.tsv")
PATCHED.CLUE.INPUT <- glue::glue("{OUTPUT}/clue_patched.rds")
CHEMBL.URL.TEMPLATE <- "https://www.ebi.ac.uk/chembl/target_report_card"
MOLECULAR_CSV.OUTPUT <- glue::glue("{OUTPUT}/molecular_background.csv")
COMPOUNDS_CSV.OUTPUT <- glue::glue("{OUTPUT}/compounds_summary.csv")

#' Main function
#'
#' Load data and represent it in HTML format.
#'
#' @return
main <- function() {
  ## read curated input names
  targetList <- readRDS(TARGET_LIST.RDS)

  ## read input data prepared by dataPatch.R
  patchedData <- readRDS(PATCHED.CLUE.INPUT)

  patchedData <- targetList %>%
    left_join(patchedData) %>%
    rowwise() %>%
    mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID)))

  renderWebPage(
    patchedData, title = "Has CLUE.IO Entries", outputHTML = WEB_OUT
  )

  warnings()
}


#' Render web page
#'
#' @param result List of data structures to be visualized as a web page.
#' @param title Extension title.
#' @param outputHTML Name of result HTML file.
#'
#' @return Invisible NULL.
renderWebPage <- function(result, title, outputHTML = NULL) {

  resultHasNoData <- result %>%
    filter(has_data == FALSE) %>%
    arrange(Label, HUGO)

  result <- result %>%
    filter(has_data == TRUE) %>%
    arrange(Label, HUGO)


  ## create summary tables ------------------------------------------------

  molecularBackground <- renderMolecularBackgroundSummary(result)
  compoundsSummary <- renderCompoundsSummary(result)


  ## create overview list  ------------------------------------------------

  overview <- list(
    targetsWithNoClueData = resultHasNoData %>% pull(HUGO) %>% unique(),
    targetsWithClueData = result %>% pull(HUGO) %>% unique(),
    totalCompoundCount = result %>%
      select(pert_iname) %>% distinct() %>% nrow()
  )
  overview$targetsWithNoClueDataCount <- length(overview$targetsWithNoClueData)
  overview$targetsWithClueDataCount <- length(overview$targetsWithClueData)
  overview$targetsWithNoClueData <- paste(overview$targetsWithNoClueData, collapse = ', ')
  overview$targetsWithClueData <- paste(overview$targetsWithClueData, collapse = ', ')
  overview$avgCompoundsPerTarget <- round(
    overview$totalCompoundCount / overview$targetsWithClueDataCount, digits = 2
  )

  countsByFinalStatus <- overviewByFinalStatus(result)
  overview <- c(overview, countsByFinalStatus)

  # result %>% select(pert_iname) %>% distinct()
  # result %>% select(pubchem_cid) %>% distinct()
  # result %>% select(chembl_id) %>% distinct()
  # result %>% select(drugbank_id) %>% distinct()


  ## prepare summary tables for access from template ----------------------

  molecularBackground <- whisker::rowSplit(molecularBackground)
  compoundsSummary <- whisker::rowSplit(compoundsSummary)

  ## transforming data for rendering ----
  message("transforming data for rendering...")
  ## - this should be an iteration on each HUGO group
  ## - collect pert groups for each gene group
  ## Maybe I shouldn't join result tables in download function.
  collection <- list()
  for (geneGroup in unique(result$HUGO)) {
    message(glue::glue("processing gene group: {geneGroup}..."))
    groupName <- geneGroup
    # overwrite variable with data subset
    geneGroup <- result %>%
      filter(HUGO == groupName)

    hasData <- geneGroup$has_data[1]
    label <- geneGroup$Label[1]
    UNIPROT_KB_ID <- geneGroup$UNIPROT_KB_ID[1]

    # TODO: Old solution was: geneGroup$protein_external_id[1]
    uniProtData <- result %>%
      select(HUGO, UniProtData) %>%
      filter(HUGO == groupName) %>%
      distinct() %>%
      pull(UniProtData)

    ## unwrap UniProt details
    stringID <- uniProtData[[UNIPROT_KB_ID]]$STRING
    keggID <- uniProtData[[UNIPROT_KB_ID]]$KEGG
    uniProtSubCellular <- uniProtSubCellular(uniProtData[[UNIPROT_KB_ID]])
    uniProtMolecular <- uniProtMolecularFunction(uniProtData[[UNIPROT_KB_ID]])
    uniProtBiological <- uniProtBiologicalProcess(uniProtData[[UNIPROT_KB_ID]])
    ## create an iterable list of list of "pathwayID" and "pathwayName" pairs
    reactomePathways <- uniProtData[[UNIPROT_KB_ID]]$Reactome %>%
      whisker::iteratelist(name = "pathwayID", value = "pathwayName")

    ## group by pert_iname
    # drugBankId <- geneGroup$drugbank_id[1]
    # chemblId <- geneGroup$chembl_id[1]
    # finalStatus <- geneGroup$final_status[1]

    grouppedByPerts <- geneGroup %>%
      # select(-c(HUGO, protein_external_id, has_data)) %>%
      select(-c(HUGO, has_data)) %>%
      group_by(pert_iname) %>%
      group_split()

    ## collect pert groups per genes and creates
    grouppedByPerts <- multivaluedCellsToHTML(grouppedByPerts)

    collection <- c(collection, list(list(
      target = groupName,
      stringID = stringID,
      keggID = keggID,
      data = grouppedByPerts,
      groupLabel = label,
      UNIPROT_KB_ID = UNIPROT_KB_ID,
      hasData = tolower(hasData),
      uniProtSubCell = uniProtSubCellular,
      uniProtMolecular = uniProtMolecular,
      uniProtBiological = uniProtBiological,
      reactomePathways = reactomePathways
    )))

  } # end of main for loop


  ## export as web page ---------------------------------------------------

  message(glue("reading web template: {WEB_TEMPLATE}"))
  template <- readr::read_file(WEB_TEMPLATE)

  creationTime <- format(Sys.time(), usetz = TRUE)
  message(glue("rendering web page, template is '{WEB_TEMPLATE}'"))
  renderResult <- whisker::whisker.render(template, debug = TRUE, data = list(
    targets = collection,
    overview = overview,
    molecularBackground = molecularBackground,
    compoundsSummary = compoundsSummary,
    title = title,
    creationTime = creationTime
  ))
  readr::write_file(renderResult, file = outputHTML)
  message(glue("rendered web page is saved into '{outputHTML}'"))

  invisible(NULL)
}


#' Prepare multiple values of table cell
#'
#' @param dataList List of dataframes
#'
#' @return Pre-processed dataframes to be ready to show multiple values in
#' sepecific HTML table cells.
#' @import dplyr
multivaluedCellsToHTML <- function(dataList) {
  assertthat::assert_that(is.list(dataList))
  assertthat::assert_that(length(dataList) > 0)
  assertthat::assert_that(is.data.frame(dataList[[1]]))

  cellsToHTML <- function(dataframe) {
    # TODO: Does it eliminate duplications?
    ## collapsing moa
    moa <- paste(unique(dataframe$moa), collapse = ", <br/><br/>")

    dataframe <- dataframe %>%
      # select(-c(moa, pubchem_cid, chembl_id)) %>%
      select(
        pert_iname,
        status_source,
        drugbank_id,
        pubchem_cid,
        chembl_id,
        final_status
      ) %>%
      distinct() %>%
      mutate(
        chembl_id = chemblHTML(chembl_id),
        pubchem_cid = pubChemHTML(pert_iname, pubchem_cid),
        drugbank_id = drugBankHTML(drugbank_id)
      ) %>%
      rowwise() %>%
      mutate(chem_drugs = paste0(
        na.exclude(c(chembl_id, pubchem_cid, drugbank_id)),
        collapse = "<br/>")
      ) %>%
      select(-c(chembl_id, pubchem_cid, drugbank_id)) %>%
      distinct()

    ## strict verification
    browser(expr = (nrow(dataframe) != 1))
    assertthat::assert_that(nrow(dataframe) == 1)
    ## set collapsed moa
    dataframe$moa <- moa
    return(dataframe)
  }
  dataList <- lapply(dataList, cellsToHTML)
  return(dataList)
}


#' ChEMBL Id to HTML link
#'
#' @param chemblId
#'
#' @return Character object containing a HTML code fragment with
#' an "anchor" element.
chemblHTML <- function(chemblId) {
  ## used in case of non-numeric ChEMBL Id
  unexpectedChemblId <- function(chemblId) {
    return(
      if_else(chemblId != "",
        glue::glue("Unexpected ChEMBL value: '{chemblId}'"),
        ""
      )
    )
  }

  chemblId <- unique(chemblId)
  ## choose appropriate one
  HTMLtext <- dplyr::if_else(is.na(chemblId),
    ## TRUE branch
    glue::as_glue(NA),
    ## FALSE branch
    dplyr::if_else(stringr::str_ends(chemblId, pattern = "^CHEMBL[0-9]+$"),
      ## TRUE branch
      {
        link <- glue::glue("{CHEMBL.URL.TEMPLATE}/{chemblId}")
        aHref(link = link, titleText = chemblId)
      },
      unexpectedChemblId(chemblId)
    ) # inner if_else
  ) # outer if_else
  return(if_else(is.na(HTMLtext),
    HTMLtext,
    paste(HTMLtext, collapse = "<br/>")
  ))
}


#' Create DrugBank links
#'
#' @param drugBankId DrugBank ID(s)
#'
#' @return HTML "a" snippet(s) that can be used in HTML document directly.
drugBankHTML <- function(drugBankId) {
  drugBankId <- unique(drugBankId)

  HTMLtext <- if_else(stringr::str_ends(drugBankId, pattern = "^DB[0-9]+$"), {
    link <- glue::glue("http://www.drugbank.ca/drugs/{drugBankId}")
    aHref(link = link, titleText = drugBankId)
  },
    if_else(is.na(drugBankId),
      glue::as_glue(NA),
      ## text as is
      glue::as_glue(drugBankId)
    )
  )
  return(if_else(is.na(HTMLtext),
    HTMLtext,
    paste(HTMLtext, collapse = "<br/>")
  ))
}


#' Create PubChem links
#'
#' @param pert_iname compound name
#' @param pubChemId PubChem ID(s)
#'
#' @return HTML "a" snippet(s) that can be used in HTML document directly.
pubChemHTML <- function(pert_iname, pubChemId) {
  pubChemId <- unique(pubChemId)
  pert_iname <- unique(pert_iname)

  ## choose appropriate one
  id <- if_else(is.na(pubChemId), pert_iname, as.character(pubChemId))
  label <- if_else(is.na(pubChemId), glue::glue("PubChem??{id}??"),
                   glue::glue("PubChem: {id}"))
  url <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/compound/{id}")
  return(
    paste(aHref(link = url, titleText = label), collapse = "<br/>")
  )
}


#' Create sub-cellular list for iteration
#'
#' @param uniProtDataItem
#'
#' @return List of GOId-subCellLocation pairs.
uniProtSubCellular <- function(uniProtDataItem) {
  uniProtDataItem$subCellularLocation %>%
    whisker::iteratelist(name = "GOId", value = "subCellLocation")
}


#' Create list of molecular functions for iteration
#'
#' @param uniProtDataItem
#'
#' @return List of GOId-molecularFunction pairs.
uniProtMolecularFunction <- function(uniProtDataItem) {
  uniProtDataItem$molecularFunction %>%
    whisker::iteratelist(name = "GOId", value = "molecularFunction")
}


#' Create list of biological processes for iteration
#'
#' @param uniProtDataItem
#'
#' @return List of GOId-biologicalProcess pairs.
uniProtBiologicalProcess <- function(uniProtDataItem) {
  uniProtDataItem$biologicalProcess %>%
    whisker::iteratelist(name = "GOId", value = "biologicalProcess")
}


#' Create an "anchor" element
#'
#' @param link Parameter of "href" attribute.
#' @param titleText character content of "a" element.
#'
#' @return HTML "a" snippet that can be used in HTML document directly.
aHref <- function(link, titleText) {
  return(glue::glue("<a href=\"{link}\" target=\"_blank\">{titleText}</a>"))
}

## Summary Tables ----

renderMolecularBackgroundSummary <- function(cluePatched) {
  cluePatched <- cluePatched %>%
    dplyr::select(
      HUGO, UniProtData, NumberOfKEGGPathways, NumberOfSTRINGInteractors
    ) %>%
    dplyr::distinct() %>%
    dplyr::arrange(HUGO)


  cluePatched <- cluePatched %>% dplyr::transmute(
    HUGO                    = HUGO,
    ReactomePathways     = length(UniProtData$Reactome),
    KEGGPathways         = dplyr::if_else(is.na(NumberOfKEGGPathways), as.integer(0), as.integer(NumberOfKEGGPathways)),
    STRINGInteractors    = dplyr::if_else(is.na(NumberOfSTRINGInteractors), as.integer(0), as.integer(NumberOfSTRINGInteractors)),
    MolecularFunctions   = length(UniProtData$molecularFunction),
    SubcellularLocations = length(UniProtData$subCellularLocation),
    BiologicalProcesses  = length(UniProtData$biologicalProcess)
  )

  # print and save it as CSV
  print(cluePatched)
  return(
    readr::write_csv(cluePatched, MOLECULAR_CSV.OUTPUT)
  )
}

renderCompoundsSummary <- function(cluePatched) {

  ## TODO: EMA counts must be added at least Launched values
  cluePatched <- cluePatched %>%
    dplyr::select(
      HUGO,
      pert_iname,
      final_status,
      pubchem_cid,
      chembl_id,
      drugbank_id,
      PubMedCounter
    ) %>%
    dplyr::distinct() %>%
    dplyr::mutate(
      Preclinical   = stringToNumeric(final_status, 'Preclinical'),
      Phase1        = stringToNumeric(final_status, 'Phase 1'),
      Phase2        = stringToNumeric(final_status, 'Phase 2'),
      Phase3        = stringToNumeric(final_status, 'Phase 3'),
      Launched      = stringToNumeric(final_status, 'Launched'),
      PubMedCounter = dplyr::if_else(is.na(PubMedCounter), as.integer(0), PubMedCounter),
      PubChem       = NA_to_zero(dplyr::if_else(pubchem_cid != '', 1, 0)),
      ChEMBL        = NA_to_zero(dplyr::if_else(chembl_id != '', 1, 0)),
      DrugBank      = NA_to_zero(dplyr::if_else(drugbank_id != '', 1, 0))
    ) %>%
    dplyr::group_by(HUGO) %>%
    dplyr::summarise(
      Preclinical = sum(Preclinical),
      Phase1 = sum(Phase1),
      Phase2 = sum(Phase2),
      Phase3 = sum(Phase3),
      Launched = sum(Launched),
      PubMed = sum(PubMedCounter),
      PubChem = sum(PubChem),
      ChEMBL = sum(ChEMBL),
      DrugBank = sum(DrugBank)
    )

  # print and save it as CSV
  print(cluePatched)
  return(
    readr::write_csv(cluePatched, COMPOUNDS_CSV.OUTPUT)
  )
}

overviewByFinalStatus <- function(cluePatched) {
  cluePatched <- cluePatched %>%
    dplyr::select(
      pert_iname,
      final_status
    ) %>%
    dplyr::distinct() %>%
    dplyr::mutate(
      Preclinical   = stringToNumeric(final_status, 'Preclinical'),
      Phase1        = stringToNumeric(final_status, 'Phase 1'),
      Phase2        = stringToNumeric(final_status, 'Phase 2'),
      Phase3        = stringToNumeric(final_status, 'Phase 3'),
      Launched      = stringToNumeric(final_status, 'Launched'),
      Withdrawn     = stringToNumeric(final_status, 'Withdrawn')
    )

  saveRDS(cluePatched, 'countsByFinalStatus.rds')

  countsByFinalStatus <- list(
    PreclinicalCount  = sum(cluePatched$Preclinical),
    Phase1Count       = sum(cluePatched$Phase1),
    Phase2Count       = sum(cluePatched$Phase2),
    Phase3Count       = sum(cluePatched$Phase3),
    LaunchedCount     = sum(cluePatched$Launched),
    WithdrawnCount    = sum(cluePatched$Withdrawn)
  )
  return(countsByFinalStatus)
}


NA_to_zero <- function(value) {
  return(dplyr::if_else(is.na(value), 0, value))
}
NA_to_zero <- Vectorize(NA_to_zero)


stringToNumeric <- function(actual, expected) {
  return(NA_to_zero(
    dplyr::if_else(
      stringr::str_ends(stringr::str_trim(actual), expected), 1, 0
    )
  ))
}
stringToNumeric <- Vectorize(stringToNumeric)

