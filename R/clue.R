library(httr)
library(jsonlite)
library(glue)

USER_KEY <- Sys.getenv("CLUE_USER_KEY")
API_BASE <- "https://api.clue.io/api/"

perts <- function(targets) {
  apiFunction <- "perts"
  filterParams <- list(
    fields = c(
      "pert_id",
      "pert_iname",
      "alt_name",
      "pert_type",
      "pert_summary",
      "description",
      #"clinical_phase",
      "moa",
      "status",
      "target",
      "pert_url",
      "provisional",
      "pubchem_cid"
    ),
    where = list(
      target = list(inq = targets)
    )
  )
  filterParams["fields"] <- NULL
  filterParams <- jsonlite::toJSON(filterParams)


  requestUrl <- glue(
    "{API_BASE}{apiFunction}?",
    "filter={filterParams}&user_key={USER_KEY}"
  )
  result <- httr::GET(requestUrl, verbose())

  return(httr::content(result))
}

resultAsJSON <- function() {
  targets <- c(
    "CXCR2"
  #  "TP63",
  #  "MMP7"
  )

  result <- perts(targets)

  return(jsonlite::toJSON(result))
}

# print(
#   jsonlite::flatten(
#     jsonlite::fromJSON( resultAsJSON()),
#     recursive = TRUE
#   )
# )

r <- resultAsJSON()
browser()


