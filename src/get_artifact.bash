##
## get_artifact.bash:
##
## Get recent artifact by name
##

echo ...............................................

## set variables
ARTIFACTS_API_URL="$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/actions/artifacts"
TOKEN="$1"
ARTIFACT_NAME="$2"
ARTIFACTS_RESPONSE="artifacts.json"

## query request to get recent 50 artifacts descriptions in JSON
curl "$ARTIFACTS_API_URL?page=1&per_page=50" > "$ARTIFACTS_RESPONSE"
ART_ID=$(
  jq "[ .artifacts[] \
    | select(.name == \"$ARTIFACT_NAME\" and .expired == false) \
    | .id ] \
    | max" "$ARTIFACTS_RESPONSE"
)

## extracted artifact id
echo "ART_ID: is $ART_ID"

# ART_ID check: "null" or "" not allowed
if [ $ART_ID == "null" -o $ART_ID == "" ]; then
  echo Artifact ID not found
  exit 1
  echo ...............................................
else
  SELECTED_ARTIFACT="selected_${ART_ID}.zip"
  DDIR=PREV_RESULT
  mkdir -p "$DDIR"
  SELECTED_ARTIFACT="$DDIR/selected_${ART_ID}.zip"

  ## download the selected artifact
  curl -L --output "$SELECTED_ARTIFACT" \
    --header "authorization: Bearer ${TOKEN}" \
    "$ARTIFACTS_API_URL/$ART_ID/zip"
  md5sum "$SELECTED_ARTIFACT"
  unzip "$SELECTED_ARTIFACT"
  file "$SELECTED_ARTIFACT"
  rm "$SELECTED_ARTIFACT"
  tar --directory="$DDIR" -xzf "$ARTIFACT_NAME"
  md5sum "$ARTIFACT_NAME"
fi
echo ...............................................
