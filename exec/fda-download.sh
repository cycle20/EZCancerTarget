##
## fda-download.sh: downloads fda labels and translates them into smaller JSONs
##

set -x
set -e

FILE_LIST="https://api.fda.gov/download.json"
DLOAD_JSON="fda-filelist.json"
OUTPUT="./OUTPUT"

cd "$OUTPUT"
curl -o "$DLOAD_JSON" "$FILE_LIST"
FILE_LIST=$(
jq '.results.drug | [ .drugsfda.partitions[].file, .label.partitions[].file ]' \
  "$DLOAD_JSON" \
  | grep 'https://' \
  | sed -E 's/[,"]//g'
)

set +x
for current_json in $FILE_LIST; do
  echo -n "Downloading $current_json... "
  curl -s -O "$current_json"
  echo "done"
done
set -x
