##
## wrap_directory.bash:
##
## bash [-x] src/wrap_directory.bash ARCHIVE_FILE_NAME SOURCE_DIR
##

INPUT_DIR="$2"
[ -d "$INPUT_DIR" ] && tar --directory="$INPUT_DIR" -cvzf "$1" $(ls $INPUT_DIR)
