#!/usr/bin/env bash
#
## run_pipeline.bash:
##   run the scancer data pipeline in the SLIM runtime image
##   (cycle20/ezct:3.1.0), non-interactively.
##
## The project directory is bind-mounted at /app so OUTPUT/ persists on the host
## and each stage can read the previous stage's output. Requires CLUE_USER_KEY.
##
## The container's `app` user is uid 1000; on this host the project files are
## owned by uid 1000 as well, so mounted writes land with the right ownership.
##
## Usage:
##   CLUE_USER_KEY=... ./run_pipeline.bash            # run all three stages
##   CLUE_USER_KEY=... ./run_pipeline.bash clue       # run a single stage
##                                                    # (clue | patch | render)
#
set -euo pipefail

IMAGE="${IMAGE:-cycle20/ezct:3.1.0}"
HOST_SRC_DIR="${HOST_SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

: "${CLUE_USER_KEY:?set CLUE_USER_KEY to your clue.io API key}"

run_stage() {
  echo ">>> pipeline stage: $1"
  docker run --rm \
    -e CLUE_USER_KEY \
    --network host \
    --volume "$HOST_SRC_DIR":/app \
    -w /app \
    "$IMAGE" \
    R --quiet --no-save -e "$2"
}

clue()   { run_stage "clue.io collect"  'source("R/clue.R"); main()'; }
patch()  { run_stage "FDA/EMA/UniProt"  'source("R/dataPatch.R"); main()'; }
render() { run_stage "render HTML"      'source("R/renderWebPage.R"); main()'; }

case "${1:-all}" in
  clue)   clue ;;
  patch)  patch ;;
  render) render ;;
  all)    clue; patch; render ;;
  *) echo "unknown stage: $1 (use: clue | patch | render | all)" >&2; exit 2 ;;
esac
