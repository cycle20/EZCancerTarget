##
## fda-create-rds.sh:
##
## usage: bash exec/fda-create-rds.sh
##

set -x
set -e

OUTPUT="./OUTPUT"
LABEL_FILES=$(ls "$OUTPUT"/drug-label*.zip)
RDS_FILE="$OUTPUT/fda-label.rds"
UNZIPPED_FIFO="$OUTPUT/unzipped-label-fifo"
EXTRACTED_FIFO="$OUTPUT/extracted-label-fifo"

rm -fv "$OUTPUT"/*-fifo "$RDS_FILE"
mkfifo \
  "$UNZIPPED_FIFO" \
  "$EXTRACTED_FIFO"

set +x
for label_file in $LABEL_FILES; do
  echo -n "Processing $label_file... "
  unzip -p "$label_file" > "$UNZIPPED_FIFO" &
  bash exec/fda-extract.sh "$UNZIPPED_FIFO" > "$EXTRACTED_FIFO" &
  Rscript -e 'source("R/fdaPrepare.R"); main()' "$EXTRACTED_FIFO" "$RDS_FILE"
  echo " done"
done

set -x
rm "$UNZIPPED_FIFO" "$EXTRACTED_FIFO"
