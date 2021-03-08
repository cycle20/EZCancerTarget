#
## string_download_data.bash:
## --------------------------
## TODO: in progress...
##
#

OUTFILE="missing_uniprot.tsv"
UNIPROT_URL="https://uniprot.org/uploadlists/"

cd INPUT

curl -O https://stringdb-static.org/download/protein.aliases.v11.0/9606.protein.aliases.v11.0.txt.gz
curl -O https://string-db.org/mapping_files/uniprot/human.uniprot_2_string.2018.tsv.gz
#curl -O https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/idmapping/by_organism/HUMAN_9606_idmapping.dat.gz
curl -O https://ftp.uniprot.org/pub/databases/uniprot/current_release/knowledgebase/idmapping/by_organism/HUMAN_9606_idmapping_selected.tab.gz


## STRING API call to get missing values: no result from the API
STRING_EXTERNAL_IDS="\
ENSP00000374424 \
ENSP00000479860 \
ENSP00000452479 \
ENSP00000243314 \
ENSP00000485396 \
ENSP00000479106 \
ENSP00000358155 \
ENSP00000313571 \
ENSP00000455510 \
ENSP00000379842 \
ENSP00000353874"

POST_DATA="\
from=STRING_ID&\
to=ACC&\
format=tab&\
query=$STRING_EXTERNAL_IDS"

function api_call() {
  POST_DATA=$1
  ## tricky request: there is a redirect
  ## furthermore we have to prevent POST request to GET request translation
  curl -L --post301 -d "$POST_DATA" "$UNIPROT_URL"
}

RESPONSE=$(api_call "$POST_DATA")
echo "$RESPONSE" | \
  sed -e "s/From/string_external_id/; s/To/uniprot_id/;" > \
  "$OUTFILE"
echo "${OUTFILE} saved"
