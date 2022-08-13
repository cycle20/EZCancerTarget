### Methods

#### `clue.R` and `dataPatch.R` scripts

Target inclusion/exclusion depends on search results from a clue.io query. `EZCancerTarget` consists of 3 separate R scripts. The first script - `clue.R` - calls various clue.io REST API endpoints to build up a result table. If the main API call does not find any component for a target, that target will not be involved in further processing steps since no known drug repurposing approaches are available in clue.io. `clue.R` looks up the input target list in two ways. First, it tries to access a shared Google Sheet file. It requires a unique "key" (a token) given to `clue.R` via a simple environmental variable. If this secret key is available for the script, it authenticates by `gargle` package (Bryan et al, 2022) to access Google Sheet API services. Next, it reads the sheet and takes the values from its first three columns. An ID string also identifies the Google Sheet, and it is passed via an operating system environment. If there is no API key/Google Sheet identifier, then clue.R tries to load a TSV file from the `INPUT` directory of the `EasyCancerTarget` directory. `clue.R` merges the outputs of various clue.io API calls and saves the composing table into an RDS file. It is an R-specific data format to store and load R objects. At the next stage, `dataPatch.R` reads this RDS file and restores the data frame composed by `clue.R`.

_NOTE:_ R scripts of the application are located in the `R` directory of the source tree.

#### `dataPatch.R` functions

##### `fdaLabel` function

`dataPatch.R` collects additional details from external resources. Most of them are used by clue.io itself, but gaps can occur in its dataset. For example _EMA_ data is not included at all, so appending it is an improvement. Another plus is harvesting direct links to drug labels from the search interface of _FDALabel_. `fdaLabel` function implements this feature that contains several internal sub-functions (some of them are anonymous and vectorized). This function then sends a POST HTTP request to a specific _FDALabel_ link - the same that is used by the human search interface to send a query. `fdaLabel` function uses `pert_iname` from clue.io as a search parameter and uses the following parameters to define the search criteria:

* document types of labeling types as documentTypeCodes: `Human Rx 34391-3, Human OTC 34390-5, Vaccine 53404-0`
* labeling section: `selectedLabelingType: 0, sectionTypeCode: Active Ingredient 2-55106-9`
  `fdaLabel` uses its internal function - `getFDALabelResults` - to send the query and interpret the HTTP response from the FDA service.

The result may contain several duplications for a specific product. It is a consequence of FDA strict registration and regulation procedures (products are allowed for different time ranges or can be withdrawn, etc). The function uses a weighting method in order to reduce these duplications and return the most relevant items. `fdaLabel` function filters out products that are parts of aid kits by verifying presence of simple words first `aid|kit|KIT` in product names. It receives responses from the _FDALabel_ service in JSON format. It parses, prioritizes and filters the list of returned drug products based on their market date and match-mode with `pert_iname` (exact, prefix, suffix, inner, not at all). This is a necessary step since the product list contains copies of drugs with only different dates.


##### `pubMed` function

This function searches for the compound name received from clue.io and sends a search request to _PubMed®_ service of _National Center for Biotechnology Information_ (NCBI). It restricts the result set by including only clinical trials, meta-analyses, randomized controlled trials, reviews and systematic reviews. The results are ordered by the best match algorithm of _PubMed®_. Our function picks the top 3 of the result set and stores it in the global datatable. If there is no hit at all, `dataPatch.R` provides the used search URL and this search can be re-initiated and/or refined by users of `EZCancerTarget`. `pubMed` function uses a simple XPath query to extract _PubMed®_ identifiers embedded into the resulting HTML source code.

##### `ema` function

`ema` function complements the dataset with links to drugs' overview pages on the website of _European Medicines Agency_ (EMA). It downloads the summary table of approved drugs from the _EMA_ site and lookups compounds by their 'active substance' property. Each drug has a URL to its overview page. The function pastes it into the dataset, if there is a hit by the name of the active substance.

##### `xmlUniProt` function

This function collects data from the _UniProt_ website. _UniProt_ provides APIs to access and query its data. Easy to access the human readable contents in machine readable formats (for example XML, RDF, etc.). The usage of the _UniProt_ website's REST API is straightforward, since the input target list also contains UniProt identifiers. `xmlUniProt` extracts GO (_Gene Ontology_) molecular function and cellular component terms, _STRING_ and _Reactome_ references from the received XML data. These specific entries are stored in simple R lists and added to the data frame of already collected data in a new column: `UniProtData`.

#### `renderWebPage.R` script

Its main function `renderWebPage`. It is responsible for rendering human-readable HTML documentation from "patched" data produced by `dataPatch.R`. This function iterates on rows of the input table created by `dataPatch.R`. It prepares a compounded, hierarchical data structure from the data table. This data structure helps to simplify data access from the template file which is an important substance of generating out HTML.

##### `multivaluedCellsToHTML` function

A single compound can have multiple related values as elements of various resources. For example a compound can have two Mechanism of Action items (MoA); or a PubChem reference along with a DrugBank reference. These values have to be organized into the same row as the compound and items of the same categories must be displayed in a single table cell. `multivaluedCellsToHTML` function handles these cases. `multivaluedCellsToHTML` function uses these functions to compose corresponding URLs for each identifier from different data sources, including Chembl, PubChem and DrugBank.

#### Presentation layer

A web browser is a "mandatory" software of each end user's computer, so HTML is a clear choice to summarize, visualize and deliver collections of texts, images and hyperlinks. An important part of this rendering is building an HTML source file and populating it with the collected data in an user-friendly way. `EZCancerTarget` follows the popular `Model-View-Controller` design pattern even though it composes only static HTML output (View) from the data (Model) at this stage of the workflow. _(NOTE: Previous actions and functionalities of the workflow can be interpreted as the Controller part of the MVC pattern.)_

##### Templating

Most web frameworks incorporate a templating system - as a result of their own solution or reusing a 3rd party component. These templating components are not tightly coupled with web services, any software can use their power. `EZCancerTarget` uses the _whisker_ package (Salt and Hu 2015), which implements the _Mustache_ template language. This approach excludes any occurance of program source code from the template code. It provides a strict separation for the _View_ layer of `EZCancerTarget`. The structure of the rendered HTML output is based on _Bootstrap_ components and their hierarchy. _(NOTE: The current hierarchical structure and the content of components cannot support a responsible page design. `EZCancerTarget` output is tailored for desktop browsing.)_

##### Dynamic request for STRING network image and a simple cache for HTML/XML contents

Current functionality of `EZCancerTarget` is very similar to a web crawler. This kind of interaction with popular web servers requires respecting their policies controlled by their `robots.txt` files and described in public pages (FAQ, Usage Guideline, Terms of Service etc.) in order to minimize the load on their resources. Respecting their resources also helps to avoid a possible block or denied access from a well-protected website. 

`EZCancerTarget` uses an event-based method, a dynamic DOM modification from JavaScript (see `scancer.js`). If the user opens the STRING accordion of a target content, then the `getSTRING` function (set up as on onclick handler) inserts the image tag. The HTTP request of the STRING network image is initiated by the browser as it modified the Document Object Model and loads the missing/uncached image content to complete the rendering of the missing part of the document. It loads the images belonging to only the visited STRING panels of the document.

The simple cache is also purposed to saving resources on websites. `EZCancerTarget` sends HTTP requests and receives HTTP responses via its `getPageCached` function. This function checks the `cache.tsv` file in the caching folder and returns the content immediately, when it has been already downloaded earlier. If the looked up entry is missing from the cache, the function downloads it and adds it to the cache. This does not just spare remote resources, but it speeds up the subsequent queries to a specific server since `EZCancerTarget` does not need to wait between politely after requests served by the cache-solution.

All the R scripts and description of versions and runtime environment is freely accessible at: https://github.com/cycle20/EZCancerTarget.


