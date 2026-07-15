# syntax=docker/dockerfile:1
#
# scancer / EZCancerTarget SLIM RUNTIME image
#
# R 4.6.1 + the project's package library only. Runs the data pipeline and the
# tinytest suite. This is the image used in CI and production.
#
# Base: rocker/r-ver (no RStudio, no Quarto, no esbuild) -> smaller image and a
# smaller attack surface than the tidyverse base. It still ships the Posit
# Package Manager binary repo, so renv::restore() installs binary packages
# (fast, no compiler toolchain needed).
#
# For an interactive RStudio IDE, use the development image (see ./Dockerfile.dev).
FROM rocker/r-ver:4.6.1

# System libraries required by the renv packages. The -dev packages also pull in
# the matching runtime shared libs (libssl, libcurl, libxml2). libuv1t64 is the
# one runtime lib the tidyverse base provided but r-ver does not: the PPM `fs`
# binary links libuv.so.1 (verified by ldd against the 3.0.0 library).
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        libssl-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
        libuv1t64 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Non-root user to own /app and run the pipeline/tests (r-ver has no such user).
RUN useradd --create-home --shell /bin/bash --uid 1000 app

WORKDIR /app

# renv environment configuration (declared before restore so it takes effect).
ENV HOME=/home/app \
    RENV_PATHS_LIBRARY=/home/app/renv-library \
    RENV_PATHS_CACHE=/home/app/.cache/R/renv/cache \
    RENV_CONFIG_CACHE_ENABLED=TRUE \
    RENV_CONFIG_PAK_ENABLED=FALSE

# Restore the R package library from the lockfile. Copy only the files needed
# for restore first so this layer is cached independently of the source code.
COPY --chown=app:app renv.lock renv.lock
COPY --chown=app:app renv/ renv/
COPY --chown=app:app .Rprofile .Rprofile
RUN chown app:app /app

USER app

RUN R -e "install.packages('renv', repos = 'https://packagemanager.posit.co/cran/latest')" \
    && R -e "renv::consent(provided = TRUE)" \
    && R -e "renv::restore()"

# Copy the rest of the project source.
COPY --chown=app:app . .

# Default command self-tests the image. Override the command to run pipeline
# stages, e.g. `docker run --rm cycle20/ezct:3.1.0 R -e 'source("R/clue.R")'`.
# `R` (not `Rscript`) is used so /app/.Rprofile activates the renv library.
CMD ["R", "--quiet", "--no-save", "-e", \
     "res <- tinytest::run_test_dir('inst/tinytest'); print(res); quit(status = as.integer(!all(res)))"]
