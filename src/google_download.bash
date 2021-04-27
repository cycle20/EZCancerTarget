#
# google_download.bash:
#
# Google Drive download utils based on:
# https://gist.github.com/amit-chahar/db49ce64f46367325293e4cce13d2424#gistcomment-2688184
#

fileid="$1"
filename="$2"

## DRIVE_EXPORT_LINK="https://drive.google.com/uc?export=download&id=${fileid}"
## 
## curl -o /dev/null -L --silent --cookie-jar ./cookie "$DRIVE_EXPORT_LINK"
## curl -o ${filename} -L --cookie ./cookie \
##   "${DRIVE_EXPORT_LINK}&confirm=`awk '/download/ {print $NF}' ./cookie`"
## 
## rm cookie

# my simplified version (no cookie and "confirm" stuffs):
curl -o "$filename" -L "https://drive.google.com/uc?export=download&id=$fileid"
