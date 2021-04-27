##
## STRING.R: collect data from STRING
##
## NOTE: It collects data from already initialized subset of STRING
##       (stored as an SQLite3 database locally)
##

library(assertthat)
library(data.table)
library(DBI)
library(dplyr)
library(glue)
library(readr)
library(RSQLite)

## environment settings of the script
SQL_LITE_PATH <- "INPUT/STRING/STRING_DB_SQLITE3.db"
OUTPUT.DIR <- "OUTPUT"
CLUE.RESULT <- glue:: glue("{OUTPUT.DIR}/clue.tsv")

##### Data Section
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

preCheck <- function() {
  assertthat::assert_that(file.exists(SQL_LITE_PATH))
  #browser()
  assertthat::are_equal(dir.exists(paths = OUTPUT.DIR), TRUE)
  assertthat::assert_that(file.exists(CLUE.RESULT))
}

readData <- function() {
  clueResult <- readr::read_tsv(CLUE.RESULT)

  connection <- DBI::dbConnect(RSQLite::SQLite(), SQL_LITE_PATH)

  tab <- DBI::dbReadTable(connection, "ITEMS_PROTEINS")

  DBI::dbDisconnect(connection)

  preferred_names <- tab$perferred_name

  # assertthat::assert_that(
  #   length(intersect(NE.LOW, preferred_names)) == length(NE.LOW)
  # )
  # assertthat::assert_that(
  #   length(intersect(NE.HIGH, preferred_names)) == length(NE.HIGH)
  # )

  browser()
  result <- tab %>%
    filter(preferred_name %in% c(NE.LOW, NE.HIGH)) %>%
    arrange(preferred_name) %>%
    select(preferred_name, protein_external_id, UNIPROT_KB_ID)

  readr::write_tsv(result, file = "string_tab.tsv")
}

preCheck()
readData()
