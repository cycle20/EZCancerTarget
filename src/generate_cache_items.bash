#
# generate_cache_items.bash:
# --------------------------
#
# re-using already downloaded files for caching
# (in this case: for PubMed downloads)
#

URL_TMPL="https://pubmed.ncbi.nlm.nih.gov/?term=%s&filter=pubt.clinicaltrial&size=50"

find OUTPUT/DATAPATH_CACHE -name "*pubmed.html" | \
  for fname in $(cat /dev/stdin); do
    bname=$(basename $fname)
    compound=$(echo $bname | sed -e 's/_from_pubmed.html//')
    URL=$(printf "$URL_TMPL\n" "$compound")

    ## Date format by R script in the cache.tsv: 2021-04-13T14:56:36Z

    ## Z at the end of line represents UTC
    ## (conversion forced by TZ environment variable)
    TZ=UTC date --date="@$(stat $fname --printf '%Y')" \
      +"${URL}%t${bname}%t%Y-%m-%dT%R:%SZ"
  done
