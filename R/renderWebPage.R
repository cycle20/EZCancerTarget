##
## renderWebPage.R: Present data as webpage(s)
##

library(assertthat)
library(dplyr)
library(glue)
library(readr)
library(whisker)

##
## Settings of global variables
##
WEB_TEMPLATE <- "web/index.proto.html"
WEB_OUT <- "web/index.html"
CLUE.INPUT <- "clueCollapsed.tsv"
STRING.INPUT <- "string_tab.tsv"
CHEMBL.URL.TEMPLATE <- "https://www.ebi.ac.uk/chembl/target_report_card"

##### Data Section
{
  NE.LOW10 <- c(
    "CD70",
    "CXCR2",
    "MMP7",
    "TP63",
    "ANXA1",
    "KRT5",
    "IFI27",
    "FCGR1A",
    "BIRC3",
    "ITBG6"
  )
  NE.LOW <- c(
    NE.LOW10,
    "ITGAM",
    "YBX3",
    "CTSS",
    "CD5",
    "C1QA",
    "KLRD1",
    "CCL21",
    "MX1",
    "GZMA",
    "ISG15",
    "PRF1",
    "CASP14",
    "CXCL2",
    "CYP35A",
    "MAGEA4",
    "LRMP",
    "ITGB4",
    "KRT17",
    "BCAT1",
    "VSNL1",
    "CAV2",
    "ANXA3",
    "ALDH2",
    "PGC",
    "VAMP8",
    "LAMB3",
    "REL",
    "TNFSF10",
    "PRAME",
    "CES1",
    "COL6A",
    "FOXI1",
    "MYC",
    "PTGS2",
    "CD44",
    "BCL3",
    "ROS1",
    "RAB27B",
    "CXCL10",
    "CCL20",
    "CCL21",
    "CXCL9"
  )
  NE.HIGH <- c(
    "RTN1",
    "NCAM1",
    "DNAJC6",
    "GRP",
    "CDH2",
    "SYP",
    "ID4",
    "ISL1",
    "CHGA",
    "FGF5",
    "FGF10",
    "IL9",
    "HSPB8",
    "HIC1",
    "metrn",
    "TPO",
    "LAMB4",
    "EGLN2",
    "INS",
    "SIX1",
    "L1CAM",
    "MYBL1",
    "PTN",
    "CCNA1",
    "DYSPL4",
    "CDKN2C",
    "ADAM23",
    "TP73",
    "NKX2-1",
    "AMH",
    "RBP1",
    "PAK7",
    "CXXC4",
    "CKB",
    "SOX2",
    "PAK3",
    "SMAD9",
    "DLL3",
    "FZD9",
    "COL9A3",
    "ZIC2",
    "CACNAE1"
  )
}

#' Main function
#'
#' Load data and represent it in HTML format.
#'
#' @return
main <- function() {
  resultCollapsed <- readr::read_tsv(CLUE.INPUT)
  proteinIDs <- readr::read_tsv(STRING.INPUT)
  resultCollapsed <- resultCollapsed %>%
    left_join(proteinIDs, by = c("HUGO" = "preferred_name"))

  renderWebPage(resultCollapsed)
}


renderWebPage <- function(result) {
  ## - this should be an iteration on each HUGO group
  ## - collect pert groups for each gene group
  ## Maybe I shouldn't join result tables in download function.
  result <- result %>% group_by(HUGO)
  collection <- list()
  for (geneGroup in group_split(result)) {
  # browser()
    groupName <- geneGroup$HUGO[1]
    stringID <- geneGroup$protein_external_id[1]
    grouppedByPerts <- geneGroup %>%
      group_by(pert_iname) %>%
      group_split()

    ## collect pert groups per genes and creates
    grouppedByPerts <- multivaluedCellsToHTML(grouppedByPerts)

    collection <- c(collection, list(list(
      target = groupName,
      stringID = stringID,
      data = grouppedByPerts
    )))
  }

  ## export as web page
  message(glue("reading web template: {WEB_TEMPLATE}"))
  template <- readr::read_file(WEB_TEMPLATE)

  targets <- collection

  message(glue("rendering web page, template is '{WEB_TEMPLATE}'"))
  renderResult <- whisker::whisker.render(template, debug = TRUE)
  readr::write_file(renderResult, file = WEB_OUT)
  message(glue("rendered web page is saved into '{WEB_OUT}'"))
}

multivaluedCellsToHTML <- function(dataList) {
  assertthat::assert_that(is.list(dataList))
  assertthat::assert_that(length(dataList) > 0)
  assertthat::assert_that(is.data.frame(dataList[[1]]))

  cellsToHTML <- function(dataframe) {
    # TODO: Does it eliminate duplications?
    dataframe$status_source <- v.statusSourceHTML(dataframe$status_source)
    names(dataframe$status_source) <- NULL # why does it get a name?
    dataframe$chembl_ids <- v.chemblHTML(dataframe$chembl_ids)
    names(dataframe$chembl_ids) <- NULL # why does it get a name?
    dataframe$drugbank_ids <- v.drugBankHTML(dataframe$drugbank_ids)
    names(dataframe$drugbank_ids) <- NULL # why does it get a name?
    return(dataframe)
  }
  dataList <- lapply(dataList, cellsToHTML)
  return(dataList)
}


#' Represent sources as hyperlinks
#'
#' @param statusSource character if it is an URL, it points
#' probably to ClinicalTrials; but other URLs and pure texts
#' can be expected here as well. This function verifies the source
#' value and transform it the most appropriate HTML string.
#'
#' @return HTML string
statusSourceHTML <- function(statusSource) {
  if(is.na(statusSource) || is.null(statusSource)) {
    return(statusSource)
  }
  statusSource <- listShrink(statusSource)

  label <- if(stringr::str_ends(statusSource, pattern = "NCT[0-9]+$")) {
    # if it is an NCT link, get the ID as an URL text
    stringr::str_extract(statusSource, "NCT[0-9]+$")
  } else if (stringr::str_starts(statusSource, "http")) {
    # default URL text
    "Link"
  } else {
    # TODO: plain text?
    return(statusSource)
  }
  # TODO:
  HTMLtext <- aHref(link = statusSource, titleText = label)
  return(HTMLtext)
}

#' ChEMBL Id to HTML link
#'
#' @param chemblId
#'
#' @return Character object containing a HTML code fragment with
#' an "anchor" element.
chemblHTML <- function(chemblId) {
  if(is.na(chemblId) || is.null(chemblId)) {
    return(chemblId)
  }
  chemblId <- listShrink(chemblId)

  HTMLtext <- if(stringr::str_ends(chemblId, pattern = "^CHEMBL[0-9]+$")) {
    link <- glue::glue("{CHEMBL.URL.TEMPLATE}/{chemblId}")
    aHref(link = link, titleText = chemblId)
  } else {
    ## text as is
    chemblId
  }
  return(HTMLtext)
}

drugBankHTML <- function(drugBankId) {
  if(is.na(drugBankId) || is.null(drugBankId)) {
    return(drugBankId)
  }
  drugBankId <- listShrink(drugBankId)

  HTMLtext <- if(stringr::str_ends(drugBankId, pattern = "^DB[0-9]+$")) {
    link <- glue::glue("http://www.drugbank.ca/drugs/{drugBankId}")
    aHref(link = link, titleText = drugBankId)
  } else {
    ## text as is
    drugBankId
  }
  return(HTMLtext)
}

aHref <- function(link, titleText) {
  return(glue::glue("<a href=\"{link}\">{titleText}</a>"))
}

listShrink <- function(text) {
  resultList <- stringr::str_split(text, ",")
  assertthat::assert_that(length(resultList) <= 1)
  returnVal <- if(length(resultList) == 1) {
    ## drop duplications and collapse
    paste0(unique(resultList[[1]]), collapse = ",")
  } else {
    ""
  }
  return(returnVal)
}

## vectorize scalar functions:
v.statusSourceHTML <- Vectorize(statusSourceHTML)
v.chemblHTML <- Vectorize(chemblHTML)
v.drugBankHTML <- Vectorize(drugBankHTML)

## just call the main
main()
