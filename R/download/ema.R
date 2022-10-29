##
## ema.R: supply EMA links for clue.io compounds -----------
##

## Usage from command line:
## Rscript -e 'source("R/download/ema.R"); add.EMA.links()'

source("R/dataPatch.R")

add.EMA.links <- function() {
  pertNames <- readRDS("data/pert_list.rds")
  pertNames <- tibble::as_tibble(data.frame(pert_iname = pertNames))
  emaTable <- ema(pertNames)
  saveRDS(emaTable, "data/ema.rds")
}

r <- reportTable %>%
  select(`Active substance`) %>%
  mutate(
    ratio = levitate::lev_ratio(`Active substance`, 'tormetamol'),
    distance = levitate::lev_distance(`Active substance`, 'tormetamol')
  )
View(r)
