
# input file with perturbagens
INPUT_FILE="src/PRECLINICAL.txt"
# for output data
DATADIR="OUTPUT/Pre-Clinical-check"; mkdir -p "$DATADIR"
URL_TMPL="https://pubmed.ncbi.nlm.nih.gov/?term=%s&filter=pubt.clinicaltrial&size=50"

PERTS=$(cat "$INPUT_FILE")
for pert in $PERTS
do
  echo $pert
  curl -L $(printf $URL_TMPL "$pert") > "$DATADIR/${pert}_from_pubmed.html"
  printf "sleeping 35..."
  sleep 35
  echo "done"
done
