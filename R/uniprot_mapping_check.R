library(rvest)
library(xml2)
library(glue)

UNIPROT_API <- 'https://rest.uniprot.org/uniprotkb/{UniProtId}?format=xml'

checkUniProt <- function(UniProtId, geneName) {
  doc <- xml2::read_xml(glue::glue(UNIPROT_API))
  xml2::xml_ns_strip(doc)
  nodeset <- xml2::xml_find_all(doc, xpath = '/uniprot/entry/gene/name[@type="primary"]')
  firstValue <- xml2::xml_text(nodeset[1])
  if (length(nodeset) > 1 || geneName != firstValue) {
    print(paste0(UniProtId, " length: ", length(nodeset)))
#  } else {
#    print(glue::glue('{UniProtId}: {geneName} ok'))
  }
}

checkUniProt('Q6P093', 'AADACL2')