#
##
## load_uniprot_ids.bash:
## ----------------------
##
#
set -u
SCRIPT="$(basename $0)"

INPUT="${1:-INPUT.PPI.MODEL/string_external_to_uniprot.tsv}"
DATA_DIR="INPUT"
DB_FILE="$DATA_DIR/STRING_DB_SQLITE3.db"

echo "$SCRIPT: INPUT=$INPUT"
echo "$SCRIPT: DB_FILE=$DB_FILE"

AWK_PROGRAM=$(cat<<EOF
{
  printf "update ITEMS_PROTEINS";
  printf " set UNIPROT_KB_ID = '%s'", \$2;
  printf " where PROTEIN_EXTERNAL_ID = '%s';\n", \$1;
}
EOF
)

cat "$INPUT" | \
  sed -e 1d | \
  awk -F'\t' -e "$AWK_PROGRAM" | \
  sqlite3 "$DB_FILE"
