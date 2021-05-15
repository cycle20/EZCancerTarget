##
## collectSessionInfo.R:
## ---------------------
## 
## Helper script to document versions of used R packages.
##

filePaths <- c("R/clue.R", "R/dataPatch.R", "R/renderWebPage.R")

# collect source code lines with "library" function calls
usedLibraries <- lapply(filePaths, function(filePath) {
  lines <- readLines(filePath)
  lineNumbers <- grep(lines, pattern = "^library(.+)")
  lines[lineNumbers]
})

# dump these lines into a temporary file
tempFile <- tempfile()

cat(
  unique(unlist(usedLibraries)), sep = "\n", file = tempFile
)








# load libraries silently
suppressPackageStartupMessages(
  source(tempFile)
)


## print session informations #############################
cat("


## SESSION INFO: ##########################################


")

sessionInfo()
