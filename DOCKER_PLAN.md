# Docker Containerization Plan

## Project Analysis

Based on `.github/workflows/clue.yml` and `renv.lock`:

- **R version**: 4.1.2
- **Dependency management**: renv
- **System libraries needed**: libssl-dev, libcurl4-openssl-dev, libxml2-dev
- **Key R packages**: googlesheets4, dplyr, httr, rvest, xml2, etc.

## Recommended Docker Images

### 1. `rocker/r-ver:4.1.2` (Best match)

Minimal R image matching your exact R version. Use with renv restore:

```dockerfile
FROM rocker/r-ver:4.1.2

RUN apt-get update && apt-get install -y \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY renv.lock renv.lock
RUN R -e "install.packages('renv'); renv::restore()"
COPY . .
```

### 2. `rocker/tidyverse:4.1.2` (Faster builds)

Comes with tidyverse + system libs pre-installed. Many dependencies are already there, so `renv::restore()` will be faster.

### 3. `rocker/r-ver:4.4` (Modern option)

If you want to upgrade R (the workflow's `r-lib/actions/setup-r@v2` installs the latest R anyway), newer rocker images are better maintained.

## Recommendation

Start with `rocker/r-ver:4.1.2` to match the `renv.lock` exactly. If updating R is acceptable, `rocker/tidyverse:4.4` or later will give faster builds and better long-term support since Ubuntu 20.04 and R 4.1.2 are aging.
