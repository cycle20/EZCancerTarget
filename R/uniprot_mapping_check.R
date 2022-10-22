library(rvest)
library(xml2)
library(glue)

UNIPROT_API <- 'https://rest.uniprot.org/uniprotkb/{UniProtId}?format=xml'
UNIPROT_DELAY <- 15

checkUniProt <- function(UniProtId, geneName) {
  doc <- xml2::read_xml(glue::glue(UNIPROT_API))
  xml2::xml_ns_strip(doc)
  nodeset <- xml2::xml_find_all(doc, xpath = '/uniprot/entry/gene/name[@type="primary"]')
  firstValue <- xml2::xml_text(nodeset[1])
  if (length(nodeset) > 1 || geneName != firstValue) {
    print(paste0(
      UniProtId, " length: ", length(nodeset),
      " HUGO: ", geneName, " first primary name: ", firstValue
    ))
  } else {
    print(glue::glue('{UniProtId}: {geneName} ok'))
  }
}

# Verify each entry:
uniProtList <- readr::read_tsv('data/full_list.tsv')
lapply(1:nrow(uniProtList), function(rowId) {
  checkUniProt(uniProtList$UNIPROT_KB_ID[rowId], uniProtList$HUGO[rowId])
  Sys.sleep(UNIPROT_DELAY);
})

