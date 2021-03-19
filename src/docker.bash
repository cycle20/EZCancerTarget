##
## docker.bash:
## ------------
##
## - start a docker container
## - initialize it
## - exec render R script in the container
##

## variable
CNAME="dtarget"
INAME="r-base:latest"
R_PKGS="r-cran-dplyr r-cran-httr r-cran-readr r-cran-stringr r-cran-whisker"

## https://github.com/rocker-org/rocker/issues/134

##
## tar_content_stdout: helper function to transfer files
function tar_content_stdout() {
  tar -cf - \
    R/renderWebPage.R \
    INPUT/target_list.tsv \
    OUTPUT/clueCollapsed.tsv \
    OUTPUT/string_tab.tsv \
    web/index.proto.html
}


##
## prepare the "infra"
## -------------------
##
sudo docker run -it -d --name "$CNAME" "$INAME" bash

sudo docker container exec "$CNAME" bash -c "dpkg --get-selections | grep 'r-cran'"
sudo docker container exec "$CNAME" bash -c "apt-get update; apt-get install -y $R_PKGS"


##
## prepare the scripts and their inputs
## ------------------------------------
##
tar_content_stdout | sudo docker container cp - "$CNAME:/root"

##
## script exec.
## ------------
##
sudo docker container exec -w /root "$CNAME" bash -c "which Rscript"
sudo docker container exec -w /root "$CNAME" bash -c "Rscript -e 'getwd()'"
sudo docker container exec -w /root "$CNAME" bash -c "Rscript R/renderWebPage.R"

##
## tear down the container
## -----------------------
##
sudo docker container stop "$CNAME"
sudo docker container rm "$CNAME"
