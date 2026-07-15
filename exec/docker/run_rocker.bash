#
##
## run_rocker.bash:
##   run docker image with development environment
##
#

PASSWORD="${PASSWORD:?$PASSWORD}" # trigger error, if PASSWORD is unset
HOST_SRC_DIR=~/dev/EZCancerTarget
# Development image: R + project library + RStudio Server web IDE (port 8787).
# For the pipeline / tests use the slim runtime image via run_pipeline.bash /
# run_tests.bash (cycle20/ezct:3.1.0).
IMAGE="cycle20/ezct:3.1.0-dev"

[ -d "$HOST_SRC_DIR" ] \
  && {
    echo "Instance will mount directory: $HOST_SRC_DIR";
  } \
  || {
    echo "Directory not found: $HOST_SRC_DIR";
    exit 1;
  }

# it starts the container as a daemon
docker run -d \
  --entrypoint=/init \
  -u 0:0 \
  -p 8787:8787 \
  -e PASSWORD="$PASSWORD" \
  -e CLUE_USER_KEY="$CLUE_USER_KEY" \
  -ti \
  --cpus 1 \
  -m 1000m \
  --volume "$HOST_SRC_DIR":/ezct \
  --network host \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  -w /ezct \
  "$IMAGE"
