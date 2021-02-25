# scancer/src: file list of script folder

* *string_db_on_the_fly_scan.bash:* script to download (with no saving), extract and filter the very large *network_schema.v11.0.sql.gz* file.
* *string_db_subset.bash:* build SQLite3 DB file from TSV files. It just a subset of the whole STRING database.
* *uniprot2string_network.bash:* download STRING translation of its UniProt Id list.

Prototype files of network extractions
----

These files will be renamed and be more general to work with a list of identifiers.

* *network_associations.bash:* execute query to collect connections of items in table *uniprot2string*.
* *network_associations.sql:* SQL SELECT statement to get some demo data.
