##
## docker.bash:
## ------------
##
## - start a docker container
## - initialize it
## - exec render R script in the container
##

## variables
CNAME="dtarget"
INAME="r-base:latest"
#INAME="dtarget:2022-02-05"
# r-cran-rvest install is replaced by install.packages() call temporarly
# (to get the most recent version)
R_PKGS="r-cran-assertthat r-cran-dplyr r-cran-httr r-cran-readr r-cran-stringr r-cran-xml2 r-cran-whisker"
# prepend dependencies
R_PKGS="libssl-dev libcurl4-openssl-dev libxml2-dev $R_PKGS"
OUTPUT="OUTPUT"

## https://github.com/rocker-org/rocker/issues/134

##
## tar_content_stdout: helper function to transfer files
function tar_content_stdout() {
  tar -cf - \
    .Rprofile \
    renv.lock \
    renv/activate.R \
    R/renderWebPage.R \
    INPUT/string_tab.tsv \
    INPUT/target_list.tsv \
    OUTPUT/targetList.rds \
    OUTPUT/clue_patched.rds \
    web/template.html
}


##
## prepare the "infra"
## -------------------
##
sudo docker run -it -d --name "$CNAME" "$INAME" bash

sudo docker container exec "$CNAME" bash -c "dpkg --get-selections | grep 'r-cran'"
echo "Installing R packages: $R_PKGS"
sudo docker container exec "$CNAME" bash -c "apt-get update; apt-get install -y $R_PKGS"
#echo "Installing rvest package..."
#sudo docker container exec "$CNAME" bash -c "R -e 'install.packages(\"rvest\")'"


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
sudo docker container exec -w /root "$CNAME" bash -c "Rscript -e 'renv::restore()'"
sudo docker container exec -w /root "$CNAME" bash -c "Rscript -e 'getwd()'"
sudo docker container exec -w /root "$CNAME" bash -c "Rscript R/renderWebPage.R"


##
## tear down the container
## -----------------------
##
echo "export result from the container..."
sudo docker container cp "$CNAME:/root" - > "$OUTPUT/render_result.tar"
echo "stop container..."
sudo docker container stop "$CNAME"
echo "remove container..."
sudo docker container rm "$CNAME"
