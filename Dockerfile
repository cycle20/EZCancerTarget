FROM rocker/tidyverse:4.3.2

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --chown=rstudio:rstudio renv.lock renv.lock
COPY --chown=rstudio:rstudio renv/ renv/
COPY --chown=rstudio:rstudio .Rprofile .Rprofile
RUN chown rstudio:rstudio /app \
    && R -e "install.packages('renv', repos='https://cloud.r-project.org')"

USER rstudio

# RUN mkdir -p /home/rstudio/.cache/R/renv/cache \
#     && chown -R rstudio:rstudio /home/rstudio/.cache

ENV HOME=/home/rstudio
ENV RENV_PATHS_LIBRARY=/home/rstudio/renv-library
ENV RENV_PATHS_CACHE=/home/rstudio/.cache/R/renv/cache
ENV RENV_CONFIG_CACHE_ENABLED=TRUE
ENV RENV_CONFIG_PAK_ENABLED=FALSE

RUN R -e "renv::consent(provided = TRUE)" \
    -e "renv::restore()"
ENV RENV_CONFIG_PAK_ENABLED=TRUE

COPY --chown=rstudio:rstudio . .
