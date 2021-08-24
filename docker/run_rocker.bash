#
##
## run_rocker.bash:
##   run docker image with development environment
##
#

PASSWORD="${PASSWORD:?$PASSWORD}" # trigger error, if PASSWORD is unset
HOST_SRC_DIR=~/dev/onco/scancer
IMAGE="rocker/tidyverse:R4.1.1"

# it starts the container as a daemon
sudo docker run -d \
  -p 8787:8787 \
  -e PASSWORD="$PASSWORD" \
  -e CLUE_USER_KEY="$CLUE_USER_KEY" \
  -ti \
  --cpus 1 \
  -m 1000m \
  --volume "$HOST_SRC_DIR":/scancer \
  --network host \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  -w /scancer \
  "$IMAGE"
