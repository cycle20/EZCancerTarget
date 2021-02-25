#
##
## network_associations.bash:
## -------------------------
##
## execute query to collect connections for
## proteins from uniprot2string DB table.
##
#

##
## semantics of query (in pseudo code)
## -----------------------------------
##
## IF mode = binding
## THEN
##   get each connection
##   IF list of "action" contains "inhibition"
##   THEN
##     RETURN +1
##   ELSE
##     RETURN -1
##   ENDIF
## ENDIF
## ELSE
##   RETURN -1
## ENDIF
##

cat src/network_associations.sql | sqlite3 -csv -cmd ".header on" INPUT/STRING/STRING_DB_SQLITE3.db
