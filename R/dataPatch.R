##
## dataPatch.R: supply missing data items for clue.io compounds
##


library(assertthat)
library(dplyr)
library(glue)
library(readr)
library(rvest)
library(stringr)

set.seed(739)
##
## Settings of global variables
##
SLEEP_TIME <- 15 # wait between two HTTP request in seconds
OUTPUT <- "OUTPUT"
CACHE <- glue::glue("{OUTPUT}/DATAPATH_CACHE")
TARGET.INPUT <- "INPUT/target_list.tsv"
CLUE.INPUT <- glue::glue("{OUTPUT}/clue.tsv")
CHEMBL.URL.TEMPLATE <- "https://www.ebi.ac.uk/chembl/target_report_card"

PUBMED <- "https://pubmed.ncbi.nlm.nih.gov"
PUBMED.SORT.REL <- paste0(PUBMED, "?term={compound}&sort=relevance")
PUBMED.SORT.DATE <- paste0(PUBMED, "?term={compound}&sort=date")
PUBMED.RESULT.XPATH <-
  '/html/body/main//section[@class="search-results-list"]//article[1]//a'



#' Main function
#'
#' Load data and represent it in HTML format.
#'
#' @return
main <- function() {
  ## read curated input names
  targetList <- readr::read_tsv(TARGET.INPUT) %>%
    mutate(HUGO = target)

  result <- readr::read_tsv(CLUE.INPUT)
  result <- targetList %>%
    left_join(result) %>%
    rowwise() %>%
    mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID)))

  # resultHasData <- result %>%
  #   filter(has_data == TRUE) %>%
  #   arrange(NE, HUGO)
  #
  # resultHasNoData <- result %>%
  #   filter(has_data == FALSE) %>%
  #   arrange(NE, HUGO)

  result <- patch(result)
}


patch <- function(clueTable) {


  # TODO: phase I... : clinicalTrials

  # TODO: Launched: FDA / EMA (maybe DrugBank?)

  # TODO: !!!!! pubChem
  # TODO: JavaScript issue: result page is dynamic
  pubChem <- function(compound, inChIKey) {
    assertthat::assert_that(!is.na(compound))
    # assertthat::assert_that(!is.na(inChIKey))
    searchURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/#query={compound}")
    #compoundURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/compound/{id}")
    html <- rvest::read_html(searchURL)
    return(html)
  }

  ##
  ## count of requests and estimated download times...
  ##
  pubMedPerts <- clueTable %>%
    select(pert_iname, final_status, status_source) %>%
    filter(final_status == "Preclinical" && is.na(status_source)) %>%
    distinct()
  pubMedCount <- pubMedPerts %>% nrow()
  pubMedSecs <- pubMedCount * 2 * 35

  ## pubMed searches
  ## TODO: UPDATE the clueTable
  print(Sys.time())
  pubMedSearchResults <- sapply(
    pubMedPerts %>% pull(pert_iname),
    pubMed,
    simplify = FALSE
  )
  print(Sys.time())

  fdaCount <- clueTable %>%
    select(pert_iname, final_status, orange_book) %>%
    filter(final_status == "Launched" && !is.na(orange_book)) %>%
    distinct() %>% nrow()
  fdaSecs <- fdaCount * 2 * 35

  uniProtSecs <- 99 * 2 * 35 # 6930
  chEmblPubChemCount <- clueTable %>%
    filter(is.na(chembl_id) && is.na(pubchem_cid)) %>%
    distinct() %>% nrow()
  chEmblPubChemSecs <- chEmblPubChemCount * 35

  print(glue::glue(
    "pubMedTime: {pubMedSecs}; FDATime: {fdaSecs}"
  ))
  print(glue::glue(
    "UniProtTime: {uniProtSecs}; ChEmbl/PubChem: {chEmblPubChemSecs}"
  ))
  sumSecs <- pubMedSecs + fdaSecs + uniProtSecs + chEmblPubChemSecs
  hours <- sumSecs / 60 / 60
  print(glue::glue("sum: {sumSecs} secs; {hours} hrs"))
  browser()
}


#' ChEMBL Id
#'
#' @param chemblId
#'
#' @return ChEMBL Id or NA
chemblXML <- function(chemblId) {
  ## TODO: chEmbl
  ## https://www.ebi.ac.uk/chembl/api/data/target/search?q=ANXA3

  stop("Not implemented")
}


#' Extract PMIDs
#'
#' @param compound
#' @param inChIKey
#'
#' @return List containing the most relevant and the most recent IDs
pubMed <- function(compound, inChIKey = NA) {
  assertthat::assert_that(!is.na(compound))

  ## search by relevance
  searchURL <- glue::glue(PUBMED.SORT.REL)
  result <- getPageCached(searchURL, sleepTime = SLEEP_TIME)
  articleLink <- result$document %>%
    rvest::html_elements(xpath = PUBMED.RESULT.XPATH)
  mostRelevantId <- rvest::html_attr(articleLink, name = "data-article-id")

  searchURL <- glue::glue(PUBMED.SORT.DATE)
  result <- getPageCached(searchURL, sleepTime = SLEEP_TIME)
  articleLink <- result$document %>%
    rvest::html_elements(xpath = PUBMED.RESULT.XPATH)
  mostRecentId <- rvest::html_attr(articleLink, name = "data-article-id")

  return(list(
    compound = compound,
    mostRelevant = mostRelevantId,
    mostRecent = mostRecentId
  ))
}


#' Look up PubChem ID
#'
#' @param inChIKey International Chemical Identifier
#'
#' @return PubChem ID or NA
pubChemId <- function(inchiKey) {
  # other possible resolvers:
  # https://en.wikipedia.org/wiki/International_Chemical_Identifier#InChI_resolvers

  stop("Not implemented")

  searchURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/TODO")
  compoundURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/compound/{id}")
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


#' Load and cache files
#'
#' @param url URL pointing to XML/HTML file.
#' @param sleepTime sleep interval in seconds before download,
#' if content is not cached. Default value is 3.
#'
#' @return XML representation of the file content.
getPageCached <- function(url, sleepTime = 3) {
  cacheFile <- glue::glue(CACHE, "/cache.tsv")
  ## initialize tibble object
  cache <- if (file.exists(cacheFile)) {
    readr::read_tsv(cacheFile, col_types = "ccT")
  } else {
    dir.create(CACHE, recursive = TRUE)
    tibble::new_tibble(
      list(URL = "INIT", cache_object = "_", time = Sys.time()),
      nrow = 1
    )
  }

  # load from cache object
  {
    fileName <- cache %>%
      filter(URL == url) %>%
      select(cache_object)

    fileName <- if (nrow(fileName) == 1) {
      fileName %>% pull(cache_object)
    } else {
      character(0)
    }
    notFound <- length(fileName) == 0
    if(notFound) {
      now <- Sys.time()
      fileName <- glue::glue(
        "{getRandom()}-{as.integer(now)}"
      )
    }

    path <- glue::glue("{CACHE}/{fileName}")
    if (!notFound && file.exists(path)) {
      print(glue::glue("{Sys.time()} :: from cache: {url}"))
      # returning from cache
      return(list(
        document = rvest::read_html(path),
        fromCache = TRUE
      ))
    } else if (!notFound && !file.exists(path)) {
      stop(glue::glue("file not found: {path} *** url: {url}"))
    } else {
      # if file doesn't exists
      # ...sleep
      if (sleepTime > 0) {
        print(glue::glue("# sleeping {sleepTime} secs"))
        Sys.sleep(sleepTime)
      }
      # ...download
      resultPage <- rvest::read_html(url)
      print(glue::glue("{Sys.time()} :: donwloaded: {url}"))
      # ...and save
      write_file(toString(resultPage), file = path)
      # ...update cache
      {
        newRow <- tibble::tibble_row(
          URL = url,
          cache_object = fileName,
          time = now
        )
        cache <- cache %>%
          tibble::add_row(newRow)
      }
      # ...save updated cache
      readr::write_tsv(x = cache, file = cacheFile)
      # returning recently downloaded page
      return(list(
        document = resultPage,
        fromCache = FALSE
      ))
    }
  }
}


#' Random number generator
#'
#' Generates random integers between 1 and 10000.
#'
#' @return Random integer number.
getRandom <- function() {
  numbers <- runif(10, min = 1, max = 10000)
  return(
    floor(sample(numbers, 1))
  )
}

## just call the main
main()

warnings()
