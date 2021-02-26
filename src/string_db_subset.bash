#
##
## string_db_subset.bash:
##
## Build schema from specific STRING DB datasets:
## - items schema:    proteins table (only Homo Sapiens rows)
## - network schema:  actions table
##
#

##
## NOTE: awk TSV -> CSV snippet from
## https://stackoverflow.com/a/22421445/10393390
##
## Thanks to Michael Klement
## https://stackoverflow.com/users/45375/mklement0
##


DB_FILE="STRING_DB_SQLITE3.db"
DATA_DIR="INPUT"

## data files
PROTEIN_DATA="$DATA_DIR/STRING/items_proteins_9606.tsv.gz"
NETWORK_DATA="$DATA_DIR/STRING/homo_sapiens__network_actions_v11.0.sql.gz"
# NOTE: This is an older TSV from somewhere (replaced by live API call)
# UNIPROT2STRING_DATA="$DATA_DIR/STRING/human.uniprot_2_string.2018.tsv.gz"
UNIPROT2STRING_DATA="$DATA_DIR/UNIPROT.KB/uniprot2string.tsv.gz"
EXPR_UNIPROT2STRING_DATA="$DATA_DIR/UNIPROT.KB/expression_uniprot2string.tsv.gz"
DRUGCENTRAL_DATA="$DATA_DIR/DrugCentral/drug.target.selected_columns.tsv.gz"

## table names
PROTEIN_TABLE="items_proteins"
NETWORK_TABLE="network_actions"
UNIPROT2STRING_TABLE="uniprot2string"
EXPR_UNIPROT2STRING_TABLE="expr_uniprot2string"
DRUGCENTRAL_TABLE="drugcentral"

## create tables
{
  cat << EOSCHEMA | sqlite3
CREATE TABLE items_proteins (
  protein_id integer,
  protein_external_id character varying(50),
  species_id integer,
  protein_checksum character varying(16),
  protein_size integer,
  annotation character varying(600),
  preferred_name character varying(50),
  annotation_word_vectors text
);

CREATE TABLE network_actions (
  item_id_a integer,
  item_id_b integer,
  mode character varying,
  action character varying,
  is_directional boolean,
  a_is_acting boolean,
  score smallint
);

-- --
-- -- NOTE: this is just an inferred table specification
-- --       based on human.uniprot_2_string.2018.tsv.gz
-- --
-- -- NOTE2: replaced by another table structure due to
-- --        TSV from another source
-- --
-- CREATE TABLE uniprot2string (
--   species_id integer,
--   uniprot_id character varying(50),
--   protein_external_id character varying(50),
-- 
-- --
-- -- Unknown attributes.
-- -- Maybe they are important, maybe they are
-- -- contained by an other table in a STRING schema.
-- --
--   unknown1 numeric,
--   unknown2 numeric
-- );

--
-- UniProt data downloaded from UniProt API.
--
CREATE TABLE uniprot2string (
  uniprot_id character varying(50),
  string_external_id character varying(50)
);
-- Input for expression queries
CREATE TABLE expr_uniprot2string (
  uniprot_id character varying(50),
  string_external_id character varying(50)
);

--
-- DrugCentral data
--
CREATE TABLE drugcentral (
  drug_name TEXT,
  target_name TEXT,
  target_class TEXT,
  action_type TEXT,
  act_comment TEXT,
  accession TEXT,
  gene TEXT,
  swissprot TEXT,
  act_type TEXT,
  act_source TEXT,
  struct_id INTEGER
);

.save ${DB_FILE}
EOSCHEMA
}

##
## function import_from_tsv_gz:
##
## param1 - SQLite3 db file
## param2 - db table name
## param3 - gzipped TSV file
##
function import_from_tsv_gz() {

  DB_FILE=$1
  TABLE_NAME=$2
  TSV_GZ_FILE=$3
  
  {
    zcat "$TSV_GZ_FILE" | \
    awk 'BEGIN {
        FS="\t"; OFS=",";
      }
      {
      rebuilt=0
      for(i=1; i<=NF; ++i) {
        if ($i ~ /,/ && $i !~ /^".*"$/) { 
          gsub("\"", "\"\"", $i)
          $i = "\"" $i "\""
          rebuilt=1 
        }
      }
      if (!rebuilt) { $1=$1 }
      print
    }'
  } | sqlite3 -csv -separator "," \
        -cmd ".import /dev/stdin $TABLE_NAME" \
	"$DB_FILE"
}

##
## STRING imports
##

## import H.Sapiens proteins data
import_from_tsv_gz "$DB_FILE" "$PROTEIN_TABLE" "$PROTEIN_DATA"
## import protein-protein relations
import_from_tsv_gz "$DB_FILE" "$NETWORK_TABLE" "$NETWORK_DATA"
## import UniProt-STRING mapping
import_from_tsv_gz "$DB_FILE" "$UNIPROT2STRING_TABLE" "$UNIPROT2STRING_DATA"
import_from_tsv_gz "$DB_FILE" "$EXPR_UNIPROT2STRING_TABLE" "$EXPR_UNIPROT2STRING_DATA"

##
## Other imports
##

## import DrugCentral data
import_from_tsv_gz "$DB_FILE" "$DRUGCENTRAL_TABLE" "$DRUGCENTRAL_DATA"

