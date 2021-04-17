#
##
## uniprot2string_network.bash:
##
## Translate UniProt ID to STRING ID
## (by a curl request)
##
#

OUTFILE="uniprot2string.tsv.gz"
OUTFILE2="expression_uniprot2string.tsv.gz"
UNIPROT_URL="https://uniprot.org/uploadlists/"
UNIPROT_LIST="\
P36897 \
P07333 \
Q9UER7 \
Q99683 \
P31749 \
P46734 \
Q15759 \
P04637 \
P19419 \
P01112 \
P04049 \
Q13233 \
Q02750 \
P45985 \
P27361 \
P45983 \
P01106 \
P23458 \
P42224 \
P52630 \
P40763 \
Q14765 \
P42229 \
P51692 \
P42226 \
Q06124 \
Q07889 \
P42336 \
O60603 \
P63000 \
Q99836 \
P51617 \
Q9Y4K3 \
O43318 \
Q13568 \
Q04206 \
O75676 \
O14733 \
P41279 \
P37173 \
P31751 \
Q9Y243 \
P52564 \
Q16539 \
P53778 \
P36507 \
P28482 \
P45984 \
P53779 \
O60674 \
P52333 \
Q07890 \
P42338 \
O00329 \
P27986 \
O00459 \
Q92569 \
O00206 \
Q9NWZ3 \
P19838 \
O75582 \
P29597"

UNIPROT_LIST2="\
P01375 \
P01574 \
P01584 \
P29459 \
P29460 \
Q9NPF7 \
Q07325 \
P02778 \
O14625 \
P13500 \
P10147 \
P13236 \
P13501 \
P80075 \
P51671 \
P01137 \
P61812 \
P10600 \
P18510 \
P22301 \
P02776 \
O43927 \
P22362 \
Q92583 \
O00626 \
O00175"

##
## Download binding +/-1 input list
##
POST_DATA="\
from=ACC+ID&\
to=STRING_ID&\
format=tab&\
query=$UNIPROT_LIST"

function api_call() {
  POST_DATA=$1
  ## tricky request: there is a redirect
  ## furthermore we have to prevent POST request to GET request translation
  curl -L --post301 -d "$POST_DATA" "$UNIPROT_URL"
}

RESPONSE=$(api_call "$POST_DATA")
echo "$RESPONSE" | \
  sed -e "s/From/uniprot_id/; s/To/string_external_id/;" | \
  gzip -c > \
  "$OUTFILE"
echo "${OUTFILE} saved"


##
## Download input list of expression query
##
POST_DATA2="\
from=ACC+ID&\
to=STRING_ID&\
format=tab&\
query=$UNIPROT_LIST2"

RESPONSE2=$(api_call "$POST_DATA2")
echo "$RESPONSE2" | \
  sed -e "s/From/uniprot_id/; s/To/string_external_id/;" | \
  gzip -c > \
  "$OUTFILE2"
echo "${OUTFILE2} saved"
