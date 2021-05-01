#
# gh_action__merge_caches.bash:
#
# usage:
#   bash gh_action__merge_caches.bash UNIPROT_CACHE_DIR ARTIFACT_CACHE_DIR
#

# cache dir contains UniProt "historical" files
UNI_CACHE_DIR="$1"
# extracted from GitHub artifcat or created by GitHub action
GH_CACHE_DIR="$2"

UNI_CACHE_FILE="$UNI_CACHE_DIR/UniProt_CacheLines.tsv"
GH_CACHE_FILE="$GH_CACHE_DIR/cache.tsv"

if [ -f "$GH_CACHE_FILE" ]; then
  # exclude UniProt HTML lines
  echo "Merge cache files"
  {
    egrep -v 'https://www.uniprot.org/uniprot/[A-Z0-9]{6,10}\s' "$GH_CACHE_FILE"
    egrep '\.html\s' "$UNI_CACHE_FILE"
  } > new_cache.tsv
  cp new_cache.tsv "$GH_CACHE_FILE"
  tail -30 "$GH_CACHE_FILE"
else
  # just set it as starter cache file
  mkdir -p "$GH_CACHE_DIR"
  mv -v "$UNI_CACHE_FILE" "$GH_CACHE_FILE"
  head -30 "$GH_CACHE_FILE"
fi
