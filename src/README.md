# scancer/src: file list of script folder

* *src/load_uniprot_ids.bash:* loads STRING-UniProtKB mapping table from a TSV file into the database. TSV structure: first column: STRING external identifier; second column: UniProtKB identifier. The script transforms lines to SQL UPDATE-statements and UNIPROT\_KB\_ID of the extended ITEMS\_PROTEINS table gets its value based on the PROTEIN\_EXTERNAL\_ID attribute.
* *string_db_on_the_fly_scan.bash:* script to download (with no saving), extract and filter the very large *network_schema.v11.0.sql.gz* file.
* *string_db_subset.bash:* build SQLite3 DB file from TSV files. It is just a subset of the whole STRING database.
* *uniprot2string_network.bash:* download STRING translation of its UniProt Id list.

Prototype files of network extractions
----

These files will be renamed and be more general to work with a list of identifiers.

* *network_associations.bash:* execute query to collect connections of items in table *uniprot2string*.
* *network_associations.sql:* SQL SELECT statement to get some demo data.
