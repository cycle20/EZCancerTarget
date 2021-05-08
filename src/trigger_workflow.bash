#
# trigger_workflow.bash:
#
set -e


[ ! -z "$1" ] && BRANCH="$1" || {
  echo "arg1 (BRANCH) is empty"
  exit 1
}

[ ! -z "$2" ] && WORKFLOW_NAME="$2" || {
  echo "arg2 (WORKFLOW_NAME) is empty"
  exit 1
}

[ ! -z "$3" ] && TOKEN="$3" || {
  echo "arg3 (TOKEN) is empty"
  exit 1
}


# store JSON response from API
REPO_WORKFLOWS="$(
  curl 'https://api.github.com/repos/cycle20/scancer/actions/workflows'
)"

WORKFLOW_URL="$(
  echo "$REPO_WORKFLOWS" | jq -r ".workflows[] \
    | select(.name == \"$WORKFLOW_NAME\" and .state == \"active\") \
    | .url"
)"

PAYLOAD="$(printf '{"ref": "%s"}' $BRANCH)"
curl -H "Authorization: Bearer $TOKEN" -d "$PAYLOAD" "$WORKFLOW_URL/dispatches"
