FROM rocker/tidyverse:4.3.2

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

ENV RENV_PATHS_CACHE=/home/rstudio/.cache/R/renv/cache
ENV RENV_CONFIG_CACHE_ENABLED=TRUE
ENV RENV_CONFIG_PAK_ENABLED=TRUE

RUN mkdir -p /home/rstudio/.cache/R/renv \
    && chown -R rstudio:rstudio /home/rstudio/.cache

WORKDIR /app
COPY renv.lock renv.lock
COPY renv/ renv/

RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')" \
    -e "renv::consent(provided = TRUE)" \
    -e "renv::restore()"

COPY . .

RUN chown -R rstudio:rstudio /home/rstudio/.cache \
    && chown -R rstudio:rstudio .
