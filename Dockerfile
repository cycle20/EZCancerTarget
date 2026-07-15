# syntax=docker/dockerfile:1
#
# scancer / EZCancerTarget runtime image
#
# Base: rocker/tidyverse pins both R and a dated Posit Package Manager (PPM)
# snapshot, so package versions are reproducible. Bumping the tag is the main
# security win (newer Ubuntu base -> fewer OS CVEs, newer R + packages).
FROM rocker/tidyverse:4.6.1

# System libraries required to build the renv packages that are not already
# provided by the tidyverse base image.
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        libssl-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# renv environment configuration (declared before restore so it takes effect).
ENV HOME=/home/rstudio \
    RENV_PATHS_LIBRARY=/home/rstudio/renv-library \
    RENV_PATHS_CACHE=/home/rstudio/.cache/R/renv/cache \
    RENV_CONFIG_CACHE_ENABLED=TRUE \
    RENV_CONFIG_PAK_ENABLED=FALSE

# Restore the R package library from the lockfile. Copy only the files needed
# for restore first so this layer is cached independently of the source code.
COPY --chown=rstudio:rstudio renv.lock renv.lock
COPY --chown=rstudio:rstudio renv/ renv/
COPY --chown=rstudio:rstudio .Rprofile .Rprofile
RUN chown rstudio:rstudio /app

USER rstudio

RUN R -e "install.packages('renv', repos = 'https://packagemanager.posit.co/cran/latest')" \
    && R -e "renv::consent(provided = TRUE)" \
    && R -e "renv::restore()"

# Copy the rest of the project source.
COPY --chown=rstudio:rstudio . .
