# EZCancerTarget

Collect drug compound data based on editable target table and scan various sources to augment dataset

# Documentation

https://cycle20.github.io/EZCancerTarget/

## Generate GitHub pages from source

```bash
Rscript -e 'bookdown::render_book("index.Rmd", "bookdown::gitbook")'
git restore libs
cp -t . _book/reference-keys.txt _book/search_index.json _book/*.html
git add *.html *.txt *.json
```
