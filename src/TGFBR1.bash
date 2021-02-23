#
##
## TGFBR1.bash:
## ------------
##
## execute query to collect connections of TGFBR1
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

cat src/TGFBR1.sql | sqlite3 -column -cmd ".header on" INPUT/STRING/STRING_DB_SQLITE3.db
