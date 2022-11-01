##
## test_fda_label.R
##

setwd('../..')
source("R/dataPatch.R")

## arrange
clueTable <- tibble::as_tibble(list(
  pert_iname = c(
    'padeliporfin',
    'empagliflozin',
    'apomorphine',
    'rolipram',
    'baclofen'
  )
))

## act
clueTable <- fdaLabel(clueTable)
#print(clueTable$fdaSearchResults)

## assert

# padeliporfin
expect_equal(
  target = NA,
  current = clueTable$fdaSearchResults[[1]][["pert_iname"]]
)

# empagliflozin
expect_equal(
  target = "Jardiance",
  current = clueTable$fdaSearchResults[[2]][["productsTable"]]$productNames[1]
)
expect_equal(
  target = "71873567-9594-452a-bb92-34a129adecac",
  current = clueTable$fdaSearchResults[[2]][["productsTable"]]$setId[3]
)

# baclofen
expect_equal(
  target = "Lioresal (baclofen)",
  current = clueTable$fdaSearchResults[[5]][["productsTable"]]$productNames[1]
)


