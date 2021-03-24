#
# NA_stats.bash:
# --------------
#
# This is an exploration script to collect
# overview information about our "target database".
#

# global variables
# INPUT vars
PAGE="OUTPUT/index.html"



#
#
function missing_clue_data() {
  echo "============================="
  echo "DO NOT HAVE CLUE.IO DATA:"
  echo "-----------------------------"
  egrep 'has-data-false' "$PAGE" | \
    sed -E 's/^.+#list-(\w+).+$/\1/; /^\s+/d;' | \
    sed -zE '{ s/\n/, /g; }' | \
    sed -Ez 's/(, )$//'

  echo # blank line
  echo "----------"
  printf "# of proteins: "
  egrep -c 'has-data-false' "$PAGE"
}


function main() {
  missing_clue_data
}

main
