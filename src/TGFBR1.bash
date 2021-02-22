#
##
## TGFBR1.bash:
## execute query to collection connections of TGFBR1
##
#
cat src/TGFBR1.sql | sqlite3 -column -cmd ".header on" INPUT/STRING/STRING_DB_SQLITE3.db
