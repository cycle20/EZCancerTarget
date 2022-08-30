Rscript -e 'bookdown::render_book("index.Rmd", "bookdown::gitbook")'

git restore libs
cp -t . _book/reference-keys.txt _book/search_index.json _book/*.html
git add *.html *.txt *.json
