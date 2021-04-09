##
## dataPatch.R: supply missing data items for clue.io compounds -----------
##

##
## Libraries --------------------------------------------------------------
##
library(assertthat)
library(dplyr)
library(glue)
library(httr)
library(readr)
library(rvest)
library(stringr)
library(xml2)

set.seed(739)
options(width = 160)

##
## Settings of global variables -------------------------------------------
##
SLEEP_TIME <- 35 # wait between two HTTP request in seconds
INGREDIENT_FILTER <- FALSE # Is FDA Label API request strict or not?
OUTPUT <- "OUTPUT"
CACHE <- glue::glue("{OUTPUT}/DATAPATH_CACHE")
TARGET.INPUT <- "INPUT/target_list.tsv"
CLUE.INPUT <- glue::glue("{OUTPUT}/clue.tsv")
# CLUE.PATCHED.OUTPUT <- glue::glue("{OUTPUT}/clue_patched.tsv")
CLUE.PATCHED.OUTPUT <- glue::glue("{OUTPUT}/clue_patched.rds")
CHEMBL.URL.TEMPLATE <- "https://www.ebi.ac.uk/chembl/target_report_card"

TOOL.NAME <- "https://github.com/cycle20/scancer/"

PUBMED <- "https://pubmed.ncbi.nlm.nih.gov"
PUBMED.SORT.REL <- paste0(PUBMED, "?term={compound}&sort=relevance")
PUBMED.SORT.DATE <- paste0(PUBMED, "?term={compound}&sort=date")
PUBMED.RESULT.XPATH <-
  '/html/body/main//section[@class="search-results-list"]//article[1]//a'

UNIPROT.HTML.TEMPL = "https://www.uniprot.org/uniprot/{id}"
UNIPROT.XML.TEMPL = "https://www.uniprot.org/uniprot/{id}.xml"


##
## Functions --------------------------------------------------------------
##

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

  #checkDataCoverage(result)

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

  ## Append UniProt details
  result <- xmlUniProt(result)
  result <- patch(result)
  ## save tibble as RDS since write_tsv is not an obvious way
  saveRDS(result, file = CLUE.PATCHED.OUTPUT)
  # TODO: readr::write_tsv(result, file = CLUE.PATCHED.OUTPUT)
  # TODO: or JSON format might be a portable solution

  checkDataCoverage(result)
}


#' Check gaps in our data set
#'
#' @param clueTable
#'
#' @return Invisible NULL
checkDataCoverage <- function(clueTable) {
  separator <- paste(rep("#", 75), collapse = "")
  print(glue::glue("\n\n{separator}"))
  print(glue::glue("{separator}", "  !!! START OF DATA INTEGRITY TEST !!!"))
  print(glue::glue("{separator}\n\n"))

  ## internal helper function
  checkTable <- function(table, msg) {
   n <- nrow(table)
   prefix <- glue::glue("\n\n>>>>>>>> {msg}: {n} ...")
   if(nrow(table) > 0) {
     print(glue::glue("{prefix} IS NOT OK!"))
     print(table)
   } else
     print(glue::glue("{prefix} IS OK!"))
  }

  ## FDA Orange issue
  distinctTable <- clueTable %>%
    select(
      pert_iname,
      # moa,
      final_status,
      status_source,
      orange_book
    ) %>%
    distinct() %>%
    rowwise() %>%
    filter(grepl("FDA Orange", status_source))
  checkTable(distinctTable, "FDA Orange")

  ## FDA Orange issue V2
  distinctTable <- clueTable %>%
    select(
      pert_iname,
      final_status,
      status_source,
      orange_book
    ) %>%
    distinct() %>%
    rowwise() %>%
    filter(!is.na(orange_book) && is.na(status_source))
  checkTable(distinctTable, "FDA.V2 orange_book has value")

  ## FDA Launched check
  distinctTable <- clueTable %>%
    select(
      pert_iname,
      final_status,
      status_source,
      orange_book
    ) %>%
    distinct() %>%
    rowwise() %>%
    filter(final_status == "Launched" &&
      is.na(orange_book) && is.na(status_source))
  checkTable(distinctTable, "FDA Launched check")

  ## PubChem/ChEMBL check
  distinctTable <- clueTable %>%
    select(
      pert_iname,
      final_status,
      pubchem_cid,
      chembl_id,
      inchi_key,
      pert_id,
      ttd_id,
      drugbank_id,
      source,
      status_source
    ) %>%
    distinct() %>%
    rowwise() %>%
    filter(is.na(pubchem_cid) && is.na(chembl_id))
  checkTable(distinctTable, "PubChem/ChEMBL check")


##  print("Foreced quit")
##  quit(save = "no")


  print(glue::glue("{separator}"))
  print(glue::glue("{separator}", "  !!! END OF DATA INTEGRITY TEST !!!"))
  print(glue::glue("{separator}"))

  return(invisible(NULL))
}


#' "Patch" data gaps in CLUE table
#'
#' @param clueTable
#'
#' @return Invisible NULL
patch <- function(clueTable) {


  # TODO: phase I... : clinicalTrials

  # TODO: Launched: FDA / EMA (maybe DrugBank?)

  ##
  ## count of requests and estimated download times...
  ##

  ## pubMed searches
  ## TODO: UPDATE the clueTable
  pubMedPerts <- clueTable %>%
    select(pert_iname, final_status, status_source) %>%
    filter(final_status == "Preclinical" && is.na(status_source)) %>%
    distinct()
  pubMedCount <- pubMedPerts %>% nrow()
  pubMedSecs <- pubMedCount * 2 * 35

  print(Sys.time())
  # pubMedSearchResults <- sapply(
  #   pubMedPerts %>% pull(pert_iname),
  #   pubMed,
  #   simplify = FALSE
  # )
  print(Sys.time())

  ## FDA searches
  ## TODO: UPDATE the clueTable
  fdaPerts <- clueTable %>%
    select(pert_iname, final_status, orange_book) %>%
    filter(final_status == "Launched" && !is.na(orange_book)) %>%
    distinct()
  fdaCount <- fdaPerts %>% nrow()
  fdaSecs <- fdaCount * 2 * 35

  print(Sys.time())
  fdaSearchResults <- sapply(
    fdaPerts %>% pull(pert_iname),
    fdaLabel,
    simplify = FALSE
  )
  print(Sys.time())
  # TODO: export - debug purposed
  concatenated <- paste(fdaSearchResults, collapse = " ")
  readr::write_file(concatenated, "FDAResult.html")

  ## transform status_source based on FDA results
  clueTable <- clueTable %>%
    mutate(status_source = if_else(
      hasName(fdaSearchResults, pert_iname) &&
        !is.null(fdaSearchResults[[pert_iname]]),
      # WHAT AN UGLY HACK! How can I eliminate this paste0 call?
      paste0("", fdaSearchResults[[pert_iname]]),
      status_source
    ))

  ## TODO: chEbml data...

  uniProtSecs <- 99 * 2 * 35 # 6930
  chEmblPubChemCount <- clueTable %>%
    filter(is.na(chembl_id) && is.na(pubchem_cid)) %>%
    distinct() %>% nrow()
  chEmblPubChemSecs <- chEmblPubChemCount * 35

  hour <- 60 * 60
  print(glue::glue(
    "pubMedTime: {pubMedSecs} / {pubMedSecs / hour}; ",
    "FDATime: {fdaSecs} / {fdaSecs / hour}"
  ))
  print(glue::glue(
    "UniProtTime: {uniProtSecs} / {uniProtSecs / hour}; ",
    "ChEmbl/PubChem: {chEmblPubChemSecs} / {chEmblPubChemSecs / hour}"
  ))
  sumSecs <- pubMedSecs + fdaSecs + uniProtSecs + chEmblPubChemSecs
  print(glue::glue("sum: {sumSecs} secs; {sumSecs / hour} hrs"))

  ## return updated tables
  return(clueTable)
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

  # TODO: #########   PUBMED re-cache!!!!!!!!!

  # TODO: PMC? And embargoed articles? https://www.ncbi.nlm.nih.gov/pmc

  # TODO: https://drugs.ncats.io/substances?facet=Pharmacology%2FInhibitor

  # TODO: https://drugs.ncats.io/drug/MRK240IY2L

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


##
## Labels for Launched Drugs/Compounds ------------------------------------
##

ema <- function() {
  # TODO https://www.ema.europa.eu/en/medicines/field_ema_web_categories%253Aname_field/Human?sort=search_api_aggregation_sort_ema_active_substance_and_inn_common_name&order=asc&search_api_views_fulltext=Disulfiram
  stop("Not implemented")
}


fdaLabel <- function(pert_iname) {
  # DailyMed - NIH’s labeling search tool over 130,000 labeling documents for
  # prescription drugs (including biological products, vaccines, blood products,
  # cellular and gene therapy products), over-the-counter drugs, homeopathic
  # drugs, animal drugs, and other products.
  # FDALabel - FDA’s labeling search tool over 130,000 labeling documents.
  # FDALabel and DailyMed have the same database but have different search
  # functions and different displays of search results.

  # More resources: https://www.fda.gov/drugs/laws-acts-and-rules/prescription-drug-labeling-resources

  ## TODO: https://www.fda.gov/science-research/bioinformatics-tools/fdalabel-full-text-search-drug-product-labeling#Live%20Queries
  ## Biomarker “BRCA or BRAF”

  # based on https://nctr-crs.fda.gov/fdalabel/ui/search results
  fdaDownload <- function(url) {
    if(startsWith(url, CACHE)) {
      ## if reading from cache...
      return(readr::read_file(url))
    }

    if (!INGREDIENT_FILTER) {
      ## Simple search:
      ## ..............
      ## Labeling type: "Human Rx", "Human OTC"
      ## Labeling Full Text Search
      # postData <- paste0('{"criteria":[{"criteria":[',
      #   '{"sourceEntity":"document-type","documentTypeCodes":',
      #   '["34391-3","34390-5", "53404-0"]},{"sourceEntity":"spl-text",',
      #   '"textQuery":"',
      #   pert_iname,
      #   '","advanced":false}],"logOps":["a","a"]}],"logOps":[]}')
      postData <- paste0(
        '{"criteria":[{
          "criteria": [
            {
              "sourceEntity": "document-type",
              "documentTypeCodes": [
                "34391-3",
                "34390-5",
                "53404-0"
              ]
            },
            {
              "sourceEntity": "product",
              "nameType": "ANY",
              "namePatternType": "SUBSTR",
              "namePattern": "', pert_iname, '"
            }
          ],
          "logOps": ["a","a"]
        }],"logOps":[]}'
      )
    } else {
      ## Simple search: ingredient filter is ON
      ## ......................................
      postData <- paste0(
        '{"criteria":[{"criteria":[',
        '{"sourceEntity":"document-type","documentTypeCodes":',
        ## Labeling type: "Human Rx", "Human OTC", "Vaccine"
        '["34391-3","34390-5","53404-0"]},{"sourceEntity":"section",',
        '"textQuery":"',
        pert_iname,
        ## Labeling Section(s): "ACTIVE INGERDIENT"
        '","selectedLabelingType":"0","sectionTypeCode":"2-55106-9",',
        '"advanced":false}],"logOps":["a","a"]}],"logOps":[]}'
      )
    }

    ## compress by removing white spaces
    postData <- stringr::str_remove_all(postData, "[[:space:]]")
    # response <- httr::HEAD(url, body = postData, config = add_headers(
    #   "Content-Type" = "application/json; charset=UTF-8",
    #   "Accept" = "application/json"
    # ))

    ## send the POST request
    response <- httr::POST(url, body = postData, config = add_headers(
      "Content-Type" = "application/json; charset=UTF-8",
      "Accept" = "application/json"
    ))
    responseContent <- httr::content(response, as = "text", encoding = "UTF-8")

    return(responseContent)
  }

  #labelTable <- jsonlite::read_json(glue::glue("{CACHE}/{pret_iname.json}"))
  url = paste0("https://nctr-crs.fda.gov/fdalabel/services/spl/summaries",
               "?pert3=", pert_iname, "&ingr=", INGREDIENT_FILTER)

  ## cached download
  downloadResult <- getPageCached(
    url, sleepTime = SLEEP_TIME, downloadFunc = fdaDownload
  )

  ## "compressing" result set
  parsedResult <- jsonlite::fromJSON(downloadResult$document)
  if (parsedResult$totalResultsCount == 0) {
    print(glue::glue("fdaLabel :: {pert_iname} :: results not found"))
    return(invisible(NA))
  }

  ## filtering
  pertNamePattern <- gsub("-", ".{,4}", pert_iname)
  products <- parsedResult$resultsArray %>%
    filter(
      !grepl("first aid", productNames, ignore.case = TRUE)
        && (!grepl(" kit", productNames, ignore.case = TRUE)
            && !grepl("KIT", dosageForms))
    )

  if ((products %>% nrow()) == 0) {
    print(glue::glue("{pert_iname} :: results not found after filtering"))
    return(invisible(NA))
  }

  products <- products %>%
    ## ACTIVE INGREDIENTS UNIIs ---------- check it!!!
    group_by(actIngrUniis) %>%
    filter(marketDates == max(marketDates)) %>%
    ungroup() %>%
    arrange(actIngrNames)
  print(glue::glue(
    "{pert_iname} :: fdaLabel products shrinked from ",
    "{parsedResult$totalResultsCount} to {nrow(products)}"
  ))

  ## TODO: https://nctr-crs.fda.gov/fdalabel/services/spl/set-ids/ab85719a-53de-547c-e053-2a95a90ae578/spl-doc?hl=retinol
  labelURLTemplate =
    "https://nctr-crs.fda.gov/fdalabel/services/spl/set-ids/{setId}/spl-doc"
  anchorTemplate = '<a href="{labelURL}" target="_blank">{productNames}</a>'

  htmlOfURLs <- products %>%
    mutate(
      labelURL = glue::glue(labelURLTemplate),
      htmlURL = glue::glue(anchorTemplate)
    ) %>%
    select(labelURL, htmlURL)

  resultHTML <- htmlOfURLs %>% pull(htmlURL)
  resultHTML <- paste(resultHTML, collapse = "<br/>")

  ## TODO: https://nctr-crs.fda.gov/fdalabel/ui/database-updates
  return(resultHTML)
}

#' #' Look up PubChem ID
#' #'
#' #' @param inChIKey International Chemical Identifier
#' #'
#' #' @return PubChem ID or NA
#' pubChemId <- function(inchiKey) {
#'   # other possible resolvers:
#'   # https://en.wikipedia.org/wiki/International_Chemical_Identifier#InChI_resolvers
#'
#'   stop("Not implemented")
#'
#'   searchURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/TODO")
#'   compoundURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/compound/{id}")
#'
#'   # # TODO: !!!!! pubChem
#'   # # TODO: JavaScript issue: result page is dynamic
#'   # pubChem <- function(compound, inChIKey) {
#'   #   assertthat::assert_that(!is.na(compound))
#'   #   # assertthat::assert_that(!is.na(inChIKey))
#'   #   searchURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/#query={compound}")
#'   #   #compoundURL <- glue::glue("https://pubchem.ncbi.nlm.nih.gov/compound/{id}")
#'   #   html <- rvest::read_html(searchURL)
#'   #   return(html)
#'   # }
#'
#' }


#' Scrape UniProt webpage
#'
#' @param id an UniProt ID
#'
#' @return Visualization of the subcellular location of the protein.
scrapeUniProtSnippets <- function(id) {
  ## empty id is not accepted
  # assertthat::assert_that(
  #   !(is.null(id) || is.na(id) || stringr::str_length(id) == 0)
  # )
  print(glue::glue("scraping: UniProt {id}"))
  if (is.null(id) || is.na(id) || stringr::str_length(id) == 0) {
    warning(
      glue::glue("UniProt id of is missing: '{id}'"),
      immediate. = TRUE
    )
    return("")
  }

  url <- glue::glue(UNIPROT.HTML.TEMPL)
  page <- getPageCached(url, sleepTime = SLEEP_TIME)

  subcellular_location <- page$document %>%
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


#' Supply details from UniProtKB
#'
#' @param clueTable Input dataframe with UNIPROT_KB_ID column.
#'
#' @return data.frame patched by UniProt details.
xmlUniProt <- function(clueTable) {
  #' Internal helper function
  #'
  #' @param xmlResult
  #'
  #' @return
  unwrapXMLData <- function(xmlResult) {
    root <- xml2::xml_root(result$document)

    ## STRING and GO ids
    dbReferences <- xml2::xml_find_all(
      x = root, xpath="//dbreference[@type = 'GO' or @type = 'STRING']"
    )

    ## iterate on DB references
    resultList <- list(GO.TERMS = list())
    for (dbref in dbReferences) {
      type <- xml_attr(dbref, "type")
      id <- xml_attr(dbref, "id")
      if (type == "STRING") {
        ## TODO: if there are multiple ids, the last one "wins"
        resultList[["STRING"]] <- id
      } else {
        resultList$GO.TERMS[[id]] <- "TODO"
      }
    }
    return(resultList)
  }

  ## xmlUniProt "body"-----------------------------------------------------
  uniProtIdList <- clueTable %>%
    select(UNIPROT_KB_ID) %>%
    distinct() %>%
    filter(!is.na(UNIPROT_KB_ID)) %>%
    pull(UNIPROT_KB_ID)

  ## iterate on UniProtKB Id list and collect/download relevant details
  filteredXMLData <- list()
  for (id in uniProtIdList) {
    ## Note: "id" referenced by the glue template below
    result <- getPageCached(glue::glue(UNIPROT.XML.TEMPL), sleepTime = 0)
    filteredXMLData[[id]] <- unwrapXMLData(result)
    subCellularSnippet <- scrapeUniProtSnippets(id)
    filteredXMLData[[id]]$subCellularHTML <- subCellularSnippet
  }

  clueTable <- clueTable %>%
    rowwise() %>%
    mutate(UniProtData = filteredXMLData[UNIPROT_KB_ID])
  return(clueTable)
}


##
## Utils/Helpers ----------------------------------------------------------
##

#' Load and cache files
#'
#' @param url URL pointing to XML/HTML file.
#' @param sleepTime sleep interval in seconds before download,
#' if content is not cached. Default value is 3.
#'
#' @return XML representation of the file content.
getPageCached <- function(url, sleepTime = 3, downloadFunc = rvest::read_html) {
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
        "{getRandomNumber()}-{as.integer(now)}"
      )
    }

    path <- glue::glue("{CACHE}/{fileName}")
    if (!notFound && file.exists(path)) {
      print(glue::glue("{Sys.time()} :: from cache: {url}"))
      # returning from cache
      return(list(
        document = downloadFunc(path),
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
      resultPage <- downloadFunc(url)
      print(glue::glue("{Sys.time()} :: downloaded: {url}"))
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
getRandomNumber <- function() {
  numbers <- runif(10, min = 1, max = 10000)
  return(
    floor(sample(numbers, 1))
  )
}

## just call the main
main()

warnings()
