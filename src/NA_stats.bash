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
# count items with no clue.io data
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

function wiki() {
  CHECK_THESE="DNAJC6 DYSPL4 FGF10 FGF5 FOXI1 FZD9 GLTP GRP GZMA"
  for protein in $CHECK_THESE
  do
    echo "$protein"
    curl -I "https://en.wikipedia.org/wiki/$protein"
    sleep 30
    curl "https://en.wikipedia.org/wiki/$protein" > "$protein.html"
    sleep 30
  done
}

function main() {
  missing_clue_data

  mkdir -p "OUTPUT/WIKI"
  pushd OUTPUT/WIKI

  wiki

  echo "Wikipages downloaded"
  popd
}

main
