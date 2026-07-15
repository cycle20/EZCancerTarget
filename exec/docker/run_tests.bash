#!/usr/bin/env bash
#
## run_tests.bash:
##   run the tinytest suite in the SLIM runtime image (cycle20/ezct:3.1.0).
##
## Usage:
##   ./run_tests.bash                       # run the full suite (default CMD)
##   ./run_tests.bash test_scancer.R        # run a single test file
##
## --network host is used because several tests make real HTTP requests to
## external APIs (FDA, UniProt, KEGG, STRING, EMA).
#
set -euo pipefail

IMAGE="${IMAGE:-cycle20/ezct:3.1.0}"

if [ "$#" -ge 1 ]; then
  docker run --rm --network host -w /app "$IMAGE" \
    R --quiet --no-save \
      -e "res <- tinytest::run_test_file('inst/tinytest/$1', verbose = 1)" \
      -e "print(res); quit(status = as.integer(!all(res)))"
else
  # No argument -> the image's default CMD runs the whole inst/tinytest suite.
  docker run --rm --network host "$IMAGE"
fi
