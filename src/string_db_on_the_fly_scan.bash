#
##
## string_db_on_the_fly_scan.bash:
##
## some investigation without saving the huge (75+ GB) file
##
#

###### 25-SET default_tablespace = '';
###### 26-
###### 27-SET default_with_oids = false;
###### 28-
###### 29---
###### 30--- Name: actions; Type: TABLE; Schema: network; Owner: -
###### 31---
###### 32-
###### 33:CREATE TABLE network.actions (
###### 34-    item_id_a integer,
###### 35-    item_id_b integer,
###### 36-    mode character varying,
###### 37-    action character varying,
###### 38-    is_directional boolean,
###### 39-    a_is_acting boolean,
###### 40-    score smallint
###### 41-);
###### 42-
###### 43-
###### 44---
###### 45--- Name: best_combined_scores_orthgroups; Type: TABLE; Schema: network; Owner: -
###### 46---
###### 47-
###### 48:CREATE TABLE network.best_combined_scores_orthgroups (
###### 49-    orthgroup_id integer,
###### 50-    best_score integer
###### 51-);

#  curl --stderr CURL_STDERR.TXT \
#    https://stringdb-static.org/download/network_schema.v11.0.sql.gz | \
#    gzip -dc | \
#

##
## grep -A 100 -E '^COPY|COPY items.proteins'
##

## gzip -dc items_schema.v11.0.sql.gz | grep -E '^.*[[:space:]]9606[[:space:]][[:xdigit:]]{16}' | sed -e '/COPY items.proteins_hierarchical_ogs /q' > items_proteins_9606.tsv


time {
    sed -n -e '/CREATE TABLE network.actions /,/COPY TABLE network.actions/w a.txt
    /COPY TABLE network.actions/q
    ' network_schema_v11.0.GREP_A100.sql
}

