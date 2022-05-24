##
## test_bug_71.R:
##
## Integration tests based on issue:
## https://github.com/cycle20/scancer/issues/71
##

library(curl)
library(glue)
library(readxl)
library(tinytest)

setwd('../..')
source("R/dataPatch.R")


###############################
## test keggPathWayCounter ----

# arrange
clueTable <- tibble::as_tibble(list(
  HUGO = c('SERPINA2', 'ITGB6'),
  UNIPROT_KB_ID = c('P20848', 'P18564')
))
clueTable <- xmlUniProt(clueTable)
# act
clueTable <- keggPathWayCounter(clueTable)
count <- clueTable %>% pull(NumberOfKEGGPathways) %>% head(1)
# assert
expect_equal(target = 0, count)


#####################################
## test stringInteractorsCounter ----

# arrange
clueTable <- tibble::as_tibble(list(
  HUGO = c('SERPINA2', 'ITGB6', 'ITGB6'),
  UNIPROT_KB_ID = c('P20848', 'P18564', 'P18564')
))
clueTable <- xmlUniProt(clueTable)
# act
clueTable <- stringInteractorsCounter(clueTable)
counts <- clueTable %>% pull(NumberOfSTRINGInteractors)
# assert
expect_equal(target = 0, counts[1])
expect_equal(target = 31, counts[3])
