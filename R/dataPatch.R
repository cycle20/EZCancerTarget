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

PUBMED.BASE <- "https://pubmed.ncbi.nlm.nih.gov/"
PUBMED <- paste0(
  PUBMED.BASE,
  "?term={compound}&size=200",
  "&filter=pubt.clinicaltrial","&filter=pubt.meta-analysis",
  "&filter=pubt.randomizedcontrolledtrial",
  "&filter=pubt.review",
  "&filter=pubt.systematicreview"
)
PUBMED.RESULT.XPATH <- paste0(
  '/html/body/main//section[@class="search-results-list"]',
  '//article[position() < 4]//a'
)

UNIPROT.HTML.TEMPL = "https://www.uniprot.org/uniprot/{id}"
UNIPROT.XML.TEMPL = "https://www.uniprot.org/uniprot/{id}.xml"

EMA.URL.TEMPLATE <- paste0(
  "https://www.ema.europa.eu/en/medicines/",
  ## more specific: EPAR items only
  "field_ema_web_categories%253Aname_field/Human/ema_group_types/ema_medicine",
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
  ## read curated input names
  targetList <- readr::read_tsv(TARGET.INPUT) %>%
    mutate(HUGO = target)

  result <- readr::read_tsv(CLUE.INPUT)

  checkDataCoverage(result)

  result <- targetList %>%
    left_join(result) %>%
    rowwise() %>%
    mutate(has_data = (!is.na(pert_iname) && !is.na(UNIPROT_KB_ID)))

  ## Append UniProt details
  result <- pubMed(result)
  result <- ema(result)
  result <- xmlUniProt(result)
  #result <- patch(result)
  result <- consolidateColumns(result)
  ## save tibble as RDS since write_tsv is not an obvious way
  print(result)
  saveRDS(result, file = CLUE.PATCHED.OUTPUT)
  # TODO: readr::write_tsv(result, file = CLUE.PATCHED.OUTPUT)
  # TODO: or JSON format might be a portable solution

  # TODO: should be another logic: checkDataCoverage(result)

  return(result)
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
  composeLink <- function(PMID) {
    link <- paste0(PUBMED.BASE, PMID)
    return(aHref(link, "PM from search"))
  }
  # returns an HTML string
  composeLinks <- function(PMIDs) {
    if(!is.list(PMIDs) || length(PMIDs) == 0) {
      return(NA)
    } else {
      return(paste(sapply(PMIDs, composeLink), collapse = "<br/>"))
    }
  }
  appendEMALinks <- function(status_source, emaLinks) {
    if(all(is.na(emaLinks))) {
      return(status_source)
    } else {
      status_source <- paste(
        c(status_source, "<strong>From EMA:</strong>"),
        collapse = "<br/>"
      )

      status_source <- paste(
        c(
          status_source,
          sapply(emaLinks, function(link) aHref(link, "Search Result"))
        ),
        collapse = "<br/>"
      )

      return(status_source)
    }
  }

  clueTable <- clueTable %>%
    rowwise() %>%
    mutate(pubMedPreClinicalLinks = composeLinks(pubMedPreClinicalLinks)) %>%
    mutate(
        status_source = statusSourceHTML(status_source, pert_iname)
    ) %>%
    mutate(
      status_source = if_else(
        final_status == "Preclinical",
        pubMedPreClinicalLinks,
        toString(status_source))
    ) %>%
    mutate(status_source = appendEMALinks(status_source, emaLinks))

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
    link <- paste0(
      "https://pubmed.ncbi.nlm.nih.gov",
      "/?term={pert_iname}&size=200",
      "&filter=pubt.clinicaltrial","&filter=pubt.meta-analysis",
      "&filter=pubt.randomizedcontrolledtrial",
      "&filter=pubt.review",
      "&filter=pubt.systematicreview"
    )

    link <- glue::glue(link)
    htmlText <- aHref(link = link, titleText = "PubMed Result: 0")

    return(htmlText)
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
    ## plain text transformed to a tool-tipped entity
    html <- glue::glue("<span data-bs-toggle=\"tooltip\" ",
      "title=\"{statusSource}\" data-bs-placement=\"right\">",
      "{statusSource}</span>")
    return(html)
  }
  # TODO:
  htmlText <- paste0(htmlText, aHref(link = statusSource, titleText = label))

  return(htmlText)
}


#' "Patch" data gaps in CLUE table
#'
#' @param clueTable
#'
#' @return Invisible NULL
patch <- function(clueTable) {

  # TODO: phase I... : clinicalTrials -------------------------------------

  ## FDA searches
  ## TODO: UPDATE the clueTable
  fdaPerts <- clueTable %>%
    select(pert_iname, final_status, orange_book) %>%
    filter(final_status == "Launched" && !is.na(orange_book)) %>%
    distinct()

  fdaSearchResults <- sapply(
    fdaPerts %>% pull(pert_iname),
    fdaLabel,
    simplify = FALSE
  )

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

  chEmblPubChemCount <- clueTable %>%
    filter(is.na(chembl_id) && is.na(pubchem_cid)) %>%
    distinct() %>% nrow()
  chEmblPubChemSecs <- chEmblPubChemCount * 35

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


#' Extract and supply PMIDs/links
#'
#' @param clueTable
#'
#' @return
pubMed <- function(clueTable) {
  assertthat::assert_that(tibble::is_tibble(clueTable))

  ## TODO: CLUE.IO bug: Desidustat (for EGLN2): Pre-clinical
  ##       But it has Clinical Trial hits on PubMed

  ## pubMed search request and extract results
  pubMedSearch <- function(compound, final_status) {
    if (final_status != "Preclinical"
        || is.null(final_status) || is.na(final_status)) {
      return(NA)
    }
    # download page or read it from cache
    searchURL <- glue::glue(PUBMED)
    result <- getPageCached(searchURL, sleepTime = SLEEP_TIME)
    # get article <a> elements (top3, if there are more)
    articleLinks <- result$document %>%
      rvest::html_elements(xpath = PUBMED.RESULT.XPATH)
    # get article identifiers
    articleIds <- rvest::html_attr(articleLinks, name = "data-article-id")

    return(as.list(articleIds))
  }

  ## TODO: UPDATE the clueTable
  # pubMedPerts <- clueTable %>%
  #   select(pert_iname, final_status, status_source) %>%
  #   filter(final_status == "Preclinical" && is.na(status_source)) %>%
  #   distinct()

  # clueTable$pubMedPreClinicalLinks <- NA
  # #  //pubMedSearch( pert_iname, final_status ))
  # clueTable$pubMedPreClinicalLinks[1] <- list(NA, NA)
  clueTable <- clueTable %>%
    mutate(pubMedPreClinicalLinks = list(pubMedSearch(pert_iname, final_status)))

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
  emaSearchLocalCache <- list()

  ## Get results of query on EMA search page
  ## Does not harvest each drug link so pageNumber is not in use currently.
  emaSearch <- function(compound, pageNumber = 0) {
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
    xpath = "string(//*/a[contains(@href, '/en/medicines/human/EPAR')]/@href)"
    firstDurgPath <- rvest::html_element(emaResult$document, xpath = xpath)
    ## If not hit at all
    if (firstDurgPath == "") {
      warning(
        glue::glue("NO DRUG FOUND :: COMPUND: {compound} ", EMA.URL.TEMPLATE),
        immediate. = TRUE
      )
      penv$emaSearchLocalCache[[compound]] <- NA
      return(NA)
    }

    ## "most" relevant drug -----------------------------------------------
    firstDrugPage <- getPageCached(
      glue::glue("https://www.ema.europa.eu{firstDurgPath}"),
      sleepTime = ifelse(emaResult$fromCache, 1, SLEEP_TIME)
    )

    ## get public summary PDF link ----------------------------------------
    xpath <- paste0(
      "string(//*/a[",
      "contains(@href, 'summary-public_en')",
      " or contains(@href, 'documents/product-information/')",
      " or contains(@href, 'refusal-public-assessment-report')",
      " or (",
        "contains(@href, 'documents/public-statement')",
        " and contains(@href, 'non-renewal')",
        " and contains(@href, 'authorisation')",
        " and contains(@href, '.pdf')",
      ")]/@href)"
    )
    pdfURL <- rvest::html_element(firstDrugPage$document, xpath = xpath)

    ## PDF URL verification -----------------------------------------------
    if (!firstDrugPage$fromCache) {
      print(glue::glue("Sleep before HEAD request: {SLEEP_TIME} secs"))
      Sys.sleep(SLEEP_TIME)
    } else {
      Sys.sleep(5)
    }
    ## HEAD request and assert
    print(glue::glue("Check URL (HEAD request): {pdfURL}"))
    sCode <- httr::HEAD(pdfURL)$status_code
    print(sCode)
    assertthat::assert_that(sCode %in% c(200, 301, 302))

    ## return the public summary PDF link of the first hit from the search list
    penv$emaSearchLocalCache[[compound]] <- pdfURL
    return(pdfURL)
  }
  clueTable <- clueTable %>%
    rowwise() %>%
    mutate(emaLinks = list(emaSearch( pert_iname )))

  return(clueTable)
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


#' PubChem Id
#'
#' @param id.or.name
#'
#' @return PubChem cid/name or NA
pubChem <- function(id.or.name) {
  ## TODO: PubChem check/download

  ##
  ## TODO:
  ##
  ## to find description by name:
  ## https://pubchem.ncbi.nlm.nih.gov/compound/nitroflurbiprofen
  ##
  ## Can be extracted:
  ##
  ## <meta name="pubchem_uid_type" content="CID">
  ## <meta name="pubchem_uid_type_prefix" content="PubChem">
  ## <meta name="pubchem_uid_name" content="compound">
  ## <meta name="pubchem_uid_value" content="119387">
  ##
  ## <link rel="alternate" type="application/rdf+xml"
  ##   title="CID:119387"
  ##   href="https://rdf.ncbi.nlm.nih.gov/pubchem/compound/CID119387">
  ##

  stop("Not implemented")

  ##
  url <- glue::glue(PUBCHEM.URL.TEMPLATE)
}


#' Scrape UniProt webpage
#'
#' @param id an UniProt ID
#'
#' @return Visualization of the subcellular location of the protein.
scrapeUniProtSnippets <- function(id, sleepTime) {
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
    return(lits(
      htmlSnippet = "",
      fromCache = TRUE
    ))
  }

  ## cached download of HTML page
  url <- glue::glue(UNIPROT.HTML.TEMPL)
  page <- getPageCached(url, sleepTime = sleepTime)

  ## pick the jensenlab-style image ---------------------------------------
  subcellular_location <- page$document %>%
    rvest::html_elements(
      xpath = "//div[@id = 'subcellular_location']"
    )

  htmlSnippet <- if (length(subcellular_location) == 1) {
    subCellNode <- subcellular_location[[1]]
    xml2::write_html(subCellNode, "debug_subcellular_location.html")
    toString(subCellNode)
  } else {
    warning(
      glue::glue("{id}: Subcellular figure not found"), immediate. = TRUE
    )
    glue::glue("<div>Subcellular figure not found</div>")
  }


  # hasSubCellFigure <- subcellular_location %>%
  #   xml2::xml_find_all(".//sib-swissbiopics-sl") %>%
  #   length()
  # htmlSnippet <- if (hasSubCellFigure > 0) {
  #   toString(subcellular_location)
  # } else {
  #   warning(
  #     glue::glue("{id}: Subcellular figure not found"), immediate. = TRUE
  #   )
  #   glue::glue("<div>Subcellular figure not found</div>")
  # }

  ## pick GO Molecular functions ------------------------------------------
  molecularFunction <- page$document %>% rvest::html_elements(
    xpath = '//div[@id="function"]//ul[contains(@class, "molecular_function")]'
  )
  molecularFunction <- if (length(molecularFunction) == 1) {
    node <- molecularFunction[[1]]
    xml2::write_html(node, "debug_molecular_function.html")
    toString(node)
  } else {
    warning(
      glue::glue("{id}: GO Molecular function not found"), immediate. = TRUE
    )
    glue::glue("<div>GO Molecular function not found</div>")
  }


  return(list(
    htmlSnippet = htmlSnippet,
    molecularFunction = molecularFunction,
    fromCache = page$fromCache
  ))
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

  ##
  ## iterate on UniProtKB Id list and -------------------------------------
  ## collect/download relevant details
  ##
  filteredXMLData <- list()
  scrapeFromCache <- TRUE
  for (id in uniProtIdList) {
    ## Note: "id" referenced by the glue template below
    sleepTime <- ifelse(scrapeFromCache, 2, SLEEP_TIME)
    result <- getPageCached(
      glue::glue(UNIPROT.XML.TEMPL), sleepTime
    )
    filteredXMLData[[id]] <- unwrapXMLData(result)

    ## scrape the subcell. image
    sleepTime <- ifelse(result$fromCache, 2, SLEEP_TIME)
    scrapeResult <- scrapeUniProtSnippets(id, sleepTime)
    scrapeFromCache <- scrapeResult$fromCache
    filteredXMLData[[id]]$subCellularHTML <- scrapeResult$htmlSnippet
    filteredXMLData[[id]]$molecularFunctionHTML <-
      scrapeResult$molecularFunction
  }

  ## update the input table and return the result -------------------------
  clueTable <- clueTable %>%
    rowwise() %>%
    mutate(UniProtData = filteredXMLData[UNIPROT_KB_ID])
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

#' Create an "anchor" element
#'
#' @param link Parameter of "href" attribute.
#' @param titleText character content of "a" element.
#'
#' @return HTML "a" snippet that can be used in HTML document directly.
aHref <- function(link, titleText) {
  return(glue::glue("<a href=\"{link}\" target=\"_blank\">{titleText}</a>"))
}


## just call the main
patchedTable <- main()
warnings()
