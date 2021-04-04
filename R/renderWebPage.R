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
CLUE.INPUT <- glue::glue("{OUTPUT}/clueCollapsed.tsv")
STRING.INPUT <- glue::glue("INPUT/string_tab.tsv")
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

  resultCollapsed <- readr::read_tsv(CLUE.INPUT)
  proteinIDs <- readr::read_tsv(STRING.INPUT)
  resultCollapsed <- targetList %>%
    left_join(resultCollapsed) %>%
    left_join(proteinIDs, by = c("HUGO" = "preferred_name")) %>%
    rowwise() %>%
    mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID)))

  resultHasData <- resultCollapsed %>%
    filter(has_data == TRUE) %>%
    arrange(NE, HUGO)

  resultHasNoData <- resultCollapsed %>%
    filter(has_data == FALSE) %>%
    arrange(NE, HUGO)

  renderWebPage(resultHasData, outputHTML = WEB_OUT)
  renderWebPage(resultHasNoData, outputHTML = WEB_OUT_NODATA)
}


#' Render web page
#'
#' @param result List of data structures to be visualized as a web page.
#' @param outputHTML Name of result HTML file.
#'
#' @return Invisible NULL.
renderWebPage <- function(result, outputHTML = NULL) {
  assertthat::assert_that(!is.null(outputHTML))

  ## - this should be an iteration on each HUGO group
  ## - collect pert groups for each gene group
  ## Maybe I shouldn't join result tables in download function.
  result <- result %>%
    #filter(HUGO == "ANXA1") %>%
    #head(2) %>%
    group_by(HUGO)
  collection <- list()
  for (geneGroup in group_split(result)) {
    groupName <- geneGroup$HUGO[1]
    stringID <- geneGroup$protein_external_id[1]
    hasData <- geneGroup$has_data[1]
    NE <- geneGroup$NE[1]
    UNIPROT_KB_ID <- geneGroup$UNIPROT_KB_ID[1]

    ## group by pert_iname
    # drugBankId <- geneGroup$drugbank_id[1]
    # chemblId <- geneGroup$chembl_id[1]
    # finalStatus <- geneGroup$final_status[1]

    grouppedByPerts <- geneGroup %>%
      select(-c(HUGO, target, protein_external_id, has_data)) %>%
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
      uniProtSubCell = scrapeUniProtSnippets(UNIPROT_KB_ID, groupName)
      # geneCardsSubCellTable = scrapeGeneCardsSnippets(groupName)
    )))

    print(
      glue::glue("waiting {SLEEP_TIME} seconds before the next download...")
    )
    Sys.sleep(SLEEP_TIME)
  } # end of main for loop

  ## export as web page
  message(glue("reading web template: {WEB_TEMPLATE}"))
  template <- readr::read_file(WEB_TEMPLATE)

  targets <- collection

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
    return(
      dataframe %>%
        rowwise() %>%
        mutate(
          status_source = statusSourceHTML(status_source, pert_iname),
          drugbank_id = drugBankHTML(drugbank_id),
          chembl_id = chemblHTML(chembl_id),
          pubchem_cid = pubChemHTML(pubchem_cid))
    )
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
#' @param pert_iname name of the perturbagen
#'
#' @return HTML string
statusSourceHTML <- function(statusSource, pert_iname) {
  if (is.na(pert_iname) || is.null(pert_iname)) {
    return(pert_iname)
  } else if(is.na(statusSource) || is.null(statusSource)) {
    # TODO: sophisticated query: most relevant link and most recent
    link <- "https://pubmed.ncbi.nlm.nih.gov/?term={pert_iname}&sort=relevance"
    link <- glue::glue(link)
    htmlText <- aHref(link = link, titleText = "PubMed Search")
    print(htmlText)

    return(htmlText)
  }
  statusSourceList <- listShrink(statusSource)
  htmlText <- ""
  for (statusSource in statusSourceList) {
    label <- if(stringr::str_starts(statusSource,
      pattern = "https?://.*clinicaltrials.gov/.+NCT[0-9]+")) {
      "ClinicalTrials"
    } else if (stringr::str_starts(statusSource,
      "https?://.*ncbi.*gov/pubmed")) {
      "PubMed"
    } else if (stringr::str_starts(statusSource, "https?://.+fda.gov/")) {
      "FDA"
    } else if (stringr::str_starts(statusSource,
      "https?://.*dailymed.*.gov/")) {
      "DailyMed"
    } else if (stringr::str_starts(statusSource, "https?://.*wikipedia.org/")) {
      "Wikipedia"
    } else if (stringr::str_starts(statusSource, "https?://www.drugs.com/")) {
      "drugs.com"
    } else if (stringr::str_starts(statusSource, "https?://.*springer.com/")) {
      "Springer"
    } else if (stringr::str_starts(statusSource, "https?://docslide.*/")) {
      "docslide"
    } else if (stringr::str_starts(statusSource, "https://guidebook.com/")) {
      "guidebook"
    } else if (stringr::str_starts(statusSource, "http")) {
      # default URL text
      "Unexpected Source"
    } else {
      ## plain text transformed to a tool-tipped entity
      html <- glue::glue("<span data-bs-toggle=\"tooltip\" ",
        "title=\"{statusSource}\" data-bs-placement=\"right\">",
        "{statusSource}</span>")
      return(html)
    }
    # TODO:
    htmlText <- paste0(htmlText, aHref(link = statusSource, titleText = label))
  }
  return(htmlText)
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
  return(glue::glue("<a href=\"{link}\">{titleText}</a>"))
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


#' Scrape UniProt webpage
#'
#' @param id an UniProt ID
#' @param name gene name
#'
#' @return Visualization of the subcellular location of the protein.
scrapeUniProtSnippets <- function(id, name) {
  ## empty id is not accepted
  # assertthat::assert_that(
  #   !(is.null(id) || is.na(id) || stringr::str_length(id) == 0)
  # )
  print(glue::glue("scraping: UniProt {id} {name}"))
  if (is.null(id) || is.na(id) || stringr::str_length(id) == 0) {
    warning(
      glue::glue("UniProt id of {name} is missing: '{id}'"),
      immediate. = TRUE
    )
    return("")
  }

  url <- glue::glue("https://www.uniprot.org/uniprot/{id}")
  page <- rvest::read_html(url)

  subcellular_location <- page %>%
    rvest::html_elements("#subcellular_location>:not(#topology_section)")

  hasSubCellFigure <- length(subcellular_location) >= 2 &&
    xml2::xml_length(subcellular_location) > 0
  htmlSnippet <- if (hasSubCellFigure) {
    subCellNode <- subcellular_location[[2]]
    ## simple verifications
    assertthat::assert_that(
      rvest::html_name(subCellNode) == "div"
    )
    assertthat::assert_that(
      endsWith(rvest::html_attr(subCellNode, name = "id"), id)
    )

    ## TO BE REMOVED: xml2::write_html(subCellNode, "subcellular_location.html")
    toString(subCellNode)
  } else {
    glue::glue("<div>Subcellular figure not found</div>")
  }

  return(htmlSnippet)
}


#' Scrape GeneCards webpage
#'
#' @param name gene name
#'
#' @return Table of localization values.
scrapeGeneCardsSnippets <- function(name) {
  browser()
  print(glue::glue("scraping: GeneCards {name}"))
  ## empty names is not accepted
  assertthat::assert_that(
    !(is.null(name) || is.na(name) || stringr::str_length(name) == 0)
  )
  url <- glue::glue("https://www.genecards.org/cgi-bin/carddisp.pl?gene={name}")
  page <- rvest::read_html(url)

  compartmentsTable <- page %>%
    rvest::html_elements("#compartmentsTable")

  hasSubCellFigure <- length(compartmentsTable) == 1 &&
    xml2::xml_length(compartmentsTable) == 2
  htmlSnippet <- if (hasSubCellFigure) {
    ## simple verifications
    assertthat::assert_that(
      rvest::html_name(compartmentsTable) == "table"
    )

    toString(compartmentsTable)
  } else {
    glue::glue("<div>Subcellular table not found</div>")
  }

  return(htmlSnippet)
}


## just call the main
main()

warnings()