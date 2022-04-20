##
## dataPatch.R: supply missing data items for clue.io compounds -----------
##

## Usage: call the main() from command line:
## R -e 'source("R/dataPatch.R"); main()'

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
SLEEP_TIME <- 30 # waiting time between two HTTP requests in seconds
INGREDIENT_FILTER <- FALSE # Is FDA Label API request strict or not?
OUTPUT <- "OUTPUT"
CACHE <- glue::glue("{OUTPUT}/DATAPATH_CACHE")
CLUE.INPUT <- glue::glue("{OUTPUT}/clue.rds")
# CLUE.PATCHED.OUTPUT <- glue::glue("{OUTPUT}/clue_patched.tsv")
CLUE.PATCHED.OUTPUT <- glue::glue("{OUTPUT}/clue_patched.rds")
TARGET_LIST.RDS <- glue::glue("{OUTPUT}/targetList.rds")

CHEMBL.URL.TEMPLATE <- "https://www.ebi.ac.uk/chembl/target_report_card"

TOOL.NAME <- "https://github.com/cycle20/scancer/"

PUBMED.BASE <- "https://pubmed.ncbi.nlm.nih.gov/"
PUBMED.SEARCH <- paste0(
  PUBMED.BASE,
  "?term={compound}&size=200", # "compound" as glue::glue variable
  "&filter=pubt.clinicaltrial","&filter=pubt.meta-analysis",
  "&filter=pubt.randomizedcontrolledtrial",
  "&filter=pubt.review",
  "&filter=pubt.systematicreview"
)
PUBMED.RESULT.XPATH <- paste0(
  '/html/body/main//section[@class="search-results-list"]',
  '//article[position() < 4]//a'
)
# maximum number of displayed PubMed links per compound
PUBMED.DISPLAY.MAX_LINKS <- 3

UNIPROT.HTML.TEMPL = "https://www.uniprot.org/uniprot/{id}"
UNIPROT.XML.TEMPL = "https://www.uniprot.org/uniprot/{id}.xml"

EMA.URL.TEMPLATE <- paste0(
  "https://www.ema.europa.eu/en/medicines/",
  ## more specific: EPAR items only
  "field_ema_web_categories%253Aname_field/Human/ema_group_types/ema_medicine/",
  "field_ema_med_status/authorised-36",
  "?search_api_views_fulltext={compound}", ## compound is the variable part
  "&page={pageNumber}",
  "&sort=search_api_relevance",
  "&order=desc"
)
EMA.OVERVIEW.PDF.URL <- paste0(
  "https://www.ema.europa.eu/en/documents/overview/",
  "{compound}-epar-summary-public_en.pdf"
)

PUBCHEM.URL.TEMPLATE <- "https://pubchem.ncbi.nlm.nih.gov/compound/{id.or.name}"

##
## Functions --------------------------------------------------------------
##

#' Main function
#'
#' Load data supply missing values.
#' In some complex cases it do some HTML pre-formatting to
#' support a simple HTML page rendering solution.
#'
#' @return Patched data.frame
main <- function() {
  ## read curated input used by clue.R
  targetList <- readRDS(TARGET_LIST.RDS)

  clueTable <- readRDS(CLUE.INPUT) %>%
    ## NOTE: this filter drops some not well-curated compounds
    filter(!is.na(source))

  checkDataCoverage(clueTable)

  clueTable <- targetList %>%
    left_join(clueTable) %>%
    rowwise() %>%
    mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID))) %>%
    filter(has_data == TRUE)

  result <- patch(clueTable)

  ## save tibble as RDS since write_tsv is not an obvious way
  print(result)
  saveRDS(result, file = CLUE.PATCHED.OUTPUT)

  # TODO: should be another logic: checkDataCoverage(result)

  warnings()
  return(result)
}


#' "Patch" data gaps in CLUE table
#'
#' @param clueTable
#'
#' @return Invisible NULL
patch <- function(clueTable) {

  if (nrow(clueTable) == 0) {
    stop("There are no rows in the input table")
  }

  ## FDA searches
  clueTable <- fdaLabel(clueTable)
  ## PubMed searches
  clueTable <- pubMed(clueTable)
  ## EMA searches
  clueTable <- ema(clueTable)
  ## Append UniProt details
  clueTable <- xmlUniProt(clueTable)

  ## Adjustment of data of columns and HTML fragments
  clueTable <- consolidateColumns(clueTable)

  ## return updated tables
  return(clueTable)
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
  checkTable <- function(table, msg, stop = FALSE) {
   n <- nrow(table)
   prefix <- glue::glue("\n\n>>>>>>>> {msg}: {n} ...")
   if (nrow(table) > 0) {
     print(glue::glue("{prefix} IS NOT OK!"))
     print(table)
     if (stop) stop("Unexpected data state")
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

  distinctTable <- clueTable %>%
    select(final_status, status_source) %>%
    distinct() %>%
    filter(final_status == "Preclinical" && !is.na(status_source))
  checkTable(distinctTable, "Preclinical status_source", stop = TRUE)

##  print("Foreced quit")
##  quit(save = "no")


  print(glue::glue("{separator}"))
  print(glue::glue("{separator}", "  !!! END OF DATA INTEGRITY TEST !!!"))
  print(glue::glue("{separator}"))

  return(invisible(NULL))
}


#' Cross-checking columns
#'
#' @param clueTable Input dataframe.
#'
#' @return data.frame updated based on column-wide decisions.
consolidateColumns <- function(clueTable) {
  ##
  ## TODO: Where should be constructed the HTML code?
  ##       Template file would be the best place.
  ##


  ## FUNC: to compose PubMed link
  pubMedLink <- function(PMID) {
    link <- paste0(PUBMED.BASE, PMID)
    return(aHref(link, glue::glue("PubMed {PMID}")))
  }
  ## FUNC: returns an HTML string of PubMed links
  pubMedLinks <- function(PMIDs, compound) {

    title <- "<strong>From PubMed:</strong>"
    if(all(is.na(PMIDs))) {
      searchLinkHTML <- aHref(link = glue::glue(PUBMED.SEARCH),
        titleText = "No search result"
      )
      return(paste(c(title, searchLinkHTML), collapse = "<br />"))
    } else {
      assertthat::assert_that(is.vector(PMIDs))

      PMIDs <- head(PMIDs, n = PUBMED.DISPLAY.MAX_LINKS)
      htmlLinks <- paste(sapply(PMIDs, pubMedLink), collapse = "<br />")
      return(paste(c(title, htmlLinks), collapse = "<br />"))
    }
  }

  ## FUNC: to compose EMA and append links to "status_source"
  appendEMALinks <- function(status_source = "", emaLinks) {
    if(all(is.na(emaLinks))) {
      return(status_source)
    } else {
      status_source <- paste(
        c(status_source, "<strong>From EMA:</strong>"),
        collapse = "<br />"
      )

      status_source <- paste(
        c(
          status_source,
          sapply(emaLinks, function(link) aHref(link, "Found PDF"))
        ),
        collapse = "<br />"
      )

      return(status_source)
    }
  }

  ## FUNC: to compose FDA and append links to "status_source"
  appendFDALinks <- function(status_source = "", fdaLabelDetails) {
    if (is.na(fdaLabelDetails$pert_iname)) {
      return(status_source)
    } else {
      ## old value + title of FDA "section":
      status_source <- paste(
        c(status_source, "<strong>FDA Labels:</strong>"),
        collapse = "<br />"
      )

      ## glue variable accessed from dplyr environment: "setId"
      ## TODO: https://nctr-crs.fda.gov/fdalabel...spl-doc?hl=PATTERN_TO_HIGHLIGHT
      labelURLTemplate <-
        "https://nctr-crs.fda.gov/fdalabel/services/spl/set-ids/{setId}/spl-doc"
      ## glue variable accessed from dplyr environment: "productNames"
      anchorTemplate <- '<a href="{labelURL}" target="_blank">{productNames}</a>'

      ## concatenate labels as HTML URL list
      htmlOfURLs <- fdaLabelDetails$productsTable %>%
        mutate(
          labelURL = glue::glue(labelURLTemplate),
          htmlURL = glue::glue(anchorTemplate)
        ) %>%
        select(labelURL, htmlURL)

      resultHTML <- htmlOfURLs %>% pull(htmlURL)
      resultHTML <- paste(resultHTML, collapse = "<br />")

      status_source <- paste(c(status_source, resultHTML), collapse = "<br />")
      return(status_source)
    }
  }

  ## update "status_source" by HTML representation of various sources
  clueTable <- clueTable %>%
    rowwise() %>%
    mutate(
      pubMedPreClinicalLinks = pubMedLinks(pubMedPreClinicalLinks, pert_iname),
      fdaSearchResults = appendFDALinks(pubMedPreClinicalLinks,
                                        fdaLabelDetails = fdaSearchResults),
      emaLinks = appendEMALinks(fdaSearchResults, emaLinks = emaLinks)
    ) %>%
    rowwise() %>%
    mutate(clueSource = glue::glue(
      "<div class='clue'><strong>CLUE.IO</strong><br/>",
      "{statusSourceHTML(status_source, pert_iname)}</div>"
    )) %>%
    mutate(
      status_source = paste(c(emaLinks, clueSource), collapse = "<br />")
    )

  return(clueTable)
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
    return("No status source")
  } else if (stringr::str_starts(statusSource, "<a href=")) {
    ## already converted HTML
    return(statusSource)
  }

  htmlText <- ""
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
    ## plain text as is
    html <- statusSource
    return(html)
  }
  htmlText <- paste0(htmlText, aHref(link = statusSource, titleText = label))

  return(htmlText)
}


#' Extract and supply PMIDs/links
#'
#' @param clueTable
#'
#' @return
pubMed <- function(clueTable) {

  ## pubMed search request and extract results
  pubMedSearch <- function(compound) {

    ## download page or read it from cache
    searchURL <- glue::glue(PUBMED.SEARCH)

    result <- getPageCached(searchURL, sleepTime = SLEEP_TIME)

    ## XPath expression to access ID list embedded into HTML code
    xpath <- paste0(
      'string(/html/head/meta[@name = "log_displayeduids"]/@content)'
    )
    ## get article IDs: single string separated by "," and
    ## split the ID list
    articleIds <- result$document %>%
      rvest::html_element(xpath = xpath) %>%
      stringr::str_split(pattern = ",") %>%
      unlist()

    articleIds <- if_else(articleIds[1] == "",
      list(NULL), list(articleIds)) %>%
      unlist()

    return(articleIds)
  }

  addPubMedData <- function(.data) {
    .data <- .data %>%
      mutate(pubMedPreClinicalLinks = list(pubMedSearch(pert_iname))) %>%
      mutate(PubMedCounter = length(unlist(pubMedPreClinicalLinks)))
    return(.data)
  }

  clueTable <- clueTable %>% addPubMedData()

  # TODO: PMC? And embargoed articles? https://www.ncbi.nlm.nih.gov/pmc
  # TODO: https://drugs.ncats.io/substances?facet=Pharmacology%2FInhibitor
  # TODO: https://drugs.ncats.io/drug/MRK240IY2L

  return(clueTable)
}


##
## Labels for Launched Drugs/Compounds ------------------------------------
##

#' Supply details from EMA website
#'
#' @param clueTable Input dataframe with compounds (pert_iname column).
#'
#' @return data.frame patched by EMA links.
ema <- function(clueTable) {

  ## Decreased sleep time for EMA requests
  ## (based on https://www.ema.europa.eu/robots.txt at 2021-05-30 21:05 GMT)
  SLEEP_TIME <- 11

  emaSearchLocalCache <- list()

  ## Get results of query on EMA search page
  ## Does not harvest each drug link so pageNumber is not in use currently.
  emaSearch <- function(compound, pageNumber = 0) {
    assertthat::assert_that(!is.na(compound))

    if(hasName(emaSearchLocalCache, compound)) {
      pdfURL <- emaSearchLocalCache[[compound]]
      print(glue::glue("EMA LCACHE: compound: {compound}: {pdfURL}"))
      return(pdfURL)
    }
    ## parent environment
    penv <- parent.env(environment())


    print(glue::glue("EMA SEARCH: compound: {compound}"))
    ## get search result --------------------------------------------------
    emaResult <- getPageCached(glue::glue(EMA.URL.TEMPLATE))
    xpath = paste0(
     "string(//*/a[",
       "contains(@href, '/en/medicines/human/EPAR')",
       " and not(descendant::img/@alt = 'Additional monitoring')",
     "]/@href)"
    )
    firstDrugPath <- rvest::html_element(emaResult$document, xpath = xpath)
    ## If not hit at all
    if (firstDrugPath == "") {
      warning(
        glue::glue("NO DRUG FOUND :: COMPOUND: {compound} ", EMA.URL.TEMPLATE),
        immediate. = TRUE
      )
      penv$emaSearchLocalCache[[compound]] <- NA
      return(NA)
    }

    ## "most" relevant drug -----------------------------------------------
    firstDrugPage <- getPageCached(
      glue::glue("https://www.ema.europa.eu{firstDrugPath}"),
      sleepTime = ifelse(emaResult$fromCache, 1, SLEEP_TIME)
    )

    ## get public summary PDF link ----------------------------------------
    xpath <- paste0(
      "string(//*/a[",
      "contains(@href, '.pdf') and (",
        "contains(@href, 'summary-public_en')",
        " or contains(@href, 'documents/product-information/')",
        " or contains(@href, 'refusal-public-assessment-report')",
        " or contains(@href, 'public-assessment-report')",
        " or (",
          "contains(@href, 'documents/public-statement')",
          " and contains(@href, 'non-renewal')",
          " and contains(@href, 'authorisation')",
        ") ",
        # probably this is the least restrictive URL filter
        " or contains(@href, 'documents'))",
      "]/@href)"
    )
    pdfURL <- rvest::html_element(firstDrugPage$document, xpath = xpath)
    assertthat::assert_that(pdfURL != "")
    assertthat::assert_that(!is.na(pdfURL) && !is.null(pdfURL))

    ## PDF URL verification -----------------------------------------------
    if (!firstDrugPage$fromCache) {
      print(glue::glue("Sleep before HEAD request: {SLEEP_TIME} secs"))
      Sys.sleep(SLEEP_TIME)
    } else {
      Sys.sleep(2)
    }
    ## HEAD request and assert
    print(glue::glue("Check URL (HEAD request): {pdfURL}"))
    statusCode <- httr::HEAD(pdfURL)$status_code
    print(c("Check HEAD HTTP status code: ", statusCode))
    if (statusCode == 404) { ## NOTE: this case needs a better handler
      print("ERROR 404: PAGE NOT FOUND")
    } else {
      assertthat::assert_that(statusCode %in% c(200, 301, 302))
    }

    ## return the public summary PDF link of the first hit from the search list
    penv$emaSearchLocalCache[[compound]] <- pdfURL
    return(pdfURL)
  }
  clueTable <- clueTable %>%
    dplyr::rowwise() %>%
    dplyr::mutate(emaLinks = list(emaSearch( pert_iname )))

  return(clueTable)
}


readReport <- function(fileName) {
  getEMAFile(fileName)
  report <- readxl::read_excel(fileName, skip = 7)
  return(report)
}

getEMAFile <- function(file, quiet = FALSE) {
  EMA_FILES_BASE_URL <- "https://www.ema.europa.eu/sites/default/files"
  url <- glue::glue("{EMA_FILES_BASE_URL}/{file}")
  if (!quiet) {
    print(glue::glue("Downloading {url}"))
  }
  curl::curl_download(url = url, destfile = file, mode ="wb", quiet = quiet)
}


#############################################################



fdaLabel <- function(clueTable) {
  ## url with "pert_iname" placeholder
  url = paste0("https://nctr-crs.fda.gov/fdalabel/services/spl/summaries",
               "?pert={pert_iname}&ingr=", INGREDIENT_FILTER)

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

  ## FUNC: Custom download function instead of rvest::read_html.
  ##       Passed as parameter of getPageCached function.
  ##       based on https://nctr-crs.fda.gov/fdalabel/ui/search results
  fdaDownload <- function(url) {
    if(startsWith(url, CACHE)) {
      ## if reading from cache...
      return(readr::read_file(url))
    }

    ## TODO: Ugly hack to resolve variable from the call-chain
    pert_iname <- get("pert_iname", envir = sys.frame(-2))
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

  ## FUNC: internal helper function
  getFDALabelResults <- function(pert_iname) {
    #labelTable <- jsonlite::read_json(glue::glue("{CACHE}/{pret_iname.json}"))

    ## "empty" result
    emptyList <- list(pert_iname = NA, productsTable = NA)

    ## call cached download, uses custom download function (fdaDownload) above
    downloadedResult <- getPageCached(
      glue::glue(url), ## replace pert_iname placeholder before pass it
      sleepTime = SLEEP_TIME,
      ## send and get HTTP request and result in a specialized manner
      downloadFunc = fdaDownload
    )

    ## parsing and "compressing" result set
    parsedResult <- jsonlite::fromJSON(downloadedResult$document)
    if (parsedResult$totalResultsCount == 0) {
      print(glue::glue("fdaLabel :: {pert_iname} :: results not found"))
      return(emptyList) ## return "empty" list
    }

    ## filtering
    pertNamePattern <- gsub("-", ".{,4}", pert_iname)
    products <- parsedResult$resultsArray %>%
      filter(
        !any(grepl("first aid", productNames, ignore.case = TRUE))
          && (!any(grepl(" kit", productNames, ignore.case = TRUE))
              && !any(grepl("KIT", dosageForms)))
      )

    if ((products %>% nrow()) == 0) {
      print(glue::glue("{pert_iname} :: results not found after filtering"))
      return(emptyList) ## return "empty" list
    }

    ## FUNC: Shrink found labels selecting by
    ##       max. market date of each group
    ingredientsMatchLevel <- Vectorize(function(pert_iname, ingrList) {
      ## to uppercase and split the list of ingredients name
      ingrList <- ingrList %>%
        stringr::str_to_upper() %>%
        stringr::str_split(string = ., pattern = "; *")
      ingrList <- ingrList[[1]]
      ## to uppercase the pert. name
      pert_iname <- stringr::str_to_upper(pert_iname)

      matchLevel <- if (pert_iname %in% ingrList) {
        1 # exact match
      } else if (any(stringr::str_starts(ingrList, pert_iname))) {
        2 # partial match A: starts with
      } else if (any(stringr::str_ends(ingrList, pert_iname))) {
        3 # partial match B: ends with
      } else if (any(grepl(pert_iname, ingrList))) {
        4 # partial match C: contains
      } else {
        5 # no match at all
      }
    })

    ## FUNC: split and returns actIngrUniis string
    ingrLength <- Vectorize(function(actIngrUniis) {
      actIngrUniis <- actIngrUniis %>%
        stringr::str_to_upper() %>%
        stringr::str_split(string = ., pattern = "; *")
      actIngrUniis <- actIngrUniis[[1]]

      return(length(actIngrUniis))
    })

    products <- products %>%
      mutate(matchLevel = ingredientsMatchLevel(pert_iname, actIngrNames)) %>%
      mutate(ingrLength = ingrLength(actIngrUniis)) %>%
      filter(matchLevel < 5) %>%
      group_by(matchLevel, ingrLength)

    if ((products %>% nrow()) == 0) {
      print(glue::glue("{pert_iname} :: matching ingredients not found"))
      print(glue::glue("{pert_iname} :: NOTE: there might be special matching"))
      return(emptyList) ## return "empty" list
    }

    ## probably "best" matches"
    ## TODO: needs more work: since it picks from each matchLevel,
    ##       but incremental selection would be better:
    ##       - first try to get results from level 1,
    ##       - then try level 2,...
    ##       - etc...
    products <- products %>%
      filter(marketDates == max(marketDates)) %>%
      ungroup() %>%
      arrange(matchLevel, ingrLength)

    nr <- nrow(products)
    percentage <- round((1 - nr / parsedResult$totalResultsCount) * 100, 2)
    print(glue::glue(
      "fdaLabel({pert_iname}) products counts ({nr}) shrinked by {percentage} %"
    ))

    productsTable <- (products %>% select(productNames, setId))
    return(list(
      pert_iname = pert_iname,
      productsTable = productsTable
    ))
  }

  ## transform status_source based on FDA results
  clueTable <- clueTable %>%
    # filter(final_status == "Launched" && !is.na(orange_book)) %>%
    mutate(fdaSearchResults = list(getFDALabelResults(pert_iname)))

  return(clueTable)
}


#' Supply details from UniProtKB
#'
#' @param clueTable Input dataframe with UNIPROT_KB_ID column.
#'
#' @return data.frame patched by UniProt details.
xmlUniProt <- function(clueTable) {

  ## change SLEEP_TIME locally since no restrictive robots.txt found
  ## (5 secs is still very friendly)
  SLEEP_TIME <- 5

  ## if previous request found a cached item,
  ## we can increase the request rate a bit.
  SLEEP_TIME_ON_CACHE_HIT <- 2

  #' Determine "type" GO term
  #'
  #' @param termValue GO value of a term
  #'
  #' @return "type" of the term: "molecularFunction",
  #'         "biologicalProcess" or "subCellularLocation"
  GOTermType <- function(termValue) {
    type <- if (startsWith(termValue, "F:")) {
      "molecularFunction"
    } else if (startsWith(termValue, "C:")) {
      "subCellularLocation"
    } else if (startsWith(termValue, "P:")) {
      "biologicalProcess"
    } else {
      stop(paste0("Unexpected term prefix: ", termValue))
    }
    return(type)
  }

  #' Internal helper function
  #'
  #' @param xmlResult UniProt data as XML
  #'
  #' @return Extracted and selected data items.
  unwrapXMLData <- function(xmlResult) {
    root <- xml2::xml_root(result$document)

    ## STRING and GO ids
    ## NOTE: dbReference vs dbreference ???
    xpath <- paste0(

      ## GO functional ("F:") references
      "//dbreference[@type='GO']",
        "//property[@type='term'][starts-with(@value, 'F:')]",
        "/parent::node()", ## select parent node of this GO property

      ## GO cellular components ("C:") references
      " | //dbreference[@type='GO']",
        "//property[@type='term'][starts-with(@value, 'C:')]",
        "/parent::node()", ## select parent node of this GO property

      ## GO biological process ("P:") references
      " | //dbreference[@type='GO']",
        "//property[@type='term'][starts-with(@value, 'P:')]",
        "/parent::node()", ## select parent node of this GO property

      ## STRING, Reactome or KEGG references
      " | //dbreference[@type='STRING' or @type='Reactome' or @type='KEGG']"
    )
    dbReferences <- xml2::xml_find_all(x = root, xpath = xpath)

    ## iterate on DB references
    resultList <- list(
      molecularFunction = NULL,
      subCellularLocation = NULL,
      Reactome = list()
    )
    for (dbref in dbReferences) {
      type <- xml2::xml_attr(dbref, "type")
      referenceId <- xml2::xml_attr(dbref, "id")
      if (type == "STRING") {
        ## TODO: if there are multiple ids, the last one "wins"
        resultList[["STRING"]] <- referenceId
      } else if (type == "KEGG") {
        resultList[["KEGG"]] <- referenceId
      } else if (type == "Reactome") {
        pathway <-
          xml2::xml_find_first(dbref, ".//property[@type='pathway name']") %>%
          xml2::xml_attr(attr = "value")
        resultList$Reactome[[referenceId]] <- pathway
      } else if (type == "GO") {
        ## get value of the term
        termValue <-
          xml2::xml_find_first(dbref, ".//property[@type='term']") %>%
          xml2::xml_attr(attr = "value")

        ## select item name by value prefix
        termType <- GOTermType(termValue)
        ## create a new named element (as a vector)
        newItem <- c(substring(termValue, 3))
        names(newItem) <- referenceId
        ## append to the vector (to collect values for the same GO "type")
        resultList[[termType]] <- c(resultList[[termType]], newItem)
      }
    }
    return(resultList)
  }

  ## xmlUniProt "body"-----------------------------------------------------
  uniProtIdList <- clueTable %>%
    dplyr::select(UNIPROT_KB_ID) %>%
    dplyr::distinct() %>%
    dplyr::filter(!is.na(UNIPROT_KB_ID)) %>%
    dplyr::pull(UNIPROT_KB_ID)

  ##
  ## iterate on UniProtKB Id list and -------------------------------------
  ## collect/download relevant details
  ##
  filteredXMLData <- list()
  scrapeFromCache <- TRUE
  for (id in uniProtIdList) {
    ## Note: "id" referenced by the glue template below
    sleepTime <- ifelse(scrapeFromCache, SLEEP_TIME_ON_CACHE_HIT, SLEEP_TIME)
    ## load XML "page"
    result <- getPageCached(
      glue::glue(UNIPROT.XML.TEMPL), sleepTime
    )
    filteredXMLData[[id]] <- unwrapXMLData(result)
  }

  ## update the input table and return the result -------------------------
  clueTable <- clueTable %>%
    dplyr::rowwise() %>%
    dplyr::mutate(UniProtData = filteredXMLData[UNIPROT_KB_ID])
  return(clueTable)
}


##
## Web/Networking ---------------------------------------------------------
##

#' Load and cache files
#'
#' @param url URL pointing to XML/HTML file.
#' @param sleepTime sleep interval in seconds before download,
#' if content is not cached. Default value is 3.
#'
#' @return XML representation of the file content.
#' @import dplyr
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
      stop(glue::glue("file not found: {path} !!!!!! url: {url}"))
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

#' Create an "anchor" element
#'
#' @param link Parameter of "href" attribute.
#' @param titleText character content of "a" element.
#'
#' @return HTML "a" snippet that can be used in HTML document directly.
aHref <- function(link, titleText) {
  return(glue::glue('<a href="{link}" target="_blank">{titleText}</a>'))
}

