#
##
## binding_query.bash:
## -------------------
##
## execute query to collect connections for
## proteins from uniprot2string DB table.
##
#

##
## semantics of query (in pseudo code)
## -----------------------------------
##
## IF mode = binding AND mode = inhibition
## THEN
##   RETURN +1
## ELSE IF mode = binding AND mode != inhibition
##   RETURN -1
## ENDIF
##
function message() {
  echo "$1" >> /dev/stderr
}


##
## binding_inhibition_query:
## -------------------------
##
## Run network_associations.sql
##
function binding_inhibition_query() {
  message "$FNAME: binding/inhibition query starting..."

  cat src/binding_query.sql | \
    sqlite3 -csv -cmd "${1:-}" \
    INPUT/STRING/STRING_DB_SQLITE3.db

  message "$FNAME: binding/inhibition query done."
}


##
## call_uniprot_api:
## -----------------
##
## Reads STRING external IDs from its standard input,
## then call uniprot API endpoint to download the
## matching UniProtKB IDs.
##
function call_uniprot_api() {
  local FNAME=${FUNCNAME[0]}

  message "$FNAME: assembling HTTP POST data for UniProt API call..."
  local POST_DATA="from=STRING_ID&to=ACC&format=tab&query=$(cat < /dev/stdin)"
  message "$FNAME: assembling HTTP POST data done."

  message "$FNAME: calling UniProt API endpoint..."
  time curl -L --post301 -d "$POST_DATA" "https://uniprot.org/uploadlists/"

  message "$FNAME: calling UniProt API endpoint done."
}


##
## download_missing_uniprot_ids:
## -----------------------------
##
## Collect STRING external ids from the query result and
## call uniprot API endpoint to get matching UniProtKB Ids.
##
# function download_missing_uniprot_ids() {
#   local FNAME=${FUNCNAME[0]}
# 
#   message "$FNAME: starting query..."
# 
#   time binding_inhibition_query | \
#   egrep '(^,)|(,,)' | \
#     sed -e '1d' | \
#     awk -F, '{ print $5, $6; }' | \
#     tr ' ' '\n' | \
#     sort -u | \
#     tr '\n' ' ' | \
#     call_uniprot_api
# 
#   message "$FNAME: query done."
# }

#".header on"

# download_missing_uniprot_ids

binding_inhibition_query ".header on"
