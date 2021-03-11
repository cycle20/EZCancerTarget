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

  browser()

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
    dataframe$status_source <- v.statusSourceHTML(dataframe$status_source)
    names(dataframe$status_source) <- NULL # why does it get a name?
    return(dataframe)
  }
  dataList <- lapply(dataList, cellsToHTML)
  return(dataList)
}


#' Represent sources as hyperlinks
#'
#' @param statusSource character if it is an URL, it points
#' probably to ClinicalTrials; but other URLs and pure texts
#' can be expected here as well.
#'
#' @return HTML string
statusSourceHTML <- function(statusSource) {
  if(is.na(statusSource) || is.null(statusSource)) {
    return(statusSource)
  }
  # browser()
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
  HTMLcode <- glue::glue("<a href=\"{statusSource}\">{label}</a>")
  return(HTMLcode)
}

v.statusSourceHTML <- Vectorize(statusSourceHTML)


## just call the main
main()
