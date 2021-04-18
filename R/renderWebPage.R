##
## renderWebPage.R: Present data as webpage(s)
##


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
SLEEP_TIME <- 15 # wait between two HTTP request in seconds
WEB_TEMPLATE <- "web/template.html"
OUTPUT <- "OUTPUT"
WEB_OUT <- glue::glue("{OUTPUT}/index.target.with.data.html")
WEB_OUT_NODATA <- glue::glue("{OUTPUT}/index.target.no_data.html")
TARGET.INPUT <- "INPUT/target_list.tsv"
# CLUE.INPUT <- glue::glue("{OUTPUT}/clue.tsv")
PATCHED.CLUE.INPUT <- glue::glue("{OUTPUT}/clue_patched.rds")
CHEMBL.URL.TEMPLATE <- "https://www.ebi.ac.uk/chembl/target_report_card"


#' Main function
#'
#' Load data and represent it in HTML format.
#'
#' @return
main <- function() {
  ## read curated input names
  targetList <- readr::read_tsv(TARGET.INPUT) %>%
    mutate(HUGO = target)

  ## read input data prepared by dataPatch.R
  patchedData <- if (endsWith(PATCHED.CLUE.INPUT, ".rds")) {
    readRDS(PATCHED.CLUE.INPUT)
  } else {
    readr::read_tsv(PATCHED.CLUE.INPUT)
  }
  patchedData <- targetList %>%
    left_join(patchedData) %>%
    rowwise() %>%
    mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID)))

  resultHasData <- patchedData %>%
    filter(has_data == TRUE) %>%
    arrange(NE, HUGO)

  resultHasNoData <- patchedData %>%
    filter(has_data == FALSE) %>%
    arrange(NE, HUGO)

  renderWebPage(
    resultHasData, title = "Has CLUE.IO Entries", outputHTML = WEB_OUT
  )
  renderWebPage(
    resultHasNoData, title = "Not found on CLUE.IO", outputHTML = WEB_OUT_NODATA
  )
}


#' Render web page
#'
#' @param result List of data structures to be visualized as a web page.
#' @param title Extension title.
#' @param outputHTML Name of result HTML file.
#'
#' @return Invisible NULL.
renderWebPage <- function(result, title, outputHTML = NULL) {
  assertthat::assert_that(!is.null(outputHTML))

  ## - this should be an iteration on each HUGO group
  ## - collect pert groups for each gene group
  ## Maybe I shouldn't join result tables in download function.
  collection <- list()
  for (geneGroup in unique(result$HUGO)) {
    groupName <- geneGroup
    # overwrite variable with data subset
    geneGroup <- result %>%
      filter(HUGO == groupName)

    hasData <- geneGroup$has_data[1]
    NE <- geneGroup$NE[1]
    UNIPROT_KB_ID <- geneGroup$UNIPROT_KB_ID[1]

    # TODO: Old solution was: geneGroup$protein_external_id[1]
    uniProtData <- result %>%
      select(HUGO, UniProtData) %>%
      filter(HUGO == groupName) %>%
      distinct() %>%
      pull(UniProtData)

    ## unwrap UniProt details
    stringID <- uniProtData[[UNIPROT_KB_ID]]$STRING
    uniProtSubCellular <- uniProtData[[UNIPROT_KB_ID]]$subCellularHTML
    uniProtMolecular <- uniProtData[[UNIPROT_KB_ID]]$molecularFunctionHTML
    ## create an iterable list of list of "pathwayID" and "pathwayName" pairs
    reactomePathways <- uniProtData[[UNIPROT_KB_ID]]$Reactome %>%
      whisker::iteratelist(name = "pathwayID", value = "pathwayName")

    ## group by pert_iname
    # drugBankId <- geneGroup$drugbank_id[1]
    # chemblId <- geneGroup$chembl_id[1]
    # finalStatus <- geneGroup$final_status[1]

    grouppedByPerts <- geneGroup %>%
      # select(-c(HUGO, target, protein_external_id, has_data)) %>%
      select(-c(HUGO, target, has_data)) %>%
      group_by(pert_iname) %>%
      group_split()

    ## collect pert groups per genes and creates
    grouppedByPerts <- multivaluedCellsToHTML(grouppedByPerts)

    collection <- c(collection, list(list(
      target = groupName,
      stringID = stringID,
      data = grouppedByPerts,
      NE = NE,
      UNIPROT_KB_ID = UNIPROT_KB_ID,
      hasData = tolower(hasData),
      uniProtSubCell = uniProtSubCellular,
      uniProtMolecular = uniProtMolecular,
      reactomePathways = reactomePathways
    )))

  } # end of main for loop


  ## export as web page ---------------------------------------------------

  message(glue("reading web template: {WEB_TEMPLATE}"))
  template <- readr::read_file(WEB_TEMPLATE)

  targets <- collection
  creationTime <- Sys.time()
  message(glue("rendering web page, template is '{WEB_TEMPLATE}'"))
  renderResult <- whisker::whisker.render(template, debug = TRUE)
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
multivaluedCellsToHTML <- function(dataList) {
  assertthat::assert_that(is.list(dataList))
  assertthat::assert_that(length(dataList) > 0)
  assertthat::assert_that(is.data.frame(dataList[[1]]))

  cellsToHTML <- function(dataframe) {
    # TODO: Does it eliminate duplications?
    ## collapsing moa
    moa <- paste(unique(dataframe$moa), collapse = ", <br/>")
    pubchem_cid <- paste(unique(dataframe$pubchem_cid), collapse = ", <br/>")
    chembl_id <- paste(unique(dataframe$chembl_id), collapse = ", <br/>")
    dataframe <- dataframe %>%
      # select(-c(moa, pubchem_cid, chembl_id)) %>%
      select(
        pert_iname,
        status_source,
        drugbank_id,
        final_status
      ) %>%
      distinct() %>%
      mutate(
        drugbank_id = drugBankHTML(drugbank_id),
        chembl_id = chembl_id, # chemblHTML(chembl_id),
        pubchem_cid = pubchem_cid # pubChemHTML(pubchem_cid)
      )
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


#' Create DrugBank links
#'
#' @param drugBankId DrugBank ID(s)
#'
#' @return HTML "a" snippet(s) that can be used in HTML document directly.
drugBankHTML <- function(drugBankId) {
  if(is.na(drugBankId) || is.null(drugBankId)) {
    return(drugBankId)
  }
  drugBankId <- listShrink(drugBankId)

  HTMLtext <- if(stringr::str_ends(drugBankId, pattern = "^DB[0-9]+$")) {
    link <- glue::glue("http://www.drugbank.ca/drugs/{drugBankId}")
    link <- glue::glue("http://www.drugbank.ca/drugs/{drugBankId}")
    aHref(link = link, titleText = drugBankId)
  } else {
    ## text as is
    drugBankId
  }
  return(HTMLtext)
}


#' Create PubChem links
#'
#' @param pubChemId PubChem ID(s)
#'
#' @return HTML "a" snippet(s) that can be used in HTML document directly.
pubChemHTML <- function(pubChemId) {
  if(is.na(pubChemId) || is.null(pubChemId)) {
    return(pubChemId)
  }
  #browser(expr = startsWith(pubChemId, "3117"))
  pubChemId <- listShrink(pubChemId)
  HTMLtext <- if(all(stringr::str_ends(pubChemId, pattern = "^[0-9]+$"))) {
    retVal <- ""
    for (id in pubChemId) {
      url <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/compound/{id}")
      href <- aHref(link = url, titleText = id)
      retVal <- paste0(retVal, href)
    }
    # result of the accumulation loop above
    retVal
  } else {
    ## text as is
    pubChemId
  }
  return(HTMLtext)
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


#' Shrink a simple list
#'
#' listShrink splits the input vector and return a distinct list of the
#' vector of elements.
#'
#' @param text Character vector represents a list.
#' Its elements are separated by "," or "|" characters.
#'
#' @return Unique elements represented by a vector or NULL if the input
#' string cannot be splitted.
listShrink <- function(text) {
  ## expected separators with optional space: "," and "|"
  resultList <- stringr::str_split(text, " ?(,|\\|) ?")
  assertthat::assert_that(length(resultList) <= 1)
  returnVal <- if(length(resultList) == 1) {
    ## drop duplications and collapse
    unique(resultList[[1]])
  } else {
    NULL
  }
  return(returnVal)
}


#' #' Scrape GeneCards webpage
#' #'
#' #' @param name gene name
#' #'
#' #' @return Table of localization values.
#' scrapeGeneCardsSnippets <- function(name) {
#'   browser()
#'   print(glue::glue("scraping: GeneCards {name}"))
#'   ## empty names is not accepted
#'   assertthat::assert_that(
#'     !(is.null(name) || is.na(name) || stringr::str_length(name) == 0)
#'   )
#'   url <- glue::glue("https://www.genecards.org/cgi-bin/carddisp.pl?gene={name}")
#'   page <- rvest::read_html(url)
#'
#'   compartmentsTable <- page %>%
#'     rvest::html_elements("#compartmentsTable")
#'
#'   hasSubCellFigure <- length(compartmentsTable) == 1 &&
#'     xml2::xml_length(compartmentsTable) == 2
#'   htmlSnippet <- if (hasSubCellFigure) {
#'     ## simple verifications
#'     assertthat::assert_that(
#'       rvest::html_name(compartmentsTable) == "table"
#'     )
#'
#'     toString(compartmentsTable)
#'   } else {
#'     glue::glue("<div>Subcellular table not found</div>")
#'   }
#'
#'   return(htmlSnippet)
#' }


## just call the main
main()

warnings()
