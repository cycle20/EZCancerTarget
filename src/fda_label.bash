
# input file with perturbagens
INPUT_FILE="INPUT/fdaPerts.tsv"
# for output data
DATADIR="OUTPUT/FDAperts"; mkdir -p "$DATADIR"
URL='https://nctr-crs.fda.gov/fdalabel/services/spl/summaries'
DATA_TMPL='{"criteria":[{"criteria":[{"sourceEntity":"document-type","documentTypeCodes":["34391-3","34390-5"]},{"sourceEntity":"spl-text","textQuery":"%s","advanced":false}],"logOps":["a","a"]}],"logOps":[]}'

PERTS=$(sort -u "$INPUT_FILE")
for pert in $PERTS
do
  echo $pert
  curl $URL -H 'Connection: keep-alive' \
    -H 'Content-Type: application/json;charset=UTF-8' \
    --data-raw $(printf $DATA_TMPL "$pert") > "$DATADIR/$pert.json"
  printf "sleeping 5..."
  sleep 35
  echo "done"
done
