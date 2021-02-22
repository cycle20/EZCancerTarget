#
##
## uniprot2string_network.bash:
##
## Translate UniProt ID to STRING ID
## (by a curl request)
##
#

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
O75582"

POST_DATA="\
from=ACC+ID&\
to=STRING_ID&\
format=tab&\
query=$UNIPROT_LIST"

## tricky request: there is a redirect
## furthermore we have to prevent POST request to GET request translation
RESPONSE=$(curl -L --post301 -d "$POST_DATA" "$UNIPROT_URL")

echo "$RESPONSE"
